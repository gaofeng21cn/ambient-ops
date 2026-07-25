const TRAFFIC_WEIGHTS = [1, 2, 3, 2, 1];

export function smoothTrafficValues(values) {
  const normalized = values.map((value) => Math.max(0, finite(value)));
  if (normalized.length < 3) return normalized;

  return normalized.map((_, index) => {
    let weightedTotal = 0;
    let weightTotal = 0;
    for (let offset = -2; offset <= 2; offset += 1) {
      const sampleIndex = index + offset;
      if (sampleIndex < 0 || sampleIndex >= normalized.length) continue;
      const weight = TRAFFIC_WEIGHTS[offset + 2];
      weightedTotal += normalized[sampleIndex] * weight;
      weightTotal += weight;
    }
    return weightedTotal / weightTotal;
  });
}

export function trafficScale(series) {
  const samples = series
    .flatMap((values) => values.map(finite))
    .filter((value) => value >= 0)
    .sort((a, b) => a - b);
  const peak = samples.length >= 50
    ? samples[Math.floor((samples.length - 1) * 0.98)]
    : Math.max(0, ...samples);
  if (peak === 0) return 1;
  return niceCeiling(peak * 1.12);
}

export function smoothTrafficPath(values, max, width = 1000, height = 300) {
  const points = values.map((value, index) => ({
    x: values.length === 1 ? 0 : index * width / (values.length - 1),
    y: scaledTrafficY(value, max, height),
  }));
  if (points.length === 0) return "";
  if (points.length === 1) {
    return `M 0 ${points[0].y.toFixed(1)} L ${width} ${points[0].y.toFixed(1)}`;
  }

  let path = `M ${points[0].x.toFixed(1)} ${points[0].y.toFixed(1)}`;
  for (let index = 1; index < points.length; index += 1) {
    const previous = points[index - 1];
    const current = points[index];
    const midpointX = (previous.x + current.x) / 2;
    const midpointY = (previous.y + current.y) / 2;
    path += ` Q ${previous.x.toFixed(1)} ${previous.y.toFixed(1)}, ${midpointX.toFixed(1)} ${midpointY.toFixed(1)}`;
  }
  const last = points.at(-1);
  path += ` Q ${last.x.toFixed(1)} ${last.y.toFixed(1)}, ${last.x.toFixed(1)} ${last.y.toFixed(1)}`;
  return path;
}

export function scaledTrafficY(value, max, height) {
  if (!(max > 0)) return height;
  return height - Math.min(height, Math.max(0, finite(value) / max * height));
}

function niceCeiling(value) {
  const exponent = Math.floor(Math.log10(value));
  const magnitude = 10 ** exponent;
  const normalized = value / magnitude;
  const step = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10;
  return step * magnitude;
}

function finite(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}
