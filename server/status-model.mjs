const finite = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
const PET_STATES = new Set(["idle", "running", "waiting", "review", "failed"]);

export function normalizeSnapshot(machineId, payload, receivedAt = new Date()) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new TypeError("Snapshot payload must be an object");
  }
  const candidateGeneratedAt = new Date(payload.generatedAt || receivedAt);
  const futureLimit = receivedAt.valueOf() + 5 * 60 * 1000;
  const safeGeneratedAt = Number.isNaN(candidateGeneratedAt.valueOf()) || candidateGeneratedAt.valueOf() > futureLimit
    ? receivedAt
    : candidateGeneratedAt;
  const oneMinute = payload.oneMinute || {};
  const fiveMinutes = payload.fiveMinutes || {};

  return {
    machineId,
    machineName: String(payload.machineName || machineId).slice(0, 80),
    platform: String(payload.platform || "unknown").slice(0, 32),
    generatedAt: safeGeneratedAt.toISOString(),
    receivedAt: receivedAt.toISOString(),
    reportedStatus: ["live", "error"].includes(payload.status) ? payload.status : "live",
    error: payload.error ? String(payload.error).slice(0, 240) : null,
    oneMinute: normalizeWindow(oneMinute),
    fiveMinutes: normalizeWindow(fiveMinutes),
    activeSessions: Math.max(0, finite(payload.activeSessions)),
    pet: normalizePet(payload.pet, safeGeneratedAt),
  };
}

function normalizeWindow(window) {
  return {
    tps: Math.max(0, finite(window.tps)),
    inputTokens: Math.max(0, finite(window.inputTokens)),
    outputTokens: Math.max(0, finite(window.outputTokens)),
    cachedInputTokens: Math.max(0, finite(window.cachedInputTokens)),
    reasoningOutputTokens: Math.max(0, finite(window.reasoningOutputTokens)),
    requests: Math.max(0, finite(window.requests)),
  };
}

function normalizePet(pet, generatedAt) {
  if (!pet || typeof pet !== "object" || Array.isArray(pet)) return null;
  const id = String(pet.id || "").trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{0,79}$/.test(id)) return null;
  const state = PET_STATES.has(pet.state) ? pet.state : "idle";
  const candidateStateSince = new Date(pet.stateSince || generatedAt);
  const stateSince = Number.isNaN(candidateStateSince.valueOf())
    ? generatedAt
    : candidateStateSince;
  const assetHash = String(pet.assetHash || "").trim().toLowerCase();
  return {
    id,
    displayName: String(pet.displayName || id).slice(0, 80),
    spriteVersionNumber: Math.max(1, Math.trunc(finite(pet.spriteVersionNumber, 1))),
    assetHash: /^[a-f0-9]{64}$/.test(assetHash) ? assetHash : null,
    state,
    stateSince: stateSince.toISOString(),
  };
}

export function freshness(snapshot, now, liveAfterSeconds, staleAfterSeconds) {
  if (snapshot.reportedStatus === "error") return { status: "error", ageSeconds: age(snapshot, now) };
  const ageSeconds = age(snapshot, now);
  if (ageSeconds <= liveAfterSeconds) return { status: "live", ageSeconds };
  if (ageSeconds <= staleAfterSeconds) return { status: "stale", ageSeconds };
  return { status: "error", ageSeconds };
}

function age(snapshot, now) {
  return Math.max(0, Math.round((now.valueOf() - new Date(snapshot.generatedAt).valueOf()) / 1000));
}

export function buildDashboard({ machines, network, history, demo }, options = {}) {
  const now = options.now || new Date();
  const liveAfterSeconds = options.liveAfterSeconds || 30;
  const staleAfterSeconds = options.staleAfterSeconds || 300;
  const renderedMachines = [...machines.values()].map((snapshot) => {
    const current = freshness(snapshot, now, liveAfterSeconds, staleAfterSeconds);
    const totalInput = snapshot.oneMinute.inputTokens;
    const cachePercent = totalInput > 0
      ? Math.round((snapshot.oneMinute.cachedInputTokens / totalInput) * 100)
      : 0;
    const pet = snapshot.pet
      ? {
          ...snapshot.pet,
          state: current.status === "live"
            ? snapshot.pet.state
            : current.status === "stale" ? "waiting" : "failed",
        }
      : null;
    return { ...snapshot, ...current, cachePercent, pet };
  })
    .filter((machine) => machine.ageSeconds <= staleAfterSeconds)
    .sort((a, b) => b.oneMinute.tps - a.oneMinute.tps);

  const aggregateMachines = renderedMachines.filter((machine) => machine.status === "live");
  let oneMinuteTps = 0;
  let fiveMinuteTps = 0;
  let activeSessions = 0;
  let weightedCache = 0;
  let cacheWeight = 0;
  for (const machine of aggregateMachines) {
    oneMinuteTps += machine.oneMinute.tps;
    fiveMinuteTps += machine.fiveMinutes.tps;
    activeSessions += machine.activeSessions;
    const weight = Math.max(machine.oneMinute.inputTokens, 1);
    weightedCache += machine.cachePercent * weight;
    cacheWeight += weight;
  }

  const liveMachines = renderedMachines.filter((machine) => machine.status === "live").length;
  const staleMachines = renderedMachines.filter((machine) => machine.status === "stale").length;
  const codexStatus = liveMachines > 0 ? "live" : staleMachines > 0 ? "stale" : "error";
  const renderedNetwork = networkFreshness(network, now, liveAfterSeconds, staleAfterSeconds);
  const networkStatus = renderedNetwork.status;

  return {
    generatedAt: now.toISOString(),
    demo,
    overallStatus: networkStatus === "error" || codexStatus === "error" ? "error" : networkStatus === "stale" || codexStatus === "stale" ? "stale" : "live",
    network: { ...renderedNetwork, history },
    codex: {
      status: codexStatus,
      oneMinuteTps,
      fiveMinuteTps,
      cachePercent: cacheWeight ? Math.round(weightedCache / cacheWeight) : 0,
      activeSessions,
      machineCount: renderedMachines.length,
      liveMachineCount: liveMachines,
      staleMachineCount: staleMachines,
    },
    machines: renderedMachines,
  };
}

export function networkFreshness(network, now, liveAfterSeconds, staleAfterSeconds) {
  if (!network.updatedAt) return { ...network, status: network.status || "error", ageSeconds: null };
  const ageSeconds = Math.max(0, Math.round((now.valueOf() - new Date(network.updatedAt).valueOf()) / 1000));
  if (network.status === "error") return { ...network, status: "error", ageSeconds };
  if (network.status === "stale") {
    return { ...network, status: ageSeconds <= staleAfterSeconds ? "stale" : "error", ageSeconds };
  }
  const status = ageSeconds <= liveAfterSeconds ? "live" : ageSeconds <= staleAfterSeconds ? "stale" : "error";
  return { ...network, status, ageSeconds };
}
