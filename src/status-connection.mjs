export function connectionAfterFailure(lastSuccessAt, now = Date.now(), graceMs = 5_000) {
  return Number.isFinite(lastSuccessAt) && lastSuccessAt > 0 && now - lastSuccessAt <= graceMs
    ? "live"
    : "stale";
}

export function displayConnectionConfiguration(locationLike = globalThis.location) {
  const search = String(locationLike?.search || "");
  const parameters = new URLSearchParams(search);
  const requestedEndpoint = parameters.get("statusUrl");
  const requestedView = parameters.get("view");
  let statusEndpoint = "/api/status";

  if (requestedEndpoint) {
    try {
      const parsed = new URL(requestedEndpoint);
      if (parsed.protocol === "http:" || parsed.protocol === "https:") {
        statusEndpoint = parsed.href;
      }
    } catch {
      // Invalid embedded endpoints fail closed to the normal same-origin API.
    }
  }

  return Object.freeze({
    embedded: statusEndpoint !== "/api/status",
    statusEndpoint,
    requestedView,
  });
}

export function resolveStatusAssetURLs(status, statusEndpoint) {
  if (!status || !/^https?:\/\//i.test(statusEndpoint || "")) return status;

  let endpoint;
  try {
    endpoint = new URL(statusEndpoint);
  } catch {
    return status;
  }

  let changed = false;
  const machines = (status.machines || []).map((machine) => {
    const assetUrl = machine?.pet?.assetUrl;
    if (!assetUrl) return machine;
    try {
      const resolvedAsset = new URL(assetUrl, endpoint);
      changed = true;
      if (resolvedAsset.origin !== endpoint.origin) {
        return {
          ...machine,
          pet: {
            ...machine.pet,
            assetUrl: null,
            assetUrlTrustedOrigin: false,
          },
        };
      }
      return {
        ...machine,
        pet: {
          ...machine.pet,
          assetUrl: resolvedAsset.href,
          assetUrlTrustedOrigin: true,
        },
      };
    } catch {
      changed = true;
      return {
        ...machine,
        pet: {
          ...machine.pet,
          assetUrl: null,
          assetUrlTrustedOrigin: false,
        },
      };
    }
  });
  return changed ? { ...status, machines } : status;
}
