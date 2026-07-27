import { createConnection } from "node:net";
import { performance } from "node:perf_hooks";

export function measureTcpLatency(
  { host, port = 443, timeoutMs = 1500 },
  connect = createConnection,
  now = () => performance.now(),
) {
  if (!host) return Promise.reject(new Error("Latency probe host is required"));
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    return Promise.reject(new Error("Latency probe port must be between 1 and 65535"));
  }

  return new Promise((resolve, reject) => {
    const startedAt = now();
    let settled = false;
    let socket;

    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      socket?.destroy();
      if (error) reject(error);
      else resolve(value);
    };

    try {
      socket = connect({ host, port });
    } catch (error) {
      finish(error);
      return;
    }

    socket.setTimeout(Math.max(100, timeoutMs), () => {
      finish(new Error(`Latency probe timed out after ${timeoutMs} ms`));
    });
    socket.once("connect", () => {
      finish(null, Math.round((now() - startedAt) * 100) / 100);
    });
    socket.once("error", (error) => finish(error));
  });
}
