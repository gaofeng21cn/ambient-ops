import test from "node:test";
import assert from "node:assert/strict";
import { calculateThroughput, counter64, createUnifiSnmpPoller, selectInterfaces } from "./unifi-snmp.mjs";

const sample = (at, interfaces) => ({ sampledAt: new Date(at), interfaces });

test("decodes an unsigned 64-bit SNMP counter without precision loss", () => {
  assert.equal(counter64(Buffer.from("0020000000000001", "hex")), 9_007_199_254_740_993n);
});

test("selects WAN interfaces by index, name, or alias", () => {
  const current = sample("2026-07-25T00:00:00.000Z", [
    { index: 7, name: "eth7", alias: "WAN2" },
    { index: 8, name: "eth8", alias: "WAN" },
    { index: 9, name: "br0", alias: "LAN" },
  ]);
  assert.deepEqual(selectInterfaces(current, ["8", "WAN2"]).map((entry) => entry.index), [7, 8]);
});

test("calculates aggregate dual-WAN throughput from Counter64 deltas", () => {
  const previous = sample("2026-07-25T00:00:00.000Z", [
    { index: 7, name: "eth7", alias: "WAN2", inOctets: 1000n, outOctets: 2000n },
    { index: 8, name: "eth8", alias: "WAN", inOctets: 3000n, outOctets: 4000n },
  ]);
  const current = sample("2026-07-25T00:00:02.000Z", [
    { index: 7, name: "eth7", alias: "WAN2", inOctets: 251_001_000n, outOctets: 25_002_000n },
    { index: 8, name: "eth8", alias: "WAN", inOctets: 253_003_000n, outOctets: 29_004_000n },
  ]);
  const result = calculateThroughput(previous, current, [7, 8]);
  assert.equal(result.downloadMbps, 2016);
  assert.equal(result.uploadMbps, 216);
  assert.equal(result.interfaces.length, 2);
});

test("poller establishes a baseline before returning live data", async () => {
  const samples = [
    sample("2026-07-25T00:00:00.000Z", [
      { index: 8, name: "eth8", alias: "WAN", inOctets: 0n, outOctets: 0n },
    ]),
    sample("2026-07-25T00:00:01.000Z", [
      { index: 8, name: "eth8", alias: "WAN", inOctets: 125_000_000n, outOctets: 12_500_000n },
    ]),
  ];
  const client = { readInterfaces: async () => samples.shift() };
  const poll = createUnifiSnmpPoller({
    interfaces: ["eth8"],
    pollMs: 1,
  }, client);
  const result = await poll();
  assert.equal(result.source, "unifi-snmp-v3");
  assert.equal(result.downloadMbps, 1000);
  assert.equal(result.uploadMbps, 100);
});

test("poller smooths one-second counter updates across four output samples", async () => {
  const samples = Array.from({ length: 9 }, (_, index) => {
    const seconds = index * 0.25;
    const counterStep = Math.floor(seconds);
    return sample(new Date(Date.UTC(2026, 6, 25, 0, 0, 0, index * 250)), [
      {
        index: 8,
        name: "eth8",
        alias: "WAN",
        inOctets: BigInt(counterStep * 12_500_000),
        outOctets: BigInt(counterStep * 1_250_000),
      },
    ]);
  });
  const client = { readInterfaces: async () => samples.shift() };
  const poll = createUnifiSnmpPoller({
    interfaces: ["eth8"],
    pollMs: 1,
    rateWindowMs: 1000,
  }, client);

  const results = [];
  for (let index = 0; index < 8; index += 1) results.push(await poll());

  assert.deepEqual(results.slice(3).map(({ downloadMbps }) => downloadMbps), [100, 100, 100, 100, 100]);
  assert.deepEqual(results.slice(3).map(({ uploadMbps }) => uploadMbps), [10, 10, 10, 10, 10]);
});

