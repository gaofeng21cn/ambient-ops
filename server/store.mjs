import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";

export class StatusStore {
  constructor(dataDir, { networkPersistIntervalMs = 5000 } = {}) {
    this.dataDir = dataDir;
    this.path = join(dataDir, "state.json");
    this.machines = new Map();
    this.network = { status: "error", source: "unconfigured", error: "UniFi is not configured" };
    this.networkHistory = [];
    this.persistChain = Promise.resolve();
    this.persistSequence = 0;
    this.networkPersistIntervalMs = networkPersistIntervalMs;
    this.networkPersistTimer = null;
    this.networkDirty = false;
  }

  async load() {
    await mkdir(this.dataDir, { recursive: true });
    try {
      const saved = JSON.parse(await readFile(this.path, "utf8"));
      this.machines = new Map((saved.machines || []).map((machine) => [machine.machineId, machine]));
      this.network = saved.network || this.network;
      this.networkHistory = (saved.networkHistory || []).slice(-300);
    } catch (error) {
      if (error.code !== "ENOENT") console.warn("Unable to load persisted state:", error.message);
    }
  }

  setMachine(snapshot) {
    this.machines.set(snapshot.machineId, snapshot);
    return this.persist();
  }

  async removeMachine(machineId) {
    if (!this.machines.delete(machineId)) return false;
    await this.persist();
    return true;
  }

  async pruneMachines(before) {
    const cutoff = before.valueOf();
    const removed = [];
    for (const [machineId, snapshot] of this.machines) {
      const receivedAt = new Date(snapshot.receivedAt || snapshot.generatedAt).valueOf();
      if (!Number.isFinite(receivedAt) || receivedAt < cutoff) {
        this.machines.delete(machineId);
        removed.push(machineId);
      }
    }
    if (removed.length) await this.persist();
    return removed;
  }

  setNetwork(network, { recordHistory = true } = {}) {
    this.network = network;
    if (recordHistory && Number.isFinite(network.downloadMbps) && Number.isFinite(network.uploadMbps)) {
      this.networkHistory.push({
        at: network.updatedAt,
        downloadMbps: network.downloadMbps,
        uploadMbps: network.uploadMbps,
      });
      this.networkHistory = this.networkHistory.slice(-300);
    }
    this.networkDirty = true;
    this.scheduleNetworkPersist();
    return this.persistChain;
  }

  async persist() {
    if (this.networkPersistTimer) {
      clearTimeout(this.networkPersistTimer);
      this.networkPersistTimer = null;
    }
    this.networkDirty = false;
    const body = JSON.stringify({
      machines: [...this.machines.values()],
      network: this.network,
      networkHistory: this.networkHistory,
    }, null, 2);
    const sequence = ++this.persistSequence;
    this.persistChain = this.persistChain.catch(() => undefined).then(async () => {
      const temporary = `${this.path}.${process.pid}.${sequence}.tmp`;
      await writeFile(temporary, body, { mode: 0o600 });
      await rename(temporary, this.path);
    });
    return this.persistChain;
  }

  flush() {
    return this.networkDirty ? this.persist() : this.persistChain;
  }

  scheduleNetworkPersist() {
    if (this.networkPersistTimer) return;
    this.networkPersistTimer = setTimeout(() => {
      this.networkPersistTimer = null;
      if (this.networkDirty) this.persist();
    }, this.networkPersistIntervalMs);
    this.networkPersistTimer.unref?.();
  }
}
