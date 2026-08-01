import assert from "node:assert/strict";
import test from "node:test";
import {
  appendHistorySample,
  historyCoverageMinutes,
  historyValuesInWindow,
  loadTrendDomain,
  mergeHistorySamples,
} from "../src/status-history.mjs";

test("retains one sampled TPS point per interval while keeping the latest value", () => {
  let history = [];
  history = appendHistorySample(history, { at: "2026-07-29T00:00:00.000Z", tps: 10 });
  history = appendHistorySample(history, { at: "2026-07-29T00:00:01.000Z", tps: 20 });
  history = appendHistorySample(history, { at: "2026-07-29T00:00:05.000Z", tps: 30 });

  assert.deepEqual(history, [
    { at: "2026-07-29T00:00:00.000Z", tps: 20 },
    { at: "2026-07-29T00:00:05.000Z", tps: 30 },
  ]);
});

test("filters a real time window instead of assuming a sample count", () => {
  const now = new Date("2026-07-29T01:00:00.000Z").valueOf();
  const history = [
    { at: "2026-07-29T00:20:00.000Z", tps: 10 },
    { at: "2026-07-29T00:35:00.000Z", tps: 20 },
    { at: "2026-07-29T00:55:00.000Z", tps: 30 },
  ];

  assert.deepEqual(historyValuesInWindow(history, 30 * 60 * 1_000, now), [20, 30]);
});

test("merges a short server history without discarding longer client coverage", () => {
  const existing = [
    { at: "2026-07-29T00:00:00.000Z", tps: 10 },
    { at: "2026-07-29T00:10:00.000Z", tps: 20 },
  ];
  const incoming = [
    { at: "2026-07-29T00:10:00.000Z", tps: 25 },
    { at: "2026-07-29T00:11:00.000Z", tps: 30 },
  ];

  assert.deepEqual(mergeHistorySamples(existing, incoming), [
    { at: "2026-07-29T00:00:00.000Z", tps: 10 },
    { at: "2026-07-29T00:10:00.000Z", tps: 25 },
    { at: "2026-07-29T00:11:00.000Z", tps: 30 },
  ]);
  assert.equal(historyCoverageMinutes(mergeHistorySamples(existing, incoming)), 11);
});

test("focuses a high-load trend on its real variation without inventing noise", () => {
  const values = [46_212, 59_717, 51_628];
  const [minimum, maximum] = loadTrendDomain(values);

  assert.ok(minimum > 0);
  assert.ok(minimum < Math.min(...values));
  assert.ok(maximum > Math.max(...values));
  assert.ok((Math.max(...values) - Math.min(...values)) / (maximum - minimum) > 0.7);
  assert.deepEqual(loadTrendDomain([50_000, 50_000]), [46_280, 53_720]);
  assert.deepEqual(loadTrendDomain([0, 50_000]), [0, 50_000 / 0.92]);
});
