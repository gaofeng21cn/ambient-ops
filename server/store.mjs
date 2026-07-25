import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";

export class StatusStore {
  constructor(dataDir) {
    this.dataDir = dataDir;
    this.path = join(dataDir, "state.json");
    this.machines = new Map();
    this.network = { status: "error", source: "unconfigured", error: "UniFi is not configured" };
    this.networkHistory = [];
    this.persistChain = Promise.resolve();
    this.persistSequence = 0;
  }

  async load() {
    await mkdir(this.dataDir, { recursive: true });
    try {
      const saved = JSON.parse(await readFile(this.path, "utf8"));
      this.machines = new Map((saved.machines || []).map((machine) => [machine.machineId, machine]));
      this.network = saved.network || this.network;
      this.networkHistory = saved.networkHistory || [];
    } catch (error) {
      if (error.code !== "ENOENT") console.warn("Unable to load persisted state:", error.message);
    }
  }

  setMachine(snapshot) {
    this.machines.set(snapshot.machineId, snapshot);
    return this.persist();
  }

  setNetwork(network, { recordHistory = true } = {}) {
    this.network = network;
    if (recordHistory && Number.isFinite(network.downloadMbps) && Number.isFinite(network.uploadMbps)) {
      this.networkHistory.push({
        at: network.updatedAt,
        downloadMbps: network.downloadMbps,
        uploadMbps: network.uploadMbps,
      });
      this.networkHistory = this.networkHistory.slice(-120);
    }
    return this.persist();
  }

  async persist() {
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
    return this.persistChain;
  }
}
