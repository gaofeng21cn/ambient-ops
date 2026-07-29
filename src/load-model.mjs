const LOAD_STATES = Object.freeze([
  { id: "quiet", label: "QUIET", min: 0 },
  { id: "active", label: "ACTIVE", min: 0.18 },
  { id: "heavy", label: "HEAVY", min: 0.45 },
  // Constraint is a measured host condition, not an activity-score bucket.
  { id: "constrained", label: "CONSTRAINED", min: Number.POSITIVE_INFINITY },
]);

export function finiteOrNull(value) {
  if (value === null || value === undefined || value === "") return null;
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

export function singleMachineLoad(machine) {
  const tps = Math.max(0, Number(machine?.oneMinute?.tps || 0));
  const sessions = Math.max(0, Number(machine?.activeSessions || 0));
  const cpu = finiteOrNull(machine?.cpuPercent);
  // Codex hosts can report tens of thousands of tokens/sec. A broad reference
  // range keeps the display expressive instead of pinning every real host at 1.
  const tpsIntensity = clamp(Math.sqrt(tps / 60_000), 0, 1);
  const sessionIntensity = Math.min(1, sessions / 12);
  const cpuIntensity = cpu === null ? null : Math.min(1, Math.max(0, cpu / 100));
  const score = cpuIntensity === null
    ? tpsIntensity * 0.72 + sessionIntensity * 0.28
    : tpsIntensity * 0.56 + sessionIntensity * 0.22 + cpuIntensity * 0.22;
  const normalizedScore = clamp(score, 0, 1);
  const hasCodexWork = tps > 0 || sessions > 0;
  const cpuPressure = cpu === null ? null : clamp((cpu - 68) / 32, 0, 1);
  // High activity is not the same as saturation. Only a measured host signal
  // can promote the visual to CONSTRAINED.
  const constrained = Boolean(
    hasCodexWork && cpu !== null && cpu >= 88 && normalizedScore >= 0.35,
  );
  const streamCount = hasCodexWork
    ? normalizedScore >= 0.45 ? 3 : normalizedScore >= 0.18 ? 2 : 1
    : 0;

  return {
    tps,
    sessions,
    cpu,
    score: normalizedScore,
    cpuPressure,
    constrained,
    travelSeconds: clamp(3.1 - tpsIntensity * 1.8 - sessionIntensity * 0.35, 0.8, 3.1),
    cycleSeconds: clamp(3.1 - tpsIntensity * 1.8 - sessionIntensity * 0.35, 0.8, 3.1),
    density: hasCodexWork
      ? clamp(0.12 + tpsIntensity * 0.58 + sessionIntensity * 0.22, 0.12, 1)
      : 0,
    streamCount,
    beamCount: streamCount,
    backpressure: constrained ? clamp(0.35 + (cpuPressure || 0) * 0.65, 0.35, 1) : 0,
  };
}

export function loadSceneProfile(load) {
  const score = clamp(Number(load?.score) || 0, 0, 1);
  const sessions = Math.max(0, Number(load?.sessions) || 0);
  const tps = Math.max(0, Number(load?.tps) || 0);
  const pressure = load?.cpu === null
    ? 0
    : clamp(Number(load?.cpuPressure) || 0, 0, 1);
  const hasWork = tps > 0 || sessions > 0;
  const parallel = hasWork ? clamp(Math.sqrt(sessions / 18), 0, 1) : 0;
  const tempo = hasWork
    ? clamp(0.45 + score * 1.35 + Math.sqrt(tps / 90_000) * 0.7, 0.45, 2.5)
    : 0.2;
  const clusterCount = hasWork ? Math.max(1, Math.min(4, Math.round(1 + parallel * 3))) : 0;
  const activity = hasWork ? clamp(score * 0.72 + parallel * 0.28, 0, 1) : 0;
  const travelMs = hasWork
    ? clamp((Number(load?.travelSeconds) || 3.1) * 1_000, 800, 3_100)
    : 4_800;
  const queueDepth = load?.constrained
    ? clamp(0.24 + pressure * 0.76, 0.24, 1)
    : clamp(Math.max(0, score - 0.68) * 0.7, 0, 0.25);

  return {
    activity,
    parallel,
    tempo,
    travelMs,
    clusterCount,
    taskDensity: hasWork ? clamp(0.16 + activity * 0.68 + parallel * 0.16, 0.16, 1) : 0,
    pressure,
    queueDepth,
    heat: clamp(pressure * 0.9 + activity * 0.12, 0, 1),
  };
}

const STREAM_SPEEDS = Object.freeze([0.92, 1.08, 1.24]);
const STREAM_DENSITIES = Object.freeze([0.92, 1.08, 0.98]);
const STREAM_CENTERS = Object.freeze([0.28, 0.5, 0.72]);
const STREAM_SPREADS = Object.freeze([0.07, 0.09, 0.07]);

export function loadFlowChannels(load) {
  const streamCount = Math.max(
    0,
    Math.min(3, Math.round(Number(load?.streamCount ?? load?.beamCount ?? load?.laneCount) || 0)),
  );
  const baseDensity = clamp(Number(load?.density) || 0, 0, 1);
  const baseTravelMs = Math.max(300, Number(load?.cycleSeconds || load?.travelSeconds || 3.1) * 1_000);

  return STREAM_SPEEDS.map((speed, index) => {
    const active = index < streamCount;
    const density = active ? clamp(baseDensity * STREAM_DENSITIES[index], 0.08, 1) : 0;
    return {
      active,
      index,
      density,
      travelMs: Math.round(baseTravelMs * speed),
      packetCount: active ? Math.max(5, Math.min(26, Math.round(5 + density * 21))) : 0,
      center: STREAM_CENTERS[index],
      spread: STREAM_SPREADS[index],
      phaseOffset: index * 0.23,
    };
  });
}

export function loadParticlePhase(elapsedMs, travelMs, phaseOffset = 0) {
  const duration = Math.max(1, Number(travelMs) || 1);
  const elapsed = Math.max(0, Number(elapsedMs) || 0);
  const offset = Number(phaseOffset) || 0;
  return (elapsed / duration + offset) % 1;
}

export function loadState(score, context = {}) {
  const normalized = clamp(Number(score) || 0, 0, 1);
  let definition = LOAD_STATES[0];
  for (const candidate of LOAD_STATES) {
    if (normalized >= candidate.min) definition = candidate;
  }
  if (context.constrained === true) {
    definition = LOAD_STATES.at(-1);
  }
  return { score: normalized, definition };
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}
