export const STATUS_HISTORY_RETENTION_MS = 60 * 60 * 1_000;
export const STATUS_HISTORY_SAMPLE_MS = 5_000;
export const LOAD_TREND_WINDOW_MS = 30 * 60 * 1_000;

export function appendHistorySample(history, sample, options = {}) {
  const retentionMs = positive(options.retentionMs, STATUS_HISTORY_RETENTION_MS);
  const sampleIntervalMs = positive(options.sampleIntervalMs, STATUS_HISTORY_SAMPLE_MS);
  const sampleAt = new Date(sample?.at).valueOf();
  if (!Number.isFinite(sampleAt)) return Array.isArray(history) ? history : [];

  const cutoff = sampleAt - retentionMs;
  const retained = (Array.isArray(history) ? history : []).filter((entry) => {
    const at = new Date(entry?.at).valueOf();
    return Number.isFinite(at) && at >= cutoff && at <= sampleAt;
  });
  const normalized = {
    at: new Date(sampleAt).toISOString(),
    tps: Math.max(0, Number(sample?.tps) || 0),
  };
  const last = retained.at(-1);
  if (!last) return [normalized];

  const lastAt = new Date(last.at).valueOf();
  if (sampleAt < lastAt) return retained;
  if (sampleAt === lastAt) return [...retained.slice(0, -1), normalized];
  if (sampleAt - lastAt < sampleIntervalMs) {
    return [...retained.slice(0, -1), { ...normalized, at: last.at }];
  }
  return [...retained, normalized].slice(-1_000);
}

export function historyValuesInWindow(history, windowMs, nowMs = Date.now()) {
  const duration = positive(windowMs, LOAD_TREND_WINDOW_MS);
  const cutoff = nowMs - duration;
  return (Array.isArray(history) ? history : [])
    .filter((entry) => {
      const at = new Date(entry?.at).valueOf();
      return Number.isFinite(at) && at >= cutoff && at <= nowMs;
    })
    .map((entry) => Math.max(0, Number(entry?.tps) || 0));
}

function positive(value, fallback) {
  return Number.isFinite(Number(value)) && Number(value) > 0 ? Number(value) : fallback;
}
