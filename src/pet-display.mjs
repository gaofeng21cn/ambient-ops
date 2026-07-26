const LEGACY_PET_ID = "ledger-owl";
const LEGACY_PET_HASH = "783854af87d6ee8639843ca7812917e062345b0095d43f9be5ea2374a41ada6c";
const LEGACY_PET_URL = "/pets/ledger-owl/spritesheet.webp";
const CONTENT_ADDRESSED_URL = /^\/api\/v1\/pets\/[a-f0-9]{64}\.webp$/;

export const PET_ANIMATIONS = Object.freeze({
  idle: animation("idle", 0, [280, 110, 110, 140, 140, 320]),
  failed: animation("failed", 5, [140, 140, 140, 140, 140, 140, 140, 240]),
  waiting: animation("waiting", 6, [150, 150, 150, 150, 150, 260]),
  running: animation("running", 7, [120, 120, 120, 120, 120, 220]),
  review: animation("review", 8, [150, 150, 150, 150, 150, 280]),
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
  const expectedUrl = /^[a-f0-9]{64}$/.test(pet.assetHash || "")
    ? `/api/v1/pets/${pet.assetHash}.webp`
    : null;
  if (expectedUrl && pet.assetUrl === expectedUrl && CONTENT_ADDRESSED_URL.test(pet.assetUrl)) {
    return pet.assetUrl;
  }
  if (
    pet.id === LEGACY_PET_ID
    && (!pet.assetHash || pet.assetHash === LEGACY_PET_HASH)
  ) {
    return LEGACY_PET_URL;
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

export function petFrameAtElapsed(animationDefinition, elapsedMs, reduceMotion = false) {
  if (reduceMotion) return 0;
  const elapsed = Number.isFinite(elapsedMs) && elapsedMs > 0 ? elapsedMs : 0;
  const loopElapsed = elapsed % animationDefinition.duration;
  let frameEnd = 0;
  for (let frame = 0; frame < animationDefinition.frameDurations.length; frame += 1) {
    frameEnd += animationDefinition.frameDurations[frame];
    if (loopElapsed < frameEnd) return frame;
  }
  return 0;
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
