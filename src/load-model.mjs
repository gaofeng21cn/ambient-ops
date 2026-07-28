const LOAD_STATES = Object.freeze([
  { id: "quiet", label: "QUIET", min: 0 },
  { id: "active", label: "ACTIVE", min: 0.18 },
  { id: "heavy", label: "HEAVY", min: 0.45 },
  { id: "constrained", label: "CONSTRAINED", min: 0.75 },
]);

export function finiteOrNull(value) {
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

  return {
    tps,
    sessions,
    cpu,
    score: normalizedScore,
    travelSeconds: clamp(2.8 - tpsIntensity * 1.65 - sessionIntensity * 0.35, 0.72, 2.8),
    density: hasCodexWork
      ? clamp(0.12 + tpsIntensity * 0.58 + sessionIntensity * 0.22, 0.12, 1)
      : 0,
    beamCount: hasCodexWork
      ? normalizedScore >= 0.75 ? 4 : normalizedScore >= 0.45 ? 3 : normalizedScore >= 0.18 ? 2 : 1
      : 0,
  };
}

const BEAM_SPEEDS = Object.freeze([0.91, 1.18, 0.99, 1.27]);
const BEAM_DENSITIES = Object.freeze([0.86, 1.12, 0.96, 1.18]);
const BEAM_CENTERS = Object.freeze([0.27, 0.43, 0.59, 0.74]);
const BEAM_SPREADS = Object.freeze([0.055, 0.075, 0.068, 0.052]);

export function loadFlowChannels(load) {
  const beamCount = Math.max(
    0,
    Math.min(4, Math.round(Number(load?.beamCount ?? load?.laneCount) || 0)),
  );
  const baseDensity = clamp(Number(load?.density) || 0, 0, 1);
  const baseTravelMs = Math.max(300, Number(load?.travelSeconds || 2.8) * 1_000);

  return BEAM_SPEEDS.map((speed, index) => {
    const active = index < beamCount;
    const density = active ? clamp(baseDensity * BEAM_DENSITIES[index], 0.08, 1) : 0;
    return {
      active,
      index,
      density,
      travelMs: Math.round(baseTravelMs * speed),
      packetCount: active ? Math.max(5, Math.min(24, Math.round(5 + density * 19))) : 0,
      center: BEAM_CENTERS[index],
      spread: BEAM_SPREADS[index],
      phaseOffset: index * 0.19,
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
