import {
  LOAD_VISUAL_MODEL_VERSION,
  fleetLoadPresentation,
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
  const providerId = String(instanceId || "");
  return {
    schemaVersion: PUBLIC_STATUS_SCHEMA_VERSION,
    serverVersion: String(serverVersion || "unknown"),
    instanceId: providerId,
    generatedAt: dashboard.generatedAt,
    demo: Boolean(dashboard.demo),
    site: dashboard.site,
    overallStatus: dashboard.overallStatus,
    provider: {
      kind: "gateway",
      scope: "fleet",
      id: providerId,
      name: dashboard.site.name,
    },
    capabilities: {
      loadVisualState: true,
      network: true,
      networkHistory: true,
      machineHistory: true,
      persistentHistory: true,
      fleetHistory: true,
      hostNetwork: true,
      pets: true,
      webDisplay: true,
      liveActivityPush: false,
    },
    network: dashboard.network,
    codex: dashboard.codex,
    fleet: projectFleet(dashboard.fleet),
    machines: dashboard.machines.map(projectMachine),
  };
}

function projectFleet(fleet) {
  const load = fleetLoadPresentation(fleet);
  return {
    ...fleet,
    loadVisualState: visualState(load),
  };
}

function projectMachine(machine) {
  const load = singleMachineLoad(machine);
  const state = loadState(load.score, load).definition;
  return {
    ...machine,
    loadVisualState: visualState({ ...load, state, sceneProfile: loadSceneProfile(load) }),
  };
}

function visualState(load) {
  const state = load.state?.id ? load.state : loadState(load.score, load).definition;
  const profile = load.sceneProfile || loadSceneProfile(load);
  return {
    modelVersion: LOAD_VISUAL_MODEL_VERSION,
    state: state.id,
    label: state.label,
    score: load.score,
    constrained: load.constrained,
    ...profile,
  };
}
