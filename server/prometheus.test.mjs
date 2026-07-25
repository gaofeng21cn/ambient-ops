import test from "node:test";
import assert from "node:assert/strict";
import { renderPrometheus } from "./prometheus.mjs";

test("renders aggregate and per-machine Prometheus metrics", () => {
  const body = renderPrometheus({
    network: { downloadMbps: 100, uploadMbps: 20 },
    codex: { oneMinuteTps: 50, fiveMinuteTps: 45, activeSessions: 2 },
    machines: [{ machineId: "mac", machineName: "Mac", platform: "macOS", ageSeconds: 1, status: "live", oneMinute: { tps: 50 }, fiveMinutes: { tps: 45 } }],
  });
  assert.match(body, /ambient_ops_network_download_megabits_per_second 100/);
  assert.match(body, /machine_id="mac"/);
});
