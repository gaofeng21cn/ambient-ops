import {
  loadSceneProfile,
  loadState,
  singleMachineLoad,
} from "../src/load-model.mjs";

export const PUBLIC_STATUS_SCHEMA_VERSION = 1;
export const PUBLIC_STATUS_PATH = "/api/v1/status";

export function buildPublicStatus(dashboard, {
  instanceId,
  serverVersion,
} = {}) {
  return {
    schemaVersion: PUBLIC_STATUS_SCHEMA_VERSION,
    serverVersion: String(serverVersion || "unknown"),
    instanceId: String(instanceId || ""),
    generatedAt: dashboard.generatedAt,
    demo: Boolean(dashboard.demo),
    site: dashboard.site,
    overallStatus: dashboard.overallStatus,
    capabilities: {
      loadVisualState: true,
      networkHistory: true,
      pets: true,
      liveActivityPush: false,
    },
    network: dashboard.network,
    codex: dashboard.codex,
    machines: dashboard.machines.map(projectMachine),
  };
}

function projectMachine(machine) {
  const load = singleMachineLoad(machine);
  const state = loadState(load.score, load).definition;
  return {
    ...machine,
    loadVisualState: {
      state: state.id,
      label: state.label,
      score: load.score,
      constrained: load.constrained,
      ...loadSceneProfile(load),
    },
  };
}
