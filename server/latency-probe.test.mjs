import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:net";
import { measureTcpLatency } from "./latency-probe.mjs";

test("measures a TCP handshake without raw-socket privileges", async (context) => {
  const server = createServer((socket) => socket.end());
  context.after(() => server.close());
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });

  const address = server.address();
  const latencyMs = await measureTcpLatency({
    host: "127.0.0.1",
    port: address.port,
    timeoutMs: 500,
  });

  assert.equal(Number.isFinite(latencyMs), true);
  assert.ok(latencyMs >= 0);
  assert.ok(latencyMs < 500);
  assert.ok((String(latencyMs).split(".")[1]?.length ?? 0) <= 2);
});

test("rejects an invalid probe target before opening a socket", async () => {
  await assert.rejects(
    measureTcpLatency({ host: "", port: 443, timeoutMs: 500 }),
    /host is required/,
  );
  await assert.rejects(
    measureTcpLatency({ host: "example.test", port: 0, timeoutMs: 500 }),
    /port must be between/,
  );
});
