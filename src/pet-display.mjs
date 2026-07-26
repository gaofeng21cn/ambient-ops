const LEGACY_PET_ID = "ledger-owl";
const LEGACY_PET_HASH = "783854af87d6ee8639843ca7812917e062345b0095d43f9be5ea2374a41ada6c";
const LEGACY_PET_URL = "/pets/ledger-owl/spritesheet.webp";
const CONTENT_ADDRESSED_URL = /^\/api\/v1\/pets\/[a-f0-9]{64}\.webp$/;

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