test("two-second window bridges an irregular 1.5 second counter refresh", async () => {
  const samples = Array.from({ length: 13 }, (_, index) => {
    const counterStep = Math.floor(index / 6);
    return sample(new Date(Date.UTC(2026, 6, 25, 0, 0, 0, index * 250)), [
      {
        index: 8,
        name: "eth8",
        alias: "WAN",
        inOctets: BigInt(counterStep * 18_750_000),
        outOctets: BigInt(counterStep * 1_875_000),
      },
    ]);
  });
  const client = { readInterfaces: async () => samples.shift() };
  const poll = createUnifiSnmpPoller({
    interfaces: ["eth8"],
    pollMs: 1,
    rateWindowMs: 2000,
  }, client);

  const results = [];
  for (let index = 0; index < 12; index += 1) results.push(await poll());

  const settled = results.slice(5);
  assert.ok(settled.every(({ downloadMbps, uploadMbps }) => downloadMbps > 0 && uploadMbps > 0));
  assert.ok(Math.abs(average(settled.map(({ downloadMbps }) => downloadMbps)) - 100) < 10);
  assert.ok(Math.abs(average(settled.map(({ uploadMbps }) => uploadMbps)) - 10) < 1);
});

test("poller clears its baseline and closes the session after a read failure", async () => {
  const samples = [
    sample("2026-07-25T00:00:00.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 100n, outOctets: 50n },
    ]),
    new Error("temporary route failure"),
    sample("2026-07-25T00:00:02.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 200n, outOctets: 100n },
    ]),
    sample("2026-07-25T00:00:03.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 300n, outOctets: 150n },
    ]),
  ];
  let closed = false;
  const client = {
    readInterfaces: async () => {
      const next = samples.shift();
      if (next instanceof Error) throw next;
      return next;
    },
    close: () => { closed = true; },
  };
  const poll = createUnifiSnmpPoller({
    interfaces: ["23"],
    pollMs: 1,
  }, client);

  await assert.rejects(poll(), /temporary route failure/);
  assert.equal(closed, true);
  const recovered = await poll();
  assert.equal(recovered.status, "live");
  assert.ok(recovered.downloadMbps > 0);
});

test("poller does not calculate across a failed baseline", async () => {
  const samples = [
    new Error("temporary route failure"),
    sample("2026-07-25T00:00:02.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 200n, outOctets: 100n },
    ]),
    sample("2026-07-25T00:00:03.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 300n, outOctets: 150n },
    ]),
  ];
  let closed = false;
  const client = {
    readInterfaces: async () => {
      const next = samples.shift();
      if (next instanceof Error) throw next;
      return next;
    },
    close: () => { closed = true; },
  };
  const poll = createUnifiSnmpPoller({
    interfaces: ["23"],
    pollMs: 1,
  }, client);

  await assert.rejects(poll(), /temporary route failure/);
  assert.equal(closed, true);
  const recovered = await poll();
  assert.equal(recovered.status, "live");
  assert.ok(recovered.downloadMbps > 0);
});

test("poller rebuilds its baseline after a Counter64 reset", async () => {
  const samples = [
    sample("2026-07-25T00:00:00.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 900n, outOctets: 900n },
    ]),
    sample("2026-07-25T00:00:01.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 100n, outOctets: 100n },
    ]),
    sample("2026-07-25T00:00:02.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 200n, outOctets: 200n },
    ]),
    sample("2026-07-25T00:00:03.000Z", [
      { index: 23, name: "eth7", alias: "WAN", inOctets: 300n, outOctets: 300n },
    ]),
  ];
  const client = { readInterfaces: async () => samples.shift() };
  const poll = createUnifiSnmpPoller({
    interfaces: ["23"],
    pollMs: 1,
  }, client);

  const recovered = await poll();
  assert.equal(recovered.status, "live");
  assert.ok(recovered.downloadMbps > 0);
});

function average(values) {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}
