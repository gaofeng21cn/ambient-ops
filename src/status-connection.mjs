export function connectionAfterFailure(lastSuccessAt, now = Date.now(), graceMs = 5_000) {
  return Number.isFinite(lastSuccessAt) && lastSuccessAt > 0 && now - lastSuccessAt <= graceMs
    ? "live"
    : "stale";
}
