import assert from "node:assert/strict";
import test from "node:test";
import {
  loadFlowChannels,
  loadParticlePhase,
  loadState,
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
  assert.equal(heavy.beamCount, 3);
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
  assert.equal(idle.travelSeconds, 3.1);
  assert.ok(idle.score >= 0 && idle.score <= 1);
});

test("keeps missing CPU telemetry distinct from a measured zero", () => {
  assert.equal(singleMachineLoad({ cpuPercent: null }).cpu, null);
  assert.equal(singleMachineLoad({ cpuPercent: "" }).cpu, null);
  assert.equal(singleMachineLoad({ cpuPercent: 0 }).cpu, 0);
});

test("does not call high token activity constrained when CPU is unknown", () => {
  const load = singleMachineLoad({
    oneMinute: { tps: 60_000 },
    activeSessions: 10,
    cpuPercent: null,
  });

  assert.equal(load.constrained, false);
  assert.notEqual(loadState(load.score, load).definition.id, "constrained");
});

test("uses measured host pressure for constrained state, including a valid zero", () => {
  const constrained = singleMachineLoad({
    oneMinute: { tps: 60_000 },
    activeSessions: 10,
    cpuPercent: 97,
  });
  const idleZero = singleMachineLoad({
    oneMinute: { tps: 0 },
    activeSessions: 0,
    cpuPercent: 0,
  });

  assert.equal(constrained.constrained, true);
  assert.equal(loadState(constrained.score, constrained).definition.id, "constrained");
  assert.equal(idleZero.cpu, 0);
  assert.equal(idleZero.constrained, false);
});

test("maps aggregate work into varied parallel flow without implying per-conversation telemetry", () => {
  const channels = loadFlowChannels(singleMachineLoad({
    oneMinute: { tps: 60_000 },
    activeSessions: 10,
    cpuPercent: 88,
  }));

  assert.equal(channels.length, 3);
  assert.ok(channels.every((channel) => channel.active));
  assert.ok(new Set(channels.map((channel) => channel.travelMs)).size > 1);
  assert.ok(channels.every((channel) => channel.packetCount >= 5));
  assert.ok(new Set(channels.map((channel) => channel.center)).size > 1);
});

test("uses absolute elapsed time for flow particles so kiosk motion catches up after throttling", () => {
  assert.equal(loadParticlePhase(0, 1_000, 0), 0);
  assert.equal(loadParticlePhase(250, 1_000, 0), .25);
  assert.equal(loadParticlePhase(12_250, 1_000, 0), .25);
  assert.equal(loadParticlePhase(750, 1_000, .5), .25);
});
