const LOAD_STATES = Object.freeze([
  { id: "quiet", label: "QUIET", min: 0 },
  { id: "flowing", label: "FLOWING", min: 0.18 },
  { id: "heavy", label: "HEAVY", min: 0.45 },
  { id: "saturated", label: "SATURATED", min: 0.75 },
]);

export function finiteOrNull(value) {
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

export function singleMachineLoad(machine) {
  const tps = Math.max(0, Number(machine?.oneMinute?.tps || 0));
  const sessions = Math.max(0, Number(machine?.activeSessions || 0));
  const cpu = finiteOrNull(machine?.cpuPercent);
  const tpsIntensity = Math.min(1, tps / 2_000);
  const sessionIntensity = Math.min(1, sessions / 8);
  const cpuIntensity = cpu === null ? null : Math.min(1, Math.max(0, cpu / 100));
  const score = cpuIntensity === null
    ? tpsIntensity * 0.68 + sessionIntensity * 0.32
    : tpsIntensity * 0.52 + sessionIntensity * 0.22 + cpuIntensity * 0.26;
  const normalizedScore = clamp(score, 0, 1);
  const hasCodexWork = tps > 0 || sessions > 0;

  return {
    tps,
    sessions,
    cpu,
    score: normalizedScore,
    travelSeconds: clamp(2.8 - tps / 800, 0.65, 2.8),
    density: clamp(0.12 + tpsIntensity * 0.62 + sessionIntensity * 0.26, 0.12, 1),
    laneCount: hasCodexWork
      ? normalizedScore >= 0.75 ? 5 : Math.max(1, Math.min(4, Math.ceil(normalizedScore * 5)))
      : 0,
  };
}

const CHANNEL_SPEEDS = Object.freeze([0.94, 1.14, 0.86, 1.07, 0.98]);
const CHANNEL_DENSITIES = Object.freeze([0.82, 1.08, 0.9, 1.16, 0.98]);

export function loadFlowChannels(load) {
  const laneCount = Math.max(0, Math.min(5, Math.round(Number(load?.laneCount) || 0)));
  const baseDensity = clamp(Number(load?.density) || 0, 0, 1);
  const baseTravelMs = Math.max(300, Number(load?.travelSeconds || 2.8) * 1_000);

  return CHANNEL_SPEEDS.map((speed, index) => {
    const active = index < laneCount;
    const density = active ? clamp(baseDensity * CHANNEL_DENSITIES[index], 0.1, 1) : 0;
    return {
      active,
      index,
      density,
      travelMs: Math.round(baseTravelMs * speed),
      packetCount: active ? Math.max(4, Math.min(18, Math.round(4 + density * 14))) : 0,
    };
  });
}

export function loadParticlePhase(elapsedMs, travelMs, phaseOffset = 0) {
  const duration = Math.max(1, Number(travelMs) || 1);
  const elapsed = Math.max(0, Number(elapsedMs) || 0);
  const offset = Number(phaseOffset) || 0;
  return (elapsed / duration + offset) % 1;
}

export function loadState(score) {
  const normalized = clamp(Number(score) || 0, 0, 1);
  let definition = LOAD_STATES[0];
  for (const candidate of LOAD_STATES) {
    if (normalized >= candidate.min) definition = candidate;
  }
  return { score: normalized, definition };
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}
