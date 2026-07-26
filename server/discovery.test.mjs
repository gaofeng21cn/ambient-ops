import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  createDiscoveryPublisher,
  normalizeDiscoveryHost,
  normalizeInstanceId,
  resolveInstanceId,
} from "./discovery.mjs";

test("persists a stable generated discovery instance id", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-discovery-"));
  const first = await resolveInstanceId(dataDir);
  const second = await resolveInstanceId(dataDir);

  assert.match(first, /^ao-[a-f0-9]{16}$/);
  assert.equal(second, first);
});

test("accepts only DNS-SD-safe configured instance ids", () => {
  assert.equal(normalizeInstanceId("Home-Ops.1"), "home-ops.1");
  assert.equal(normalizeInstanceId("../unsafe"), "");
  assert.equal(normalizeInstanceId("contains spaces"), "");
});

test("publishes a resolvable local discovery hostname", () => {
  assert.equal(normalizeDiscoveryHost("ambient-nas"), "ambient-nas.local");
  assert.equal(normalizeDiscoveryHost("ambient-nas.local."), "ambient-nas.local");
  assert.equal(normalizeDiscoveryHost("invalid host", "fallback-nas"), "fallback-nas.local");
});

test("publishes the shared Ambient Ops discovery contract", async () => {
  let published;
  let destroyed = false;
  const bonjour = {
    publish(options) {
      published = options;
      return { stop() {} };
    },
    unpublishAll(callback) {
      callback();
    },
    destroy() {
      destroyed = true;
    },
  };
  const publisher = createDiscoveryPublisher({
    instanceId: "home-ops",
    name: "Example Home",
    host: "ambient-nas",
    port: 8791,
    version: "0.1.4",
    bonjour,
  });

  publisher.start();
  assert.deepEqual(published, {
    name: "Example Home",
    host: "ambient-nas.local",
    type: "ambient-ops",
    protocol: "tcp",
    port: 8791,
    txt: {
      id: "home-ops",
      name: "Example Home",
      path: "/display/overview",
      api: "/api/status",
      protocol: "1",
      pairing: "1",
      version: "0.1.4",
    },
  });
  await publisher.stop();
  assert.equal(destroyed, true);
});
