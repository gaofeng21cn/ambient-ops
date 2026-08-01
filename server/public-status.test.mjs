import assert from "node:assert/strict";
import test from "node:test";
import {
  buildPublicStatus,
  PUBLIC_STATUS_PATH,
  PUBLIC_STATUS_SCHEMA_VERSION,
} from "./public-status.mjs";

test("projects the dashboard into a versioned mobile contract", () => {
  const status = buildPublicStatus({
    generatedAt: "2026-07-31T00:00:00.000Z",
    demo: false,
    site: { name: "Home", timeZone: "Asia/Shanghai" },
    overallStatus: "live",
    network: { status: "live", history: [] },
    codex: { status: "live", oneMinuteTps: 60000 },
    fleet: {
      status: "live",
      oneMinuteTps: 60000,
      activeSessions: 10,
      cpuPercent: 97,
      liveMachineCount: 1,
      workingMachineCount: 1,
      tpsHistory: [{ at: "2026-07-30T23:59:55.000Z", tps: 58000 }],
    },
    machines: [{
      machineId: "studio",
      machineName: "Studio",
      status: "live",
      oneMinute: { tps: 60000 },
      fiveMinutes: { tps: 42000 },
      activeSessions: 10,
      cpuPercent: 97,
      tpsHistory: [{ at: "2026-07-30T23:59:55.000Z", tps: 58000 }],
    }],
  }, {
    instanceId: "home-ops",
    serverVersion: "1.2.3",
  });

  assert.equal(PUBLIC_STATUS_PATH, "/api/v1/status");
  assert.equal(status.schemaVersion, PUBLIC_STATUS_SCHEMA_VERSION);
  assert.equal(status.serverVersion, "1.2.3");
  assert.equal(status.instanceId, "home-ops");
  assert.deepEqual(status.provider, {
    kind: "gateway",
    scope: "fleet",
    id: "home-ops",
    name: "Home",
  });
  assert.equal(status.capabilities.network, true);
  assert.equal(status.capabilities.loadVisualState, true);
  assert.equal(status.capabilities.machineHistory, true);
  assert.equal(status.capabilities.persistentHistory, true);
  assert.equal(status.capabilities.fleetHistory, true);
  assert.equal(status.capabilities.hostNetwork, true);
  assert.equal(status.capabilities.webDisplay, true);
  assert.equal(status.capabilities.liveActivityPush, false);
  assert.equal(status.machines[0].loadVisualState.modelVersion, 1);
  assert.equal(status.machines[0].loadVisualState.state, "constrained");
  assert.ok(status.machines[0].loadVisualState.taskDensity > 0.8);
  assert.deepEqual(status.machines[0].tpsHistory, [
    { at: "2026-07-30T23:59:55.000Z", tps: 58000 },
  ]);
  assert.equal(status.fleet.loadVisualState.state, "constrained");
  assert.deepEqual(status.fleet.tpsHistory, [
    { at: "2026-07-30T23:59:55.000Z", tps: 58000 },
  ]);
});

test("preserves unknown CPU as activity rather than invented pressure", () => {
  const status = buildPublicStatus({
    generatedAt: "2026-07-31T00:00:00.000Z",
    demo: true,
    site: { name: "Demo", timeZone: "UTC" },
    overallStatus: "live",
    network: { status: "live", history: [] },
    codex: { status: "live" },
    fleet: {
      status: "live",
      oneMinuteTps: 60000,
      activeSessions: 10,
      cpuPercent: null,
      liveMachineCount: 1,
      workingMachineCount: 1,
    },
    machines: [{
      machineId: "mac",
      machineName: "Mac",
      oneMinute: { tps: 60000 },
      activeSessions: 10,
      cpuPercent: null,
    }],
  });

  assert.equal(status.machines[0].loadVisualState.state, "heavy");
  assert.equal(status.machines[0].loadVisualState.pressure, 0);
  assert.notEqual(status.fleet.loadVisualState.state, "constrained");
});
