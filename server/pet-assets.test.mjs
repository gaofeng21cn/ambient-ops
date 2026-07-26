import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  authorizedBearer,
  LEGACY_PET_HASH,
  LEGACY_PET_URL,
  missingPetAssets,
  PetAssetStore,
  petAssetUrl,
  validatePetUpload,
} from "./pet-assets.mjs";

const fixturePath = new URL("../public/pets/ledger-owl/spritesheet.webp", import.meta.url);
const v2Fixture = Buffer.from(
  "UklGRrQAAABXRUJQVlA4TKgAAAAv/8U7EgcQEREQkCT93x8Y0f+M//znP//5z3/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Of/aQA=",
  "base64",
);

test("stores a validated pet asset atomically and deduplicates by content hash", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const body = await readFile(fixturePath);
    const hash = sha256(body);
    const assets = new PetAssetStore(dataDir);
    await assets.load();

    const first = await assets.put(hash, body);
    const second = await assets.put(hash, body);

    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.deepEqual(await assets.read(hash), body);
    assert.equal((await readFile(join(dataDir, "pets", `${hash}.webp`))).equals(body), true);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("removes invalid persisted candidates so a valid upload can recover the hash", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const body = await readFile(fixturePath);
    const hash = sha256(body);
    const mismatchHash = "a".repeat(64);
    const petsDir = join(dataDir, "pets");
    const corruptPath = join(petsDir, `${hash}.webp`);
    const mismatchPath = join(petsDir, `${mismatchHash}.webp`);
    const unrelatedPath = join(petsDir, "operator-note.txt");
    await mkdir(petsDir);
    await writeFile(corruptPath, "not webp");
    await writeFile(mismatchPath, body);
    await writeFile(unrelatedPath, "keep");

    const reloaded = new PetAssetStore(dataDir);
    await reloaded.load();

    assert.equal(reloaded.has(hash), false);
    assert.equal(reloaded.has(mismatchHash), false);
    await assert.rejects(access(corruptPath), { code: "ENOENT" });
    await assert.rejects(access(mismatchPath), { code: "ENOENT" });
    assert.equal(await readFile(unrelatedPath, "utf8"), "keep");

    const recovered = await reloaded.put(hash, body);
    assert.equal(recovered.created, true);
    assert.equal(reloaded.has(hash), true);
    assert.deepEqual(await reloaded.read(hash), body);
    assert.equal((await stat(corruptPath)).mode & 0o777, 0o600);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("accepts a real 8x11 WebP fixture only for a v2 pet manifest", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const hash = sha256(v2Fixture);
    const assets = new PetAssetStore(dataDir);
    await assets.load();

    const stored = await assets.put(hash, v2Fixture, { spriteVersionNumber: 2 });

    assert.equal(stored.created, true);
    assert.deepEqual(
      { width: stored.width, height: stored.height },
      { width: 1536, height: 2288 },
    );
    await assert.rejects(
      assets.put(hash, v2Fixture, { spriteVersionNumber: 1 }),
      (error) => error.statusCode === 422 && /version 1 requires 1536x1872/.test(error.message),
    );
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("rejects hash mismatches, malformed WebP, and oversized assets", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const body = await readFile(fixturePath);
    const assets = new PetAssetStore(dataDir, { maxBytes: body.length });
    await assets.load();

    await assert.rejects(
      assets.put("a".repeat(64), body),
      (error) => error.statusCode === 422 && /SHA-256/.test(error.message),
    );
    await assert.rejects(
      assets.put(sha256(Buffer.from("not webp")), Buffer.from("not webp")),
      (error) => error.statusCode === 422 && /WebP/.test(error.message),
    );
    const wrongDimensions = Buffer.from(body);
    wrongDimensions.writeUInt32LE(0, 21);
    await assert.rejects(
      assets.put(sha256(wrongDimensions), wrongDimensions),
      (error) => error.statusCode === 422 && /1536x1872.*1536x2288/.test(error.message),
    );
    const oversized = Buffer.alloc(body.length + 1);
    await assert.rejects(
      assets.put(sha256(oversized), oversized),
      (error) => error.statusCode === 413,
    );
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("requires bearer authentication and the current machine pet manifest", () => {
  const hash = "a".repeat(64);
  const machine = { machineId: "mac", pet: { id: "lab-owl", assetHash: hash } };

  assert.equal(authorizedBearer("Bearer secret", "secret"), true);
  assert.equal(authorizedBearer("Bearer wrong", "secret"), false);
  assert.equal(authorizedBearer("", "secret"), false);
  assert.doesNotThrow(() => validatePetUpload({
    machine,
    machineId: "mac",
    hash,
    contentType: "image/webp",
    contentEncoding: "",
  }));
  assert.throws(
    () => validatePetUpload({ machine, machineId: "other", hash, contentType: "image/webp" }),
    (error) => error.statusCode === 409,
  );
  assert.throws(
    () => validatePetUpload({ machine, machineId: "mac", hash, contentType: "image/png" }),
    (error) => error.statusCode === 415,
  );
  assert.throws(
    () => validatePetUpload({
      machine,
      machineId: "mac",
      hash,
      contentType: "image/webp",
      contentEncoding: "gzip",
    }),
    (error) => error.statusCode === 415,
  );
});

test("reports only genuinely missing assets and preserves the legacy Ledger Owl", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-pets-"));
  try {
    const assets = new PetAssetStore(dataDir);
    await assets.load();
    const customHash = "b".repeat(64);

    assert.equal(petAssetUrl({ id: "ledger-owl", assetHash: null }, assets), LEGACY_PET_URL);
    assert.equal(
      petAssetUrl({ id: "ledger-owl", assetHash: LEGACY_PET_HASH }, assets),
      LEGACY_PET_URL,
    );
    assert.deepEqual(
      missingPetAssets({ pet: { id: "lab-owl", assetHash: customHash } }, assets),
      [customHash],
    );
    assert.deepEqual(
      missingPetAssets({ pet: { id: "ledger-owl", assetHash: LEGACY_PET_HASH } }, assets),
      [],
    );
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

function sha256(body) {
  return createHash("sha256").update(body).digest("hex");
}
