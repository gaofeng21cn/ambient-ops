import test from "node:test";
import assert from "node:assert/strict";
import {
  PET_ANIMATIONS,
  petAnimationForState,
  petFrameAtElapsed,
  petSpriteKey,
  petSpriteGrid,
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

test("maps standard animation rows correctly in v1 and v2 atlases", () => {
  const v1 = petSpriteGrid({ spriteVersionNumber: 1 });
  const v2 = petSpriteGrid({ spriteVersionNumber: 2 });

  assert.equal(v1.backgroundSize, "800% 900%");
  assert.equal(v1.columnPosition(0), "0%");
  assert.equal(v1.columnPosition(7), "100%");
  assert.equal(v1.rowPosition(8), "100%");
  assert.equal(v1.sheetHeight, "900%");
  assert.equal(v1.rowOffset(7), "-700%");
  assert.equal(v2.backgroundSize, "800% 1100%");
  assert.equal(v2.rowPosition(8), "80%");
  assert.equal(v2.sheetHeight, "1100%");
});

test("uses the Codex frame timing contract for every projected pet state", () => {
  assert.deepEqual(PET_ANIMATIONS.idle, {
    name: "idle",
    row: 0,
    frameDurations: [280, 110, 110, 140, 140, 320],
    duration: 1100,
  });
  assert.deepEqual(PET_ANIMATIONS.failed, {
    name: "failed",
    row: 5,
    frameDurations: [140, 140, 140, 140, 140, 140, 140, 240],
    duration: 1220,
  });
  assert.deepEqual(PET_ANIMATIONS.waiting, {
    name: "waiting",
    row: 6,
    frameDurations: [150, 150, 150, 150, 150, 260],
    duration: 1010,
  });
  assert.deepEqual(PET_ANIMATIONS.running, {
    name: "running",
    row: 7,
    frameDurations: [120, 120, 120, 120, 120, 220],
    duration: 820,
  });
  assert.deepEqual(PET_ANIMATIONS.review, {
    name: "review",
    row: 8,
    frameDurations: [150, 150, 150, 150, 150, 280],
    duration: 1030,
  });
  assert.equal(petAnimationForState("unknown"), PET_ANIMATIONS.idle);
});

test("locates frames from absolute elapsed time and catches up after throttling", () => {
  const running = PET_ANIMATIONS.running;

  assert.equal(petFrameAtElapsed(running, -1), 0);
  assert.equal(petFrameAtElapsed(running, 119), 0);
  assert.equal(petFrameAtElapsed(running, 120), 1);
  assert.equal(petFrameAtElapsed(running, 599), 4);
  assert.equal(petFrameAtElapsed(running, 600), 5);
  assert.equal(petFrameAtElapsed(running, 819), 5);
  assert.equal(petFrameAtElapsed(running, 820), 0);
  assert.equal(petFrameAtElapsed(running, (820 * 12) + 360), 3);
  assert.equal(petFrameAtElapsed(running, 600, true), 0);
});

function machine(machineId, machineName, status, generatedAt) {
  return { machineId, machineName, status, generatedAt };
}
