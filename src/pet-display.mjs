import { shouldReduceKioskMotion } from "./kiosk-motion.mjs";

const LEGACY_PET_ID = "ledger-owl";
const LEGACY_PET_HASH = "783854af87d6ee8639843ca7812917e062345b0095d43f9be5ea2374a41ada6c";
const LEGACY_PET_URL = "/pets/ledger-owl/spritesheet.webp";
const CONTENT_ADDRESSED_URL = /^\/api\/v1\/pets\/[a-f0-9]{64}(?:\.webp)?$/;
const CODEX_IDLE_DURATION_SCALE = 6;

export const PET_ANIMATIONS = Object.freeze({
  idle: animation("idle", 0, [280, 110, 110, 140, 140, 320]),
  jumping: animation("jumping", 4, [140, 140, 140, 140, 280]),
  failed: animation("failed", 5, [140, 140, 140, 140, 140, 140, 140, 240]),
  waiting: animation("waiting", 6, [150, 150, 150, 150, 150, 260]),
  running: animation("running", 7, [120, 120, 120, 120, 120, 220]),
  review: animation("review", 8, [150, 150, 150, 150, 150, 280]),
  waving: animation("waving", 3, [140, 140, 140, 280]),
});

export function selectDisplayMachine(machines, selectedMachineId, followMode) {
  const candidates = Array.isArray(machines) ? machines : [];
  const autoMachine = [...candidates].sort((a, b) => {
    if (a.status === "live" && b.status !== "live") return -1;
    if (a.status !== "live" && b.status === "live") return 1;
    return new Date(b.generatedAt).valueOf() - new Date(a.generatedAt).valueOf();
  })[0];
  if (followMode === "auto") return autoMachine;
  return candidates.find((machine) => machine.machineId === selectedMachineId) || autoMachine;
}

export function resolvePetSpriteUrl(pet) {
  if (!pet) return null;
  if (
    pet.id === LEGACY_PET_ID
    && (!pet.assetHash || pet.assetHash === LEGACY_PET_HASH)
  ) {
    return LEGACY_PET_URL;
  }
  const assetUrl = String(pet.assetUrl || "");
  const relativeAsset = /^\/(?!\/)/.test(assetUrl);
  const trustedAbsoluteAsset = /^https?:\/\//i.test(assetUrl)
    && pet.assetUrlTrustedOrigin === true;
  if (!relativeAsset && !trustedAbsoluteAsset) return null;
  let candidate;
  try {
    candidate = new URL(assetUrl, "http://ambient-ops.invalid");
  } catch {
    candidate = null;
  }
  const contentAddressed = candidate
    && CONTENT_ADDRESSED_URL.test(candidate.pathname)
    && candidate.pathname.replace(/\.webp$/, "").endsWith(`/${pet.assetHash}`);
  if (/^[a-f0-9]{64}$/.test(pet.assetHash || "") && contentAddressed) {
    return assetUrl;
  }
  return null;
}

export function petSpriteKey(machine, pet) {
  return `${machine.machineId}:${pet.assetHash || "legacy"}:${pet.spriteVersionNumber || 1}`;
}

export function petSpriteGrid(pet) {
  const rows = pet?.spriteVersionNumber === 2 ? 11 : 9;
  return {
    backgroundSize: `800% ${rows * 100}%`,
    columnPosition: (column) => `${column * 100 / 7}%`,
    rowPosition: (row) => `${row * 100 / (rows - 1)}%`,
    sheetHeight: `${rows * 100}%`,
    rowOffset: (row) => `${row * -100}%`,
  };
}

export function petAnimationForState(state) {
  return PET_ANIMATIONS[state] || PET_ANIMATIONS.idle;
}

export function petPlaybackForState(state, reduceMotion = false) {
  const action = petAnimationForState(state);
  const actionFrames = framesForAnimation(action);
  if (reduceMotion) {
    return Object.freeze({
      frames: Object.freeze([actionFrames[0]]),
      durationMs: actionFrames[0].frameDurationMs,
      loopStartIndex: null,
    });
  }

  const frames = action.name === "idle"
    ? framesForAnimation(PET_ANIMATIONS.idle, CODEX_IDLE_DURATION_SCALE)
    : actionFrames;
  return Object.freeze({
    frames: Object.freeze(frames),
    durationMs: frames.reduce((total, frame) => total + frame.frameDurationMs, 0),
    loopStartIndex: 0,
  });
}

export function petFramePosition(frame, pet) {
  const grid = petSpriteGrid(pet);
  return `${grid.columnPosition(frame.columnIndex)} ${grid.rowPosition(frame.rowIndex)}`;
}

export function shouldReducePetMotion(userAgent, prefersReducedMotion) {
  return shouldReduceKioskMotion(userAgent, prefersReducedMotion);
}

export function petFrameAtElapsed(playback, elapsedMs) {
  const frames = playback?.frames || [];
  if (frames.length === 0 || playback.loopStartIndex === null) return 0;
  const elapsed = Number.isFinite(elapsedMs) && elapsedMs > 0 ? elapsedMs : 0;
  if (playback.durationMs <= 0) return 0;
  return frameIndexAtElapsed(frames, elapsed % playback.durationMs);
}

function frameIndexAtElapsed(frames, elapsedMs) {
  let frameEnd = 0;
  for (let frame = 0; frame < frames.length; frame += 1) {
    frameEnd += frames[frame].frameDurationMs;
    if (elapsedMs < frameEnd) return frame;
  }
  return 0;
}

function framesForAnimation(animationDefinition, durationScale = 1) {
  return animationDefinition.frameDurations.map((frameDurationMs, columnIndex) => Object.freeze({
    rowIndex: animationDefinition.row,
    columnIndex,
    frameDurationMs: frameDurationMs * durationScale,
  }));
}

function animation(name, row, frameDurations) {
  const durations = Object.freeze(frameDurations);
  return Object.freeze({
    name,
    row,
    frameDurations: durations,
    duration: durations.reduce((total, duration) => total + duration, 0),
  });
}
