import assert from "node:assert/strict";
import test from "node:test";
import {
  appendHistorySample,
  historyValuesInWindow,
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
