import test from "node:test";
import assert from "node:assert/strict";
import {
  petSpriteKey,
  resolvePetSpriteUrl,
  selectDisplayMachine,
} from "../src/pet-display.mjs";

test("fixed pet display keeps the explicitly selected machine", () => {
  const machines = [
    machine("primary", "Primary", "live", "2026-07-25T00:00:10.000Z"),
    machine("wife", "Wife", "live", "2026-07-25T00:00:00.000Z"),
  ];

  assert.equal(selectDisplayMachine(machines, "wife", "fixed").machineId, "wife");
});

test("automatic pet display follows the most recent live machine", () => {
  const machines = [
    machine("stale", "Stale", "stale", "2026-07-25T00:00:30.000Z"),
    machine("older-live", "Older", "live", "2026-07-25T00:00:10.000Z"),
    machine("newer-live", "Newer", "live", "2026-07-25T00:00:20.000Z"),
  ];

  assert.equal(selectDisplayMachine(machines, "stale", "auto").machineId, "newer-live");
});

test("uses only trusted content-addressed sprite URLs and invalidates on pet updates", () => {
  const firstHash = "a".repeat(64);
  const secondHash = "b".repeat(64);
  const first = {
    id: "lab-owl",
    assetHash: firstHash,
    assetUrl: `/api/v1/pets/${firstHash}.webp`,
    spriteVersionNumber: 2,
  };
  const second = {
    ...first,
    assetHash: secondHash,
    assetUrl: `/api/v1/pets/${secondHash}.webp`,
    spriteVersionNumber: 3,
  };
  const host = { machineId: "wife" };

  assert.equal(resolvePetSpriteUrl(first), first.assetUrl);
  assert.notEqual(petSpriteKey(host, first), petSpriteKey(host, second));
  assert.equal(resolvePetSpriteUrl({ ...first, assetUrl: "https://tracker.invalid/pet.webp" }), null);
  assert.equal(
    resolvePetSpriteUrl({ ...first, assetUrl: `/api/v1/pets/${secondHash}.webp` }),
    null,
  );
});

test("keeps the bundled Ledger Owl URL for old machine state", () => {
  assert.equal(
    resolvePetSpriteUrl({ id: "ledger-owl", assetHash: null, spriteVersionNumber: 1 }),
    "/pets/ledger-owl/spritesheet.webp",
  );
});

function machine(machineId, machineName, status, generatedAt) {
  return { machineId, machineName, status, generatedAt };
}
