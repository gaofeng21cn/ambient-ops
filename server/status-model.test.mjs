import test from "node:test";
import assert from "node:assert/strict";
import { buildDashboard, freshness, networkFreshness, normalizeSnapshot } from "./status-model.mjs";

test("normalizes a machine snapshot without retaining unknown content", () => {
  const snapshot = normalizeSnapshot("mac", {
    machineName: "Mac",
    generatedAt: "2026-07-25T00:00:00.000Z",
    prompt: "must not be retained",
    oneMinute: { tps: 12.5, inputTokens: 100, cachedInputTokens: 80 },
  }, new Date("2026-07-25T00:00:01.000Z"));
  assert.equal(snapshot.oneMinute.tps, 12.5);
  assert.equal(snapshot.prompt, undefined);
});

test("freshness moves from live through stale to error", () => {
  const snapshot = normalizeSnapshot("mac", { generatedAt: "2026-07-25T00:00:00.000Z" });
  assert.equal(freshness(snapshot, new Date("2026-07-25T00:00:20.000Z"), 30, 300).status, "live");
  assert.equal(freshness(snapshot, new Date("2026-07-25T00:01:00.000Z"), 30, 300).status, "stale");
  assert.equal(freshness(snapshot, new Date("2026-07-25T00:06:00.000Z"), 30, 300).status, "error");
});

test("dashboard aggregates machine throughput", () => {
  const now = new Date("2026-07-25T00:00:10.000Z");
  const machines = new Map([
    ["a", normalizeSnapshot("a", { generatedAt: now, oneMinute: { tps: 10 }, fiveMinutes: { tps: 8 }, activeSessions: 2 }, now)],
    ["b", normalizeSnapshot("b", { generatedAt: now, oneMinute: { tps: 20 }, fiveMinutes: { tps: 18 }, activeSessions: 3 }, now)],
  ]);
  const dashboard = buildDashboard({ machines, network: { status: "live" }, history: [], demo: false }, { now });
  assert.equal(dashboard.codex.oneMinuteTps, 30);
  assert.equal(dashboard.codex.fiveMinuteTps, 26);
  assert.equal(dashboard.codex.activeSessions, 5);
});

test("an expired machine stays visible but does not degrade live aggregate", () => {
  const now = new Date("2026-07-25T00:10:00.000Z");
  const machines = new Map([
    ["live", normalizeSnapshot("live", { generatedAt: now, oneMinute: { tps: 20 } }, now)],
    ["expired", normalizeSnapshot("expired", { generatedAt: "2026-07-25T00:00:00.000Z", oneMinute: { tps: 999 } }, now)],
  ]);
  const dashboard = buildDashboard({ machines, network: { status: "live", updatedAt: now }, history: [], demo: false }, { now, liveAfterSeconds: 30, staleAfterSeconds: 300 });
  assert.equal(dashboard.codex.status, "live");
  assert.equal(dashboard.codex.oneMinuteTps, 20);
  assert.equal(dashboard.machines.length, 2);
});

test("network status ages from live to stale to error", () => {
  const network = { status: "live", updatedAt: "2026-07-25T00:00:00.000Z" };
  assert.equal(networkFreshness(network, new Date("2026-07-25T00:00:10.000Z"), 30, 300).status, "live");
  assert.equal(networkFreshness(network, new Date("2026-07-25T00:01:00.000Z"), 30, 300).status, "stale");
  assert.equal(networkFreshness(network, new Date("2026-07-25T00:06:00.000Z"), 30, 300).status, "error");
});

test("future generated timestamps are clamped to receipt time", () => {
  const receivedAt = new Date("2026-07-25T00:00:00.000Z");
  const snapshot = normalizeSnapshot("machine", { generatedAt: "2030-01-01T00:00:00.000Z" }, receivedAt);
  assert.equal(snapshot.generatedAt, receivedAt.toISOString());
});
