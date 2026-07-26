import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { StatusStore } from "./store.mjs";

test("prunes inactive machines from memory and persisted state", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-store-"));
  try {
    const store = new StatusStore(dataDir, { networkPersistIntervalMs: 1 });
    await store.load();
    await store.setMachine(machine("old", "2026-07-25T00:00:00.000Z"));
    await store.setMachine(machine("live", "2026-07-25T00:10:00.000Z"));

    const removed = await store.pruneMachines(new Date("2026-07-25T00:05:00.000Z"));

    assert.deepEqual(removed, ["old"]);
    assert.deepEqual([...store.machines.keys()], ["live"]);
    const saved = JSON.parse(await readFile(store.path, "utf8"));
    assert.deepEqual(saved.machines.map((entry) => entry.machineId), ["live"]);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("loads legacy machine state whose bundled pet has no asset hash", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "ambient-ops-store-"));
  try {
    await writeFile(join(dataDir, "state.json"), JSON.stringify({
      machines: [{
        ...machine("old-mac", "2026-07-25T00:00:00.000Z"),
        pet: {
          id: "ledger-owl",
          displayName: "Ledger Owl",
          spriteVersionNumber: 1,
          state: "idle",
          stateSince: "2026-07-25T00:00:00.000Z",
        },
      }],
    }));
    const store = new StatusStore(dataDir);

    await store.load();

    assert.equal(store.machines.get("old-mac").pet.id, "ledger-owl");
    assert.equal(store.machines.get("old-mac").pet.assetHash, undefined);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});

function machine(machineId, receivedAt) {
  return {
    machineId,
    machineName: machineId,
    generatedAt: receivedAt,
    receivedAt,
    reportedStatus: "live",
    oneMinute: {},
    fiveMinutes: {},
    activeSessions: 0,
  };
}
