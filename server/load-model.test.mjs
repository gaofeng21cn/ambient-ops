import assert from "node:assert/strict";
import test from "node:test";
import {
  loadFlowChannels,
  loadParticlePhase,
  singleMachineLoad,
} from "../src/load-model.mjs";

test("maps higher aggregate work to more, denser, faster flow", () => {
  const light = singleMachineLoad({
    oneMinute: { tps: 240 },
    activeSessions: 1,
    cpuPercent: 28,
  });
  const heavy = singleMachineLoad({
    oneMinute: { tps: 60_000 },
    activeSessions: 10,
    cpuPercent: 88,
  });

  assert.ok(heavy.score > light.score);
  assert.ok(heavy.beamCount > light.beamCount);
  assert.equal(heavy.beamCount, 4);
  assert.ok(heavy.density > light.density);
  assert.ok(heavy.travelSeconds < light.travelSeconds);
});

test("keeps an idle machine still and bounds the visual controls", () => {
  const idle = singleMachineLoad({
    oneMinute: { tps: 0 },
    activeSessions: 0,
    cpuPercent: null,
  });

  assert.equal(idle.beamCount, 0);
  assert.equal(idle.density, 0);
  assert.equal(idle.travelSeconds, 2.8);
  assert.ok(idle.score >= 0 && idle.score <= 1);
});

test("maps aggregate work into varied parallel flow without implying per-conversation telemetry", () => {
  const channels = loadFlowChannels(singleMachineLoad({
    oneMinute: { tps: 60_000 },
    activeSessions: 10,
    cpuPercent: 88,
  }));

  assert.equal(channels.length, 4);
  assert.ok(channels.every((channel) => channel.active));
  assert.ok(new Set(channels.map((channel) => channel.travelMs)).size > 1);
  assert.ok(channels.every((channel) => channel.packetCount >= 4));
  assert.ok(new Set(channels.map((channel) => channel.center)).size > 1);
});

test("uses absolute elapsed time for flow particles so kiosk motion catches up after throttling", () => {
  assert.equal(loadParticlePhase(0, 1_000, 0), 0);
  assert.equal(loadParticlePhase(250, 1_000, 0), .25);
  assert.equal(loadParticlePhase(12_250, 1_000, 0), .25);
  assert.equal(loadParticlePhase(750, 1_000, .5), .25);
});
