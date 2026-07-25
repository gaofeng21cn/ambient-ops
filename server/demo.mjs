import { normalizeSnapshot } from "./status-model.mjs";

const machineSeeds = [
  { id: "primary-laptop", name: "Primary Laptop", platform: "macOS", base: 1285, sessions: 7 },
  { id: "workstation", name: "Workstation", platform: "Windows", base: 1012, sessions: 5 },
  { id: "studio-desktop", name: "Studio Desktop", platform: "macOS", base: 545, sessions: 2, stale: true },
];

export function updateDemo(store, tick = Date.now()) {
  const phase = tick / 5800;
  const downloadMbps = 760 + Math.sin(phase) * 92 + Math.sin(phase * 2.7) * 48;
  const uploadMbps = 118 + Math.cos(phase * 1.4) * 18 + Math.sin(phase * 3.2) * 8;
  store.network = {
    status: "live",
    source: "demo",
    downloadMbps: Math.max(0, downloadMbps),
    uploadMbps: Math.max(0, uploadMbps),
    clients: 63,
    latencyMs: 8,
    updatedAt: new Date().toISOString(),
    error: null,
  };
  store.networkHistory.push({
    at: store.network.updatedAt,
    downloadMbps: store.network.downloadMbps,
    uploadMbps: store.network.uploadMbps,
  });
  store.networkHistory = store.networkHistory.slice(-120);

  machineSeeds.forEach((seed, index) => {
    const pulse = Math.sin(phase * (1.2 + index * 0.16) + index) * seed.base * 0.08;
    const generatedAt = new Date(Date.now() - (seed.stale ? 122_000 : index * 1_800));
    store.machines.set(seed.id, normalizeSnapshot(seed.id, {
      machineName: seed.name,
      platform: seed.platform,
      generatedAt,
      oneMinute: {
        tps: Math.max(0, seed.base + pulse),
        inputTokens: 100_000 + index * 34_000,
        outputTokens: 19_000 + index * 6_000,
        cachedInputTokens: (86 - index * 4) * 1000,
        reasoningOutputTokens: 4200 + index * 900,
        requests: 14 - index * 2,
      },
      fiveMinutes: { tps: seed.base * 0.93 + pulse * 0.4 },
      activeSessions: seed.sessions,
    }, new Date()));
  });
}
