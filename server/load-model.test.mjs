import assert from "node:assert/strict";
import test from "node:test";
import { singleMachineLoad } from "../src/load-model.mjs";

test("maps higher aggregate work to more, denser, faster flow", () => {
  const light = singleMachineLoad({
    oneMinute: { tps: 240 },
    activeSessions: 1,
    cpuPercent: 28,
  });
  const heavy = singleMachineLoad({
    oneMinute: { tps: 1_600 },
    activeSessions: 7,
    cpuPercent: 88,
  });

  assert.ok(heavy.score > light.score);
  assert.ok(heavy.laneCount > light.laneCount);
  assert.equal(heavy.laneCount, 5);
  assert.ok(heavy.density > light.density);
  assert.ok(heavy.travelSeconds < light.travelSeconds);
});

test("keeps an idle machine still and bounds the visual controls", () => {
  const idle = singleMachineLoad({
    oneMinute: { tps: 0 },
    activeSessions: 0,
    cpuPercent: null,
  });

  assert.equal(idle.laneCount, 0);
  assert.equal(idle.density, 0.12);
  assert.equal(idle.travelSeconds, 2.8);
  assert.ok(idle.score >= 0 && idle.score <= 1);
});
