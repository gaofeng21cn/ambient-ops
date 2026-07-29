import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import {
  Activity,
  Bird,
  Bot,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Cpu,
  Expand,
  Gauge,
  Globe2,
  Laptop,
  LayoutDashboard,
  Monitor,
  Network,
  Pin,
  Radio,
  Server,
  ShieldCheck,
  WifiOff,
  XCircle,
} from "lucide-react";
import {
  scaledTrafficY,
  smoothTrafficPath,
  smoothTrafficValues,
  trafficScale,
} from "./traffic-chart.mjs";
import {
  petAnimationForState,
  petFrameAtElapsed,
  petFramePosition,
  petPlaybackForState,
  petSpriteGrid,
  petSpriteKey,
  resolvePetSpriteUrl,
  selectDisplayMachine,
  shouldReducePetMotion,
} from "./pet-display.mjs";
import { fetchWithTimeout } from "./http.mjs";
import { connectionAfterFailure } from "./status-connection.mjs";
import {
  appendHistorySample,
  historyValuesInWindow,
  LOAD_TREND_WINDOW_MS,
} from "./status-history.mjs";
import {
  loadParticlePhase,
  loadSceneProfile,
  singleMachineLoad,
  loadState,
} from "./load-model.mjs";
import { shouldReduceKioskMotion } from "./kiosk-motion.mjs";

const VIEWS = ["overview", "network", "machines", "load", "pet"];
const VIEW_LABELS = { overview: "Overview", network: "Network", machines: "Machines", load: "Load", pet: "Pet" };
const CONNECTION_STALE_GRACE_MS = 5_000;
const PET_STATE_LABELS = {
  idle: "IDLE",
  failed: "OFFLINE",
  waiting: "WAITING",
  running: "WORKING",
  review: "REVIEWING",
};
const EMPTY_STATUS = {
  site: { name: "Ambient Ops", timeZone: "Asia/Shanghai" },
  generatedAt: new Date().toISOString(),
  demo: false,
  overallStatus: "error",
  network: { status: "error", history: [] },
  codex: { status: "error", oneMinuteTps: 0, fiveMinuteTps: 0, cachePercent: 0, activeSessions: 0, cpuPercent: null, machineCount: 0 },
  machines: [],
};

export function App() {
  const pairingMatch = location.pathname.match(/^\/pair\/([a-zA-Z0-9_-]{32,80})$/);
  if (pairingMatch) return <PairingApproval requestId={pairingMatch[1]} />;
  const eink = location.pathname.startsWith("/display/eink");
  const [status, connection] = useStatus();
  if (eink) return <EinkDisplay status={status} connection={connection} />;
  return <Dashboard status={status} connection={connection} />;
}

function PairingApproval({ requestId }) {
  const [pairing, setPairing] = useState(null);
  const [state, setState] = useState("loading");
  const [error, setError] = useState("");

  useEffect(() => {
    let stopped = false;
    fetchWithTimeout(`/api/v1/pairings/${requestId}`, { cache: "no-store" })
      .then(async (response) => {
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
        if (!stopped) {
          setPairing(payload);
          setState(payload.status);
        }
      })
      .catch((nextError) => {
        if (!stopped) {
          setError(nextError.message);
          setState("error");
        }
      });
    return () => { stopped = true; };
  }, [requestId]);

  const respond = async (action) => {
    setState("submitting");
    setError("");
    try {
      const response = await fetch(`/api/v1/pairings/${requestId}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action,
          verificationCode: pairing.verificationCode,
        }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
      setPairing(payload);
      setState(payload.status);
    } catch (nextError) {
      setError(nextError.message);
      setState("error");
    }
  };

  const finished = state === "approved" || state === "rejected";
  return (
    <main className="pairing-shell">
      <section className={`pairing-panel ${finished ? state : ""}`}>
        <div className="pairing-mark" aria-hidden="true">
          {state === "approved" ? <CheckCircle2 /> : state === "rejected" || state === "error" ? <XCircle /> : <ShieldCheck />}
        </div>
        {state === "loading" ? (
          <>
            <h1>Checking request</h1>
            <p>Reading the Codex TPS pairing request.</p>
          </>
        ) : null}
        {pairing && (state === "pending" || state === "submitting") ? (
          <>
            <h1>Connect Codex TPS</h1>
            <p>Approve this device only when the code matches Codex TPS.</p>
            <dl className="pairing-device">
              <div><dt>Device</dt><dd>{pairing.machineName}</dd></div>
              <div><dt>Platform</dt><dd>{pairing.platform}</dd></div>
              <div className="pairing-code-row"><dt>Pairing code</dt><dd>{pairing.verificationCode}</dd></div>
            </dl>
            {pairing.replacement ? <p className="pairing-warning">This replaces the existing key for the same machine ID.</p> : null}
            <div className="pairing-actions">
              <button type="button" className="pairing-secondary" disabled={state === "submitting"} onClick={() => respond("reject")}>Reject</button>
              <button type="button" className="pairing-primary" disabled={state === "submitting"} onClick={() => respond("approve")}>
                {state === "submitting" ? "Approving..." : "Allow device"}
              </button>
            </div>
          </>
        ) : null}
        {state === "approved" ? (
          <>
            <h1>Device connected</h1>
            <p>{pairing.machineName} can now send signed aggregate metrics. You can close this page.</p>
          </>
        ) : null}
        {state === "rejected" ? (
          <>
            <h1>Request rejected</h1>
            <p>No device key was added. You can close this page.</p>
          </>
        ) : null}
        {state === "error" ? (
          <>
            <h1>Pairing unavailable</h1>
            <p>{error || "This request expired or could not be read."}</p>
          </>
        ) : null}
      </section>
    </main>
  );
}

function useStatus() {
  const cached = useMemo(() => {
    try { return JSON.parse(localStorage.getItem("home-status-last") || "null"); } catch { return null; }
  }, []);
  const [status, setStatus] = useState(cached || EMPTY_STATUS);
  const [connection, setConnection] = useState(cached ? "stale" : "loading");
  const lastSuccessAt = useRef(0);

  useEffect(() => {
    let stopped = false;
    let timer;
    const refresh = async () => {
      try {
        const response = await fetchWithTimeout("/api/status", { cache: "no-store" });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const next = await response.json();
        if (stopped) return;
        setStatus((current) => {
          const merged = mergeStatusHistory(current, next);
          localStorage.setItem("home-status-last", JSON.stringify(merged));
          return merged;
        });
        lastSuccessAt.current = Date.now();
        setConnection("live");
      } catch {
        if (!stopped) {
          setConnection(connectionAfterFailure(lastSuccessAt.current, Date.now(), CONNECTION_STALE_GRACE_MS));
        }
      } finally {
        if (!stopped) timer = setTimeout(refresh, 250);
      }
    };
    refresh();
    return () => { stopped = true; clearTimeout(timer); };
  }, []);

  return [status, connection];
}

function Dashboard({ status, connection }) {
  const [view, setView] = useState(initialView);
  const [selectedMachineId, setSelectedMachineId] = useState(
    () => localStorage.getItem("ambient-ops-machine-id") || status.machines[0]?.machineId || null,
  );
  const [machineFollowMode, setMachineFollowMode] = useState(
    () => localStorage.getItem("ambient-ops-machine-mode") === "fixed" ? "fixed" : "auto",
  );
  const pointerStart = useRef(null);
  const selectedMachine = selectDisplayMachine(status.machines, selectedMachineId, machineFollowMode);

  useEffect(() => {
    const next = `/display/${view}`;
    if (location.pathname !== next) history.replaceState(null, "", next);
  }, [view]);

  useEffect(() => {
    if (selectedMachine?.machineId) {
      localStorage.setItem("ambient-ops-machine-id", selectedMachine.machineId);
    }
    localStorage.setItem("ambient-ops-machine-mode", machineFollowMode);
  }, [machineFollowMode, selectedMachine?.machineId]);

  const switchBy = useCallback((offset) => {
    setView((current) => VIEWS[(VIEWS.indexOf(current) + offset + VIEWS.length) % VIEWS.length]);
  }, []);

  const onPointerDown = (event) => {
    if (event.target.closest("button, select, input, a")) return;
    pointerStart.current = { x: event.clientX, y: event.clientY };
  };
  const onPointerUp = (event) => {
    if (!pointerStart.current) return;
    const dx = event.clientX - pointerStart.current.x;
    const dy = event.clientY - pointerStart.current.y;
    pointerStart.current = null;
    if (Math.abs(dx) > 90 && Math.abs(dx) > Math.abs(dy) * 1.4) switchBy(dx < 0 ? 1 : -1);
  };

  const goToMachine = (machineId) => {
    setSelectedMachineId(machineId);
    setMachineFollowMode("fixed");
    setView("machines");
  };
  const selectMachine = (machineId) => {
    setSelectedMachineId(machineId);
    setMachineFollowMode("fixed");
  };

  return (
    <div className="app-shell" onPointerDown={onPointerDown} onPointerUp={onPointerUp}>
      <Header status={status} connection={connection} />
      <main className="view-stage">
        {view === "overview" ? <Overview status={status} onMachine={goToMachine} onAllMachines={() => setView("machines")} /> : null}
        {view === "network" ? <NetworkView network={status.network} /> : null}
        {view === "machines" ? (
          <MachinesView
            machines={status.machines}
            selected={selectedMachine}
            onSelect={selectMachine}
          />
        ) : null}
        {view === "load" ? (
          <LoadView
            machines={status.machines}
            selected={selectedMachine}
            followMode={machineFollowMode}
            onFollowMode={setMachineFollowMode}
            onSelect={selectMachine}
          />
        ) : null}
        {view === "pet" ? (
          <PetView
            machines={status.machines}
            selected={selectedMachine}
            followMode={machineFollowMode}
            onFollowMode={setMachineFollowMode}
            onSelect={selectMachine}
          />
        ) : null}
      </main>
      <BottomNav view={view} setView={setView} status={status} connection={connection} />
    </div>
  );
}

function initialView() {
  const route = location.pathname.split("/").pop();
  return VIEWS.includes(route) ? route : "overview";
}

function Header({ status, connection }) {
  const now = useClock();
  return (
    <header className="top-header">
      <time>{formatTime(now, status.site?.timeZone)}</time>
      <h1>{status.site?.name || "Ambient Ops"}</h1>
      <div className="header-status">
        {status.demo ? <span className="mode-label">DEMO</span> : null}
        <StatusLabel status={connection === "live" ? status.overallStatus : "stale"} />
        <span className="divider" />
        <span className="source-label">Gateway &amp; Codex Agents</span>
        <FullscreenButton />
      </div>
    </header>
  );
}

function LoadView({ machines, selected, followMode, onFollowMode, onSelect }) {
  if (!selected) return <section className="load-view"><EmptyState /></section>;
  const Icon = machineIcon(selected.platform);
  const baseLoad = singleMachineLoad(selected);
  const load = { ...baseLoad, sceneProfile: loadSceneProfile(baseLoad) };
  const state = loadState(load.score, load).definition;
  const shortTrendValues = historyValuesInWindow(selected.tpsHistory, 5 * 60 * 1_000);
  const loadTrendValues = historyValuesInWindow(selected.tpsHistory, LOAD_TREND_WINDOW_MS);
  const loadTrendAverage = loadTrendValues.length
    ? loadTrendValues.reduce((total, value) => total + value, 0) / loadTrendValues.length
    : Number(selected.fiveMinutes.tps || 0);

  return (
    <section className={`load-view load-state-${state.id}`}>
      <div className="load-canvas">
        <div className="load-canvas-head">
          <div className="load-machine-picker">
            <Icon size={17} />
            <PetMachineControl machines={machines} selected={selected} followMode={followMode} onFollowMode={onFollowMode} onSelect={onSelect} ariaLabel="Load host" />
          </div>
          <div className="load-canvas-title">
            <span>DEVELOPMENT LOAD</span>
            <strong>{state.label}</strong>
            <small>{loadStateDescription(state.id)}</small>
          </div>
        </div>
        <div className="load-field-header">
          <span>AGGREGATE WORK FIELD</span>
          <div className="load-field-legend" aria-hidden="true">
            <i className="density" /> DENSITY
            <i className="rhythm" /> RHYTHM
          </div>
        </div>
        <LoadPixelField state={state} machineName={selected.machineName} load={load} />
        <div className="load-canvas-footer">
          <LoadScale score={load.score} />
          <span>{load.sceneProfile?.clusterCount ? "AGGREGATE FLOW" : "STANDBY STATION"} · {formatTps(load.tps)} TPS</span>
        </div>
      </div>
      <aside className="load-side-metrics">
        <div className="load-side-primary">
          <span>1 MINUTE</span>
          <div><strong>{formatTps(load.tps)}</strong><small>TPS</small></div>
          <Sparkline values={shortTrendValues} color="green" />
        </div>
        <div className="load-side-stats">
          <LoadStat label="ACTIVE" value={load.sessions} unit="CONVERSATIONS" accent="green" />
          <LoadStat label="CPU" value={load.cpu === null ? "N/A" : `${Math.round(load.cpu)}%`} unit="HOST" accent={load.cpu === null ? "muted" : load.cpu > 80 ? "amber" : "green"} />
          <LoadStat label="CACHE" value={`${selected.cachePercent || 0}%`} />
        </div>
        <div className="load-side-trend">
          <div><span>30 MIN TREND</span><small>{formatTps(loadTrendAverage)} TPS AVG</small></div>
          <Sparkline values={loadTrendValues} color="green" />
          <div className="load-side-axis"><span>-30m</span><span>-20m</span><span>-10m</span><span>now</span></div>
        </div>
        <div className="load-side-host">
          <span className={`load-host-freshness ${selected.status}`}><i /> HOST · {hostFreshness(selected)}</span>
          <span className="load-host-platform">{selected.platform}</span>
          <span className="load-side-note"><Cpu size={14} /> {load.cpu === null ? "CPU unavailable until TPS host telemetry is enabled." : "Host CPU is optional telemetry."}</span>
        </div>
      </aside>
    </section>
  );
}

function LoadScale({ score }) {
  return (
    <div className="load-scale" aria-label={`Relative load ${Math.round(score * 100)} percent`}>
      <div className="load-scale-bar"><i style={{ width: `${Math.max(3, score * 100)}%` }} /></div>
      <div><span>QUIET</span><span>ACTIVE</span><span>HEAVY</span><span>LIMIT</span></div>
    </div>
  );
}

function loadStateDescription(stateId) {
  return {
    quiet: "standby station",
    active: "focused work",
    heavy: "parallel work",
    constrained: "pressure building",
  }[stateId] || "work field";
}

function LoadPixelField({ state, machineName, load }) {
  const canvasRef = useRef(null);
  const prefersReducedMotion = usePrefersReducedMotion();
  const reduceMotion = shouldReduceKioskMotion(navigator.userAgent, prefersReducedMotion);
  const profile = useMemo(
    () => loadSceneProfile(load),
    [load.score, load.sessions, load.tps, load.cpu, load.cpuPressure, load.constrained],
  );
  const visual = useMemo(() => ({ ...profile, stateId: state.id }), [profile, state.id]);
  const visualRef = useRef(visual);
  visualRef.current = visual;

  useLoadPixelMotion(canvasRef, visualRef, reduceMotion);

  return (
    <div
      className={`load-pixel-field load-pixel-${state.id}`}
      role="img"
      aria-label={`${state.label} pixel workload animation for ${machineName}`}
      style={{
        "--pixel-score": load.score,
      }}
    >
      <canvas ref={canvasRef} className="load-pixel-canvas" aria-hidden="true" />
    </div>
  );
}

function useLoadPixelMotion(canvasRef, visualRef, reduceMotion) {
  useEffect(() => {
    const canvas = canvasRef.current;
    const field = canvas?.parentElement;
    if (!canvas || !field) return undefined;
    const context = canvas.getContext("2d");
    if (!context) return undefined;

    let width = 0;
    let height = 0;
    const resize = () => {
      const bounds = field.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = Math.max(1, bounds.width);
      height = Math.max(1, bounds.height);
      canvas.width = Math.max(1, Math.round(width * dpr));
      canvas.height = Math.max(1, Math.round(height * dpr));
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      context.setTransform(dpr, 0, 0, dpr, 0, 0);
      context.imageSmoothingEnabled = false;
    };
    resize();
    const observer = typeof ResizeObserver === "function" ? new ResizeObserver(resize) : null;
    observer?.observe(field);
    const startedAt = window.performance.now();
    let animationFrame = null;
    let lastPaintAt = -Infinity;
    let assetReady = false;
    const workstation = new Image();
    workstation.decoding = "async";
    workstation.onload = () => { assetReady = true; };
    workstation.src = "/load/operator-workbench.webp";

    const paint = (timestamp) => {
      const frameBudget = reduceMotion ? 140 : 34;
      if (timestamp - lastPaintAt < frameBudget) {
        animationFrame = window.requestAnimationFrame(paint);
        return;
      }
      lastPaintAt = timestamp;
      const elapsed = timestamp - startedAt;
      paintWorkbenchCanvas(context, width, height, elapsed, visualRef.current, assetReady ? workstation : null);
      animationFrame = window.requestAnimationFrame(paint);
    };

    paint(startedAt);
    return () => {
      if (animationFrame !== null) window.cancelAnimationFrame(animationFrame);
      observer?.disconnect();
      workstation.onload = null;
    };
  }, [canvasRef, visualRef, reduceMotion]);
}

function paintWorkbenchCanvas(context, width, height, elapsed, visual, workstation) {
  if (width <= 1 || height <= 1) return;
  const activity = clampVisual(visual.activity);
  const parallel = clampVisual(visual.parallel);
  const pressure = clampVisual(visual.pressure);
  const queueDepth = clampVisual(visual.queueDepth);
  const heat = clampVisual(visual.heat);
  const tempo = Math.max(.2, Number(visual.tempo) || .2);
  const pixel = Math.max(2, Math.round(Math.min(width, height) / 86));
  const centerY = Math.round(height * .53);

  context.clearRect(0, 0, width, height);
  context.fillStyle = "#05090d";
  context.fillRect(0, 0, width, height);
  drawWorkstationGrid(context, width, height, pixel, activity);

  const spriteSize = Math.round(Math.min(height * 1.34, width * .48));
  const spriteX = Math.round(Math.max(4, width * .015));
  const spriteY = Math.round((height - spriteSize) / 2 + Math.sin(elapsed / 1_700) * (0.4 + activity * .9));
  if (workstation) {
    context.imageSmoothingEnabled = false;
    context.drawImage(workstation, spriteX, spriteY, spriteSize, spriteSize);
  } else {
    drawFallbackWorkstation(context, spriteX, spriteY, spriteSize, pixel);
  }

  const screen = {
    x: spriteX + spriteSize * .56,
    y: spriteY + spriteSize * .205,
    width: spriteSize * .225,
    height: spriteSize * .205,
  };
  drawScreenActivity(context, screen, elapsed, activity, pressure, pixel);

  const emitterX = Math.min(width * .59, spriteX + spriteSize * .79);
  const emitterY = spriteY + spriteSize * .36;
  drawWorkPackets(context, width, height, emitterX, emitterY, elapsed, visual, pixel);
  drawPressureQueue(context, emitterX, emitterY, elapsed, queueDepth, pressure, pixel);
  drawComputerHeat(context, spriteX, spriteY, spriteSize, elapsed, heat, pressure, pixel);
  drawStationFloor(context, width, height, centerY, pixel, activity);
  context.globalAlpha = 1;
}

function drawWorkstationGrid(context, width, height, pixel, activity) {
  const step = pixel * 6;
  context.fillStyle = "rgba(34, 52, 62, .36)";
  for (let x = step; x < width; x += step) context.fillRect(x, 0, 1, height);
  for (let y = step; y < height; y += step) context.fillRect(0, y, width, 1);
  context.fillStyle = `rgba(56, 189, 248, ${.018 + activity * .03})`;
  context.fillRect(Math.round(width * .53), 0, 1, height);
}

function drawScreenActivity(context, screen, elapsed, activity, pressure, pixel) {
  const pulse = .55 + .45 * Math.sin(elapsed / Math.max(190, 640 - activity * 330));
  context.save();
  context.globalAlpha = .72;
  context.fillStyle = "#071318";
  context.fillRect(screen.x, screen.y, screen.width, screen.height);
  const rows = 4 + Math.round(activity * 4);
  for (let row = 0; row < rows; row += 1) {
    const widthFactor = .25 + pixelNoise(row + 7) * (.45 + activity * .25);
    context.fillStyle = row % 3 === 0 ? "#38bdf8" : row % 3 === 1 ? "#39d891" : "#9ee7bd";
    context.globalAlpha = .42 + pulse * .25;
    context.fillRect(
      Math.round(screen.x + pixel * 1.8),
      Math.round(screen.y + pixel * (1.6 + row * 2.2)),
      Math.max(pixel, Math.round(screen.width * widthFactor)),
      Math.max(1, Math.round(pixel * .72)),
    );
    if (row % 2 === 0) {
      context.globalAlpha *= .58;
      context.fillRect(
        Math.round(screen.x + screen.width * (.7 + pixelNoise(row + 30) * .17)),
        Math.round(screen.y + pixel * (1.6 + row * 2.2)),
        pixel,
        Math.max(1, Math.round(pixel * .72)),
      );
    }
  }
  const cursorY = screen.y + screen.height - pixel * 2.2;
  context.globalAlpha = pressure > .1 ? .45 + pulse * .35 : .8;
  context.fillStyle = pressure > .68 ? "#ffbd58" : "#39d891";
  if (Math.floor(elapsed / Math.max(160, 440 - activity * 220)) % 2 === 0) {
    context.fillRect(Math.round(screen.x + pixel * 2), Math.round(cursorY), pixel * 2, Math.max(1, Math.round(pixel * .72)));
  }
  context.restore();
}

function drawWorkPackets(context, width, height, emitterX, emitterY, elapsed, visual, pixel) {
  const activity = clampVisual(visual.activity);
  const pressure = clampVisual(visual.pressure);
  const parallel = clampVisual(visual.parallel);
  const tempo = Math.max(.2, Number(visual.tempo) || .2);
  const flowCount = Math.max(0, Math.min(4, Math.round(visual.clusterCount || 0)));
  if (flowCount === 0) return;
  const density = clampVisual(visual.taskDensity);
  const travelMs = Math.max(760, Number(visual.travelMs) || 3_100);
  const count = Math.round(28 + density * 138 + parallel * 46);
  const endX = Math.max(emitterX + pixel * 10, width - pixel * 4);
  const travel = Math.max(pixel * 10, endX - emitterX);
  const spread = height * (.1 + activity * .38);
  for (let index = 0; index < count; index += 1) {
    const seed = index * 8.173 + 1.7;
    const duration = travelMs * (.82 + (index % 7) * .055);
    const phase = loadParticlePhase(elapsed, duration, pixelNoise(seed) + index / count);
    const progress = phase * (1.08 - phase * .08);
    const x = emitterX + travel * progress;
    const band = index % flowCount;
    const bandOffset = (band - (flowCount - 1) / 2) * spread * (.32 / Math.max(1, flowCount - 1));
    const fan = (pixelNoise(seed + 1.3) - .5) * spread * (.18 + progress * .68);
    const wave = Math.sin(elapsed / (230 + (index % 5) * 47) + seed) * pixel * (.8 + activity * 2.8);
    const y = emitterY + bandOffset + fan + wave;
    const size = pixel * (index % 13 === 0 ? 2 : index % 5 === 0 ? 1.5 : 1);
    const hot = pressure > .28 && progress > .38;
    const color = hot
      ? pressure > .74 && progress > .58 ? "#ff5d6c" : "#ffbd58"
      : index % 4 === 0 ? "#38bdf8" : index % 7 === 0 ? "#9ee7bd" : "#39d891";
    const envelope = Math.min(1, phase / .055, (1 - phase) / .1);
    const alpha = envelope * (.42 + activity * .42 + (index % 4) * .035);
    const tailLength = Math.round(pixel * (1.5 + tempo * 1.7 + (index % 3)));
    context.fillStyle = color;
    context.globalAlpha = Math.min(.3, alpha * .34);
    context.fillRect(Math.round(x - tailLength), Math.round(y), tailLength, pixel);
    context.globalAlpha = Math.min(.96, alpha);
    context.fillRect(Math.round(x), Math.round(y), Math.max(pixel, Math.round(size)), pixel);
    if (index % 9 === 0 && progress > .18) {
      context.globalAlpha *= .48;
      context.fillRect(
        Math.round(x - tailLength - pixel * 2),
        Math.round(y + (index % 2 ? pixel * 2 : -pixel * 2)),
        pixel,
        pixel,
      );
    }
  }
  context.globalAlpha = 1;
}

function drawPressureQueue(context, emitterX, emitterY, elapsed, queueDepth, pressure, pixel) {
  if (queueDepth <= .05) return;
  const count = Math.round(3 + queueDepth * 12);
  const wobble = Math.sin(elapsed / 260) * pixel * (1 + pressure * 2);
  for (let index = 0; index < count; index += 1) {
    const back = pixel * (3 + (index % 6) * 2);
    const y = emitterY + (index % 5 - 2) * pixel * 2 + wobble * (index % 2 ? .45 : .18);
    context.fillStyle = pressure > .74 ? "#ff5d6c" : "#ffbd58";
    context.globalAlpha = .28 + (index % 3) * .12;
    context.fillRect(Math.round(emitterX - back), Math.round(y), pixel * (index % 4 === 0 ? 2 : 1), pixel);
  }
  context.globalAlpha = 1;
}

function drawComputerHeat(context, spriteX, spriteY, spriteSize, elapsed, heat, pressure, pixel) {
  if (heat <= .05) return;
  const x = spriteX + spriteSize * .83;
  const y = spriteY + spriteSize * .34;
  const pulse = .35 + .3 * Math.sin(elapsed / 220);
  context.fillStyle = pressure > .7 ? "#ff5d6c" : "#ffbd58";
  context.globalAlpha = .22 + heat * .35 + pulse * heat;
  for (let index = 0; index < 3; index += 1) {
    context.fillRect(Math.round(x + index * pixel * 2), Math.round(y + (index % 2) * pixel * 2), pixel, pixel * (2 + index));
  }
  context.globalAlpha = 1;
}

function drawStationFloor(context, width, height, centerY, pixel, activity) {
  context.fillStyle = `rgba(12, 21, 26, ${.78 - activity * .08})`;
  context.fillRect(0, Math.round(height * .88), width, Math.max(1, pixel));
  context.fillStyle = "rgba(56, 189, 248, .14)";
  context.fillRect(pixel * 2, Math.round(height * .88) - pixel, Math.round(width * .28), 1);
  context.fillStyle = "rgba(57, 216, 145, .12)";
  context.fillRect(Math.round(width * .67), Math.round(height * .88) - pixel, Math.round(width * .24), 1);
}

function drawFallbackWorkstation(context, x, y, size, pixel) {
  const top = y + size * .22;
  const left = x + size * .52;
  context.fillStyle = "#101c22";
  context.fillRect(Math.round(left), Math.round(top), Math.round(size * .28), Math.round(size * .2));
  context.fillStyle = "#38bdf8";
  context.fillRect(Math.round(left + pixel * 2), Math.round(top + pixel * 2), Math.round(size * .2), pixel);
  context.fillStyle = "#17252b";
  context.fillRect(Math.round(x + size * .18), Math.round(y + size * .42), Math.round(size * .55), Math.round(size * .15));
  context.fillStyle = "#39d891";
  context.fillRect(Math.round(x + size * .1), Math.round(y + size * .28), pixel * 3, pixel * 5);
}

function pixelNoise(seed) {
  const value = Math.sin(seed * 12.9898) * 43758.5453;
  return value - Math.floor(value);
}

function clampVisual(value) {
  return Math.max(0, Math.min(1, Number(value) || 0));
}

function LoadStat({ label, value, unit, accent = "" }) {
  return (
    <div className={`load-side-stat ${accent}`}>
      <span>{label}</span>
      <div><strong>{value}</strong>{unit ? <small>{unit}</small> : null}</div>
    </div>
  );
}

function Overview({ status, onMachine, onAllMachines }) {
  return (
    <>
      <DeviceOverview status={status} />
      <div className="overview-grid">
        <Panel className="internet-panel" title="Internet" icon={Globe2} action={<span className="panel-action">WAN: Primary <StatusLabel status={status.network.status} compact /></span>}>
          <ThroughputSummary network={status.network} />
          <TrafficChart points={status.network.history} allowSampleData={status.demo} />
          <div className="chart-legend">
            <Legend color="blue" label="Download" />
            <Legend color="green" label="Upload" />
            <span className="chart-scale">Scale: auto</span>
          </div>
        </Panel>
        <div className="right-column">
          <Panel className="codex-panel" title="Codex" icon={Bot} action={<StatusLabel status={status.codex.status} />}>
            <CodexSummary codex={status.codex} />
            <Sparkline values={status.codex.tpsHistory?.map((sample) => sample.tps) || []} color="green" compact />
          </Panel>
          <Panel className="machine-panel" title={`Machines (${status.machines.length})`} icon={Monitor} action={<button className="panel-link" type="button" onClick={onAllMachines}>All <ChevronRight size={20} /></button>}>
            <MachineList machines={status.machines} onMachine={onMachine} />
          </Panel>
        </div>
      </div>
    </>
  );
}

function DeviceOverview({ status }) {
  const liveMachines = status.machines.filter((machine) => machine.status === "live").length;
  return (
    <section className="device-overview">
      <div className="device-primary-metrics">
        <DeviceMetric label="Download" value={formatMetric(status.network.downloadMbps)} unit="Mbps" accent="download" />
        <DeviceMetric label="Upload" value={formatMetric(status.network.uploadMbps)} unit="Mbps" accent="upload" />
        <DeviceMetric label="Codex" value={formatTps(status.codex.oneMinuteTps)} unit="TPS" accent="codex" />
      </div>
      <section className="device-airview">
        <AirViewChart points={status.network.history} allowSampleData={status.demo} />
      </section>
      <div className="device-summary-grid">
        <DeviceStat label="CODEX 5M" value={formatTps(status.codex.fiveMinuteTps)} unit="TPS" />
        <DeviceStat label="CACHE" value={status.codex.cachePercent} unit="%" />
        <DeviceStat label="LIVE" value={`${liveMachines}/${status.machines.length}`} accent={liveMachines === status.machines.length ? "green" : "amber"} />
      </div>
    </section>
  );
}

function DeviceMetric({ label, value, unit, accent, className = "" }) {
  const density = metricDensity(value);
  return (
    <div className={`device-metric ${accent || ""} ${className}`} data-density={density}>
      <span>{label}</span>
      <div><strong>{value}</strong>{unit ? <small>{unit}</small> : null}</div>
    </div>
  );
}

function DeviceStat({ label, value, unit, accent = "" }) {
  return (
    <div className="device-stat">
      <span>{label}</span>
      <div><strong className={accent}>{value}</strong>{unit ? <small>{unit}</small> : null}</div>
    </div>
  );
}

function AirViewChart({ points = [], allowSampleData = false }) {
  const chartId = useId().replace(/:/g, "");
  const fillId = `${chartId}-airview-fill`;
  const uploadFillId = `${chartId}-airview-upload-fill`;
  const downloadStrokeId = `${chartId}-airview-download-stroke`;
  const uploadStrokeId = `${chartId}-airview-upload-stroke`;
  const data = trafficData(points, allowSampleData);
  if (data.length === 0) return <div className="airview-empty">Waiting for WAN samples</div>;
  const downloadValues = smoothTrafficValues(data.map((point) => point.downloadMbps || 0));
  const uploadValues = smoothTrafficValues(data.map((point) => point.uploadMbps || 0));
  const max = trafficScale([downloadValues, uploadValues]);
  const download = smoothTrafficPath(downloadValues, max, 1000, 100);
  const upload = smoothTrafficPath(uploadValues, max, 1000, 100);
  const lastDownloadY = scaledTrafficY(downloadValues.at(-1), max, 100);
  const lastUploadY = scaledTrafficY(uploadValues.at(-1), max, 100);
  return (
    <div className="airview-frame">
      <div className="airview-meta" aria-hidden="true">
        <span>{formatScale(max)} Mbps</span>
        <span>{historyWindowSeconds(data)}s</span>
      </div>
      <svg
        className="airview-chart"
        viewBox="0 0 1000 100"
        preserveAspectRatio="none"
        role="img"
        aria-label={`Live WAN throughput, ${formatMetric(downloadValues.at(-1))} Mbps download and ${formatMetric(uploadValues.at(-1))} Mbps upload`}
      >
        <defs>
          <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#38bdf8" stopOpacity=".2" /><stop offset="1" stopColor="#38bdf8" stopOpacity=".015" /></linearGradient>
          <linearGradient id={uploadFillId} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#b264eb" stopOpacity=".12" /><stop offset="1" stopColor="#b264eb" stopOpacity="0" /></linearGradient>
          <linearGradient id={downloadStrokeId} x1="0" y1="0" x2="1" y2="0"><stop offset="0" stopColor="#70b9ff" stopOpacity=".58" /><stop offset=".7" stopColor="#70b9ff" stopOpacity=".88" /><stop offset="1" stopColor="#8bc7ff" /></linearGradient>
          <linearGradient id={uploadStrokeId} x1="0" y1="0" x2="1" y2="0"><stop offset="0" stopColor="#a85fe1" stopOpacity=".54" /><stop offset=".7" stopColor="#b264eb" stopOpacity=".86" /><stop offset="1" stopColor="#c47df5" /></linearGradient>
        </defs>
        <g className="airview-grid">
          <line x1="0" y1="25" x2="1000" y2="25" />
          <line x1="0" y1="50" x2="1000" y2="50" />
          <line x1="0" y1="75" x2="1000" y2="75" />
          <line x1="200" y1="0" x2="200" y2="100" />
          <line x1="400" y1="0" x2="400" y2="100" />
          <line x1="600" y1="0" x2="600" y2="100" />
          <line x1="800" y1="0" x2="800" y2="100" />
        </g>
        <line className="airview-baseline" x1="0" y1="99" x2="1000" y2="99" />
        <path className="airview-fill" fill={`url(#${fillId})`} d={`${download} L 1000 100 L 0 100 Z`} />
        <path className="airview-upload-fill" fill={`url(#${uploadFillId})`} d={`${upload} L 1000 100 L 0 100 Z`} />
        <path className="airview-download" style={{ stroke: `url(#${downloadStrokeId})` }} d={download} />
        <path className="airview-upload" style={{ stroke: `url(#${uploadStrokeId})` }} d={upload} />
        <line className="airview-cursor" x1="998" y1="0" x2="998" y2="100" />
        <g className="airview-live-edge">
          <circle className="airview-halo download" cx="998" cy={lastDownloadY} r="7" />
          <circle className="airview-dot download" cx="998" cy={lastDownloadY} r="3.2" />
          <circle className="airview-halo upload" cx="998" cy={lastUploadY} r="5.5" />
          <circle className="airview-dot upload" cx="998" cy={lastUploadY} r="2.5" />
        </g>
      </svg>
    </div>
  );
}

function NetworkView({ network }) {
  const clients = networkClientsMetric(network);
  const latency = networkLatencyMetric(network);
  return (
    <>
      <DeviceNetworkView network={network} />
      <div className="network-view">
        <section className="network-hero">
          <div className="section-heading"><Globe2 size={26} /><h2>Internet</h2><StatusLabel status={network.status} /></div>
          <ThroughputSummary network={network} large />
          <div className="network-facts">
            <Fact label="Connected clients" value={clients.value} />
            <Fact label="Probe latency" value={`${latency.value}${latency.unit ? ` ${latency.unit}` : ""}`} accent={latency.accent} />
            <Fact label="Data source" value={network.source === "unifi" ? "UniFi Gateway" : network.source === "unifi-snmp-v3" ? "UniFi SNMPv3" : network.source === "demo" ? "Demonstration" : "Unconfigured"} />
            <Fact label="Last update" value={formatAge(network.updatedAt)} />
          </div>
        </section>
        <section className="network-chart-wrap">
          <div className="section-heading"><Activity size={24} /><h2>WAN throughput</h2><span>Last {historyWindowSeconds(network.history)}s</span></div>
          <TrafficChart points={network.history} detailed allowSampleData={network.source === "demo"} />
          <div className="chart-legend"><Legend color="blue" label="Download" /><Legend color="green" label="Upload" /></div>
        </section>
      </div>
    </>
  );
}

function DeviceNetworkView({ network }) {
  const clients = networkClientsMetric(network);
  const latency = networkLatencyMetric(network);
  return (
    <section className="device-network-view">
      <div className="device-network-metrics">
        <DeviceMetric label="Download" value={formatMetric(network.downloadMbps)} unit="Mbps" accent="download" />
        <DeviceMetric label="Upload" value={formatMetric(network.uploadMbps)} unit="Mbps" accent="upload" />
      </div>
      <section className="device-airview network-airview"><AirViewChart points={network.history} allowSampleData={network.source === "demo"} /></section>
      <div className="device-summary-grid network-summary">
        <DeviceStat label="CLIENTS" value={clients.value} />
        <DeviceStat label="LATENCY" value={latency.value} unit={latency.unit} accent={latency.accent} />
      </div>
    </section>
  );
}

function MachinesView({ machines, selected, onSelect }) {
  return (
    <>
      <DeviceMachinesView machines={machines} selected={selected} onSelect={onSelect} />
      <div className="machines-view">
        <section className="machine-directory">
          <div className="section-heading"><Monitor size={26} /><h2>Machines</h2><span>{machines.length} agents</span></div>
          <MachineList machines={machines} onMachine={onSelect} selectedId={selected?.machineId} expanded />
        </section>
        <section className="machine-detail">
          {selected ? <MachineDetail machine={selected} /> : <EmptyState />}
        </section>
      </div>
    </>
  );
}

function DeviceMachinesView({ machines, selected, onSelect }) {
  if (!selected) return <section className="device-machines-view"><EmptyState /></section>;
  const activity = machineActivity(selected);
  return (
    <section className="device-machines-view">
      <div className="device-machine-tabs">
        {machines.map((machine) => (
          <button
            className={selected.machineId === machine.machineId ? "selected" : ""}
            key={machine.machineId}
            onClick={() => onSelect(machine.machineId)}
            title={machine.machineName}
          >
            <i className={machine.status} />
            <span>{machine.machineName}</span>
          </button>
        ))}
      </div>
      <div className="device-machine-body">
        <div className="device-machine-primary">
          <span className={`device-machine-activity ${activity.active ? "working" : "idle"}`}>
            <strong>{activity.label}</strong> · {activity.detail}
          </span>
          <DeviceMetric label="1 min" value={formatTps(selected.oneMinute.tps)} unit="TPS" accent={activity.active ? "codex" : "idle"} className="machine-tps-primary" />
        </div>
        <div className="device-machine-secondary">
          <DeviceStat label="5 MIN" value={formatTps(selected.fiveMinutes.tps)} unit="TPS" />
          <DeviceStat label="CACHE" value={selected.cachePercent || 0} unit="%" />
          <DeviceStat label="SESSIONS" value={selected.activeSessions} />
        </div>
      </div>
      <MachineTrendChart values={selected.tpsHistory?.map((sample) => sample.tps) || []} />
    </section>
  );
}

function PetView({ machines, selected, followMode, onFollowMode, onSelect }) {
  if (!selected) return <section className="pet-view"><EmptyState /></section>;
  const pet = selected.pet;
  const spriteUrl = resolvePetSpriteUrl(pet);
  const petState = pet?.state || "idle";
  return (
    <section className={`pet-view pet-state-${petState} ${pet ? "" : "pet-unconfigured"}`}>
      <div className="pet-stage">
        {pet && spriteUrl ? (
          <>
            <PetSprite
              key={petSpriteKey(selected, pet)}
              pet={pet}
              machineName={selected.machineName}
              spriteUrl={spriteUrl}
            />
            <div className="pet-identity">
              <strong>{pet.displayName}</strong>
              <span>{PET_STATE_LABELS[pet.state] || pet.state.toUpperCase()}</span>
            </div>
            <div className="pet-trend" aria-hidden="true">
              <MachineTrendChart values={selected.tpsHistory?.map((sample) => sample.tps) || []} emptyLabel={false} />
            </div>
          </>
        ) : pet ? (
          <div className="pet-empty">
            <Bird size={58} />
            <strong>Syncing pet</strong>
            <span>{selected.machineName}</span>
          </div>
        ) : (
          <div className="pet-empty">
            <Bird size={58} />
            <strong>No pet configured</strong>
            <span>{selected.machineName}</span>
          </div>
        )}
      </div>
      <div className="pet-metrics">
        <div className="pet-primary-metric">
          <span>1 MINUTE</span>
          <div><strong>{formatTps(selected.oneMinute.tps)}</strong><small>TPS</small></div>
        </div>
        <div className="pet-secondary-metrics">
          <PetTokenStat
            label="INPUT"
            value={formatTps(selected.oneMinute.inputTokens / 60)}
            unit="TPS"
            detail={`CACHE ${selected.cachePercent || 0}%`}
          />
          <PetTokenStat
            label="OUTPUT"
            value={formatTps(selected.oneMinute.outputTokens / 60)}
            unit="TPS"
            detail={`REASON ${formatTps(selected.oneMinute.reasoningOutputTokens / 60)} TPS`}
          />
          <PetTokenStat label="SESSIONS" value={selected.activeSessions} />
        </div>
        <div className={`pet-host-status ${machines.length > 1 ? "has-machine-picker" : ""}`}>
          <PetMachineControl
            machines={machines}
            selected={selected}
            followMode={followMode}
            onFollowMode={onFollowMode}
            onSelect={onSelect}
          />
          <StatusLabel status={selected.status} age={selected.ageSeconds} />
          <span>{selected.platform} · {formatAge(selected.generatedAt)}</span>
        </div>
      </div>
    </section>
  );
}

function PetTokenStat({ label, value, unit, detail }) {
  return (
    <div className="pet-token-stat">
      <div className="pet-token-label">
        <span>{label}</span>
        {detail ? <small>{detail}</small> : null}
      </div>
      <div className="pet-token-value">
        <strong>{value}</strong>
        {unit ? <small>{unit}</small> : null}
      </div>
    </div>
  );
}

function PetMachineControl({ machines, selected, followMode, onFollowMode, onSelect, ariaLabel = "Pet host" }) {
  if (machines.length <= 1) {
    return (
      <div className="pet-machine-label">
        <i className={selected.status} />
        <strong>{selected.machineName}</strong>
      </div>
    );
  }
  const auto = followMode === "auto";
  return (
    <div className="pet-machine-control">
      <button
        type="button"
        className={auto ? "active" : ""}
        onClick={() => onFollowMode(auto ? "fixed" : "auto")}
        aria-label={auto ? "Fix selected machine" : "Automatically follow active machine"}
        title={auto ? "Auto follow" : "Fixed machine"}
      >
        {auto ? <Radio size={19} /> : <Pin size={19} />}
      </button>
      <label>
        <select
          aria-label={ariaLabel}
          value={selected.machineId}
          onChange={(event) => onSelect(event.target.value)}
        >
          {machines.map((machine) => (
            <option key={machine.machineId} value={machine.machineId}>
              {machine.machineName}
            </option>
          ))}
        </select>
        <ChevronDown size={17} />
      </label>
    </div>
  );
}

function PetSprite({ pet, machineName, spriteUrl }) {
  const frameRef = useRef(null);
  const [transientState, setTransientState] = useState(null);
  const prefersReducedMotion = usePrefersReducedMotion();
  const animationState = transientState || pet.state;
  const animation = petAnimationForState(animationState);
  const spriteGrid = petSpriteGrid(pet);
  const reduceMotion = shouldReducePetMotion(navigator.userAgent, prefersReducedMotion);

  useEffect(() => {
    const frameElement = frameRef.current;
    if (!frameElement) return undefined;

    const playback = petPlaybackForState(animationState, reduceMotion);
    const startedAt = window.performance.now();
    let animationFrame = null;
    let paintedFrameIndex = -1;
    const paintFrame = (timestamp) => {
      const frameIndex = petFrameAtElapsed(playback, timestamp - startedAt);
      if (frameIndex !== paintedFrameIndex) {
        frameElement.style.backgroundPosition = petFramePosition(
          playback.frames[frameIndex],
          pet,
        );
        paintedFrameIndex = frameIndex;
      }
      if (playback.loopStartIndex !== null && playback.frames.length > 1) {
        animationFrame = window.requestAnimationFrame(paintFrame);
      }
    };

    paintFrame(startedAt);
    return () => {
      if (animationFrame !== null) window.cancelAnimationFrame(animationFrame);
    };
  }, [animationState, pet.spriteVersionNumber, reduceMotion]);

  const onPointerEnter = (event) => {
    if (event.pointerType === "mouse") setTransientState("jumping");
  };
  const onPointerLeave = (event) => {
    if (event.pointerType === "mouse") setTransientState(null);
  };

  return (
    <div
      className={`pet-sprite ${pet.state}`}
      role="img"
      aria-label={`${pet.displayName} on ${machineName}, ${PET_STATE_LABELS[pet.state] || pet.state}`}
      data-pet-animation={animation.name}
      onPointerEnter={onPointerEnter}
      onPointerLeave={onPointerLeave}
    >
      <div
        ref={frameRef}
        className="pet-sprite-frame"
        aria-hidden="true"
        style={{
          backgroundImage: `url(${spriteUrl})`,
          backgroundSize: spriteGrid.backgroundSize,
        }}
      />
    </div>
  );
}

function usePrefersReducedMotion() {
  const query = "(prefers-reduced-motion: reduce)";
  const [preferred, setPreferred] = useState(
    () => typeof matchMedia === "function" && matchMedia(query).matches,
  );

  useEffect(() => {
    if (typeof matchMedia !== "function") return undefined;
    const mediaQuery = matchMedia(query);
    const onChange = (event) => setPreferred(event.matches);
    mediaQuery.addEventListener("change", onChange);
    return () => mediaQuery.removeEventListener("change", onChange);
  }, []);

  return preferred;
}

function MachineTrendChart({ values = [], emptyLabel = true }) {
  const fillId = useId().replace(/:/g, "");
  const hasActivity = values.some((value) => Number(value) > 0.005);
  if (!hasActivity) {
    return (
      <div className={`machine-trend-empty ${emptyLabel ? "" : "compact"}`} role="img" aria-label="No machine activity in the last five minutes">
        {emptyLabel ? <span>NO ACTIVITY · 5 MIN</span> : null}
        <svg viewBox="0 0 1000 100" preserveAspectRatio="none" aria-hidden="true">
          <line x1="0" y1="72" x2="1000" y2="72" />
          <circle cx="998" cy="72" r="3" />
        </svg>
      </div>
    );
  }
  const max = Math.max(1, ...values);
  const points = linePoints(values, max, 1000, 100);
  return (
    <svg className="machine-trend-chart" viewBox="0 0 1000 100" preserveAspectRatio="none" role="img" aria-label="Recent machine TPS trend">
      <defs>
        <linearGradient id={`${fillId}-machine-fill`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#25d06f" stopOpacity=".26" />
          <stop offset="1" stopColor="#25d06f" stopOpacity=".03" />
        </linearGradient>
      </defs>
      <g className="machine-trend-grid"><line x1="0" y1="25" x2="1000" y2="25" /><line x1="0" y1="50" x2="1000" y2="50" /><line x1="0" y1="75" x2="1000" y2="75" /></g>
      <polygon fill={`url(#${fillId}-machine-fill)`} points={`0,100 ${points} 1000,100`} />
      <polyline points={points} />
    </svg>
  );
}

function MachineDetail({ machine }) {
  const Icon = machineIcon(machine.platform);
  const cachePercent = machine.cachePercent || 0;
  return (
    <>
      <div className="machine-detail-header">
        <Icon size={38} />
        <div><h2>{machine.machineName}</h2><span>{machine.platform} · {formatAge(machine.generatedAt)}</span></div>
        <StatusLabel status={machine.status} />
      </div>
      <div className="detail-metrics">
        <Metric label="1 minute" value={formatTps(machine.oneMinute.tps)} unit="TPS" accent="green" />
        <Metric label="5 minutes" value={formatTps(machine.fiveMinutes.tps)} unit="TPS" />
        <Metric label="Cache" value={cachePercent} unit="%" />
        <Metric label="Sessions" value={machine.activeSessions} />
      </div>
      <div className="token-breakdown">
        <TokenBar label="Input" value={machine.oneMinute.inputTokens} max={machine.oneMinute.inputTokens} color="blue" />
        <TokenBar label="Cached" value={machine.oneMinute.cachedInputTokens} max={machine.oneMinute.inputTokens} color="green" />
        <TokenBar label="Output" value={machine.oneMinute.outputTokens} max={machine.oneMinute.inputTokens} color="violet" />
        <TokenBar label="Reasoning" value={machine.oneMinute.reasoningOutputTokens} max={machine.oneMinute.inputTokens} color="amber" />
      </div>
      <Sparkline values={machine.tpsHistory?.map((sample) => sample.tps) || []} color="green" />
      {machine.error ? <div className="machine-error">{machine.error}</div> : null}
    </>
  );
}

function ThroughputSummary({ network, large = false }) {
  return (
    <div className={`throughput-summary ${large ? "large" : ""}`}>
      <Metric label="Download" value={formatMetric(network.downloadMbps)} unit="Mbps" accent="blue" />
      <div className="metric-separator" />
      <Metric label="Upload" value={formatMetric(network.uploadMbps)} unit="Mbps" accent="green" />
    </div>
  );
}

function CodexSummary({ codex }) {
  return (
    <div className="codex-summary">
      <Metric label="1 min" value={formatTps(codex.oneMinuteTps)} unit="TPS" accent="green" />
      <Metric label="5 min" value={formatTps(codex.fiveMinuteTps)} unit="TPS" accent="green" />
      <Metric label="Cache" value={codex.cachePercent} unit="%" accent="green" />
      <Metric label="Sessions" value={codex.activeSessions} accent="green" />
    </div>
  );
}

function MachineList({ machines, onMachine, selectedId, expanded = false }) {
  if (machines.length === 0) return <EmptyState />;
  return (
    <div className={`machine-list ${expanded ? "expanded" : ""}`}>
      {machines.map((machine) => {
        const Icon = machineIcon(machine.platform);
        return (
          <button className={`machine-row ${selectedId === machine.machineId ? "selected" : ""}`} key={machine.machineId} onClick={() => onMachine(machine.machineId)}>
            <Icon className="machine-icon" size={expanded ? 30 : 28} />
            <div className="machine-identity"><strong>{machine.machineName}</strong>{expanded ? <span>{machine.platform} · {formatAge(machine.generatedAt)}</span> : null}</div>
            <span className="machine-tps">{formatTps(machine.oneMinute.tps)} TPS</span>
            <Sparkline values={machine.tpsHistory?.map((sample) => sample.tps) || []} color="green" mini />
            <StatusLabel status={machine.status} age={machine.ageSeconds} compact />
            <ChevronRight className="row-chevron" size={22} />
          </button>
        );
      })}
    </div>
  );
}

function Panel({ title, icon: Icon, action, className = "", children }) {
  return (
    <section className={`panel ${className}`}>
      <div className="panel-header"><div><Icon size={25} /><h2>{title}</h2></div>{action}</div>
      <div className="panel-body">{children}</div>
    </section>
  );
}

function Metric({ label, value, unit, accent }) {
  return (
    <div className={`metric ${accent || ""}`}>
      <span className="metric-label">{label}</span>
      <div><strong>{value}</strong>{unit ? <span>{unit}</span> : null}</div>
    </div>
  );
}

function Fact({ label, value, accent = "" }) {
  return <div className="fact"><span>{label}</span><strong className={accent}>{value}</strong></div>;
}

function TokenBar({ label, value, max, color }) {
  const percent = max ? Math.max(3, Math.min(100, (value / max) * 100)) : 3;
  return (
    <div className="token-bar">
      <div><span>{label}</span><strong>{formatCompact(value)}</strong></div>
      <i><b className={color} style={{ width: `${percent}%` }} /></i>
    </div>
  );
}

function TrafficChart({ points = [], detailed = false, allowSampleData = false }) {
  const chartId = useId().replace(/:/g, "");
  const downloadFillId = `${chartId}-download-fill`;
  const uploadFillId = `${chartId}-upload-fill`;
  const data = trafficData(points, allowSampleData);
  if (data.length === 0) {
    return <div className={`traffic-chart chart-empty ${detailed ? "detailed" : ""}`}><Activity size={32} /><strong>Waiting for WAN samples</strong><span>The last known values will appear here when the gateway reports data.</span></div>;
  }
  const downloadValues = smoothTrafficValues(data.map((point) => point.downloadMbps || 0));
  const uploadValues = smoothTrafficValues(data.map((point) => point.uploadMbps || 0));
  const max = trafficScale([downloadValues, uploadValues]);
  const download = smoothTrafficPath(downloadValues, max);
  const upload = smoothTrafficPath(uploadValues, max);
  const lastDownloadY = scaledTrafficY(downloadValues.at(-1), max, 300);
  const lastUploadY = scaledTrafficY(uploadValues.at(-1), max, 300);
  const windowSeconds = historyWindowSeconds(data);
  return (
    <div className={`traffic-chart ${detailed ? "detailed" : ""}`}>
      <div className="axis-labels"><span>{Math.ceil(max)}</span><span>{Math.ceil(max / 2)}</span><span>0</span></div>
      <svg viewBox="0 0 1000 300" preserveAspectRatio="none" role="img" aria-label="WAN throughput chart">
        <defs>
          <linearGradient id={downloadFillId} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#2d8cff" stopOpacity=".2" /><stop offset="1" stopColor="#2d8cff" stopOpacity="0" /></linearGradient>
          <linearGradient id={uploadFillId} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#38d891" stopOpacity=".18" /><stop offset="1" stopColor="#38d891" stopOpacity="0" /></linearGradient>
        </defs>
        <g className="grid-lines"><line x1="0" y1="0" x2="1000" y2="0" /><line x1="0" y1="150" x2="1000" y2="150" /><line x1="0" y1="299" x2="1000" y2="299" />{[0, 200, 400, 600, 800, 1000].map((x) => <line key={x} x1={x} y1="0" x2={x} y2="300" />)}</g>
        <path className="download-fill" fill={`url(#${downloadFillId})`} d={`${download} L 1000 300 L 0 300 Z`} />
        <path className="upload-fill" fill={`url(#${uploadFillId})`} d={`${upload} L 1000 300 L 0 300 Z`} />
        <path className="download-line" d={download} />
        <path className="upload-line" d={upload} />
        <line className="traffic-cursor" x1="998" y1="0" x2="998" y2="300" />
        <circle className="traffic-dot download" cx="998" cy={lastDownloadY} r="5" />
        <circle className="traffic-dot upload" cx="998" cy={lastUploadY} r="4" />
      </svg>
      <div className="time-labels"><span>-{windowSeconds}s</span><span>-{Math.round(windowSeconds / 2)}s</span><span>0s</span></div>
    </div>
  );
}

function Sparkline({ values, color, mini = false, compact = false }) {
  const data = values.length > 1 ? values : [0, 0];
  const max = Math.max(...data, 1);
  const points = linePoints(data, max, 200, 50);
  return (
    <svg className={`sparkline ${mini ? "mini" : ""} ${compact ? "compact" : ""}`} viewBox="0 0 200 50" preserveAspectRatio="none" aria-hidden="true">
      <polyline className={color} points={points} />
    </svg>
  );
}

function linePoints(values, max, width = 1000, height = 300) {
  return values.map((value, index) => {
    const x = values.length === 1 ? 0 : index * width / (values.length - 1);
    const y = height - Math.min(height, Math.max(0, value / max * height * 0.92));
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(" ");
}

function trafficData(points, allowSampleData) {
  if (points.length > 1) return points;
  if (!allowSampleData) return [];
  return Array.from({ length: 60 }, (_, index) => ({
    downloadMbps: 700 + Math.sin(index / 5) * 80,
    uploadMbps: 115 + Math.cos(index / 7) * 16,
  }));
}

function historyWindowSeconds(points = []) {
  if (points.length > 1) {
    const first = new Date(points[0].at).valueOf();
    const last = new Date(points.at(-1).at).valueOf();
    if (Number.isFinite(first) && Number.isFinite(last) && last > first) {
      return Math.max(1, Math.round((last - first) / 1000));
    }
  }
  return Math.max(1, points.length - 1);
}

function networkUnavailableLabel(network) {
  return !network.source || network.source === "unconfigured" || network.status === "error" ? "N/A" : "WAIT";
}

function networkClientsMetric(network) {
  if (network.clients !== null && network.clients !== undefined && Number.isFinite(Number(network.clients))) {
    return { value: Math.max(0, Math.round(Number(network.clients))) };
  }
  return { value: networkUnavailableLabel(network) };
}

function networkLatencyMetric(network) {
  if (network.latencyMs === null || network.latencyMs === undefined || !Number.isFinite(Number(network.latencyMs))) {
    return { value: networkUnavailableLabel(network), unit: "", accent: "" };
  }
  const value = Math.max(0, Number(network.latencyMs));
  const accent = value < 30 ? "green" : value < 80 ? "amber" : "red";
  return { value: value.toFixed(2), unit: "ms", accent };
}

function machineActivity(machine) {
  const currentTps = Number(machine.oneMinute?.tps || 0);
  if (currentTps > 0.005) return { active: true, label: "WORKING", detail: machine.platform };

  const history = Array.isArray(machine.tpsHistory) ? machine.tpsHistory : [];
  const latestAt = new Date(history.at(-1)?.at || machine.generatedAt).valueOf();
  let lastActive = null;
  for (let index = history.length - 1; index >= 0; index -= 1) {
    const sample = history[index];
    if (Number(sample.tps) > 0.005 && Number.isFinite(new Date(sample.at).valueOf())) {
      lastActive = sample;
      break;
    }
  }
  if (lastActive && Number.isFinite(latestAt)) {
    const ageSeconds = Math.max(0, Math.round((latestAt - new Date(lastActive.at).valueOf()) / 1000));
    return { active: false, label: "IDLE", detail: `LAST ${formatDuration(ageSeconds).toUpperCase()} AGO` };
  }
  if (Number(machine.fiveMinutes?.tps || 0) > 0.005) {
    return { active: false, label: "IDLE", detail: "ACTIVE <5M" };
  }
  return { active: false, label: "IDLE", detail: "5M NO ACTIVITY" };
}

function BottomNav({ view, setView, status, connection }) {
  const items = [
    ["overview", LayoutDashboard],
    ["network", Globe2],
    ["machines", Monitor],
    ["load", Gauge],
    ["pet", Bird],
  ];
  const displayStatus = connection === "live" ? status.overallStatus : "stale";
  const showFreshness = displayStatus !== "live";
  return (
    <nav className={`bottom-nav ${showFreshness ? "has-alert" : ""}`}>
      <div className="nav-tabs">
        {items.map(([id, Icon]) => (
          <button
            key={id}
            aria-label={VIEW_LABELS[id]}
            aria-current={view === id ? "page" : undefined}
            className={view === id ? "active" : ""}
            onClick={() => setView(id)}
          >
            <Icon size={24} />
            <span>{VIEW_LABELS[id]}</span>
          </button>
        ))}
      </div>
      {showFreshness ? <div className="freshness"><span>Data freshness</span><StatusLabel status={displayStatus} /><span className="divider" /><span>Updated: {formatAge(status.generatedAt, true)}</span></div> : null}
    </nav>
  );
}

function FullscreenButton() {
  if (navigator.userAgent.includes("AmbientOpsKiosk/")) return null;
  const enter = async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await document.documentElement.requestFullscreen({ navigationUI: "hide" });
    } catch { /* Chrome kiosk and immersive mode can already be fullscreen. */ }
  };
  return <button className="icon-button" onClick={enter} title="全屏"><Expand size={20} /></button>;
}

function StatusLabel({ status = "error", compact = false, age }) {
  const label = status === "live" ? "LIVE" : status === "stale" ? "STALE" : "ERROR";
  return (
    <span className={`status-label ${status} ${compact ? "compact" : ""}`}>
      <i /> <span>{label}</span>{age && status !== "live" ? <small>{formatDuration(age)}</small> : null}
    </span>
  );
}

function Legend({ color, label }) {
  return <span className="legend"><i className={color} />{label}</span>;
}

function EmptyState() {
  return <div className="empty-state"><WifiOff size={38} /><strong>No agents</strong><span>Waiting for machine snapshots</span></div>;
}

function EinkDisplay({ status, connection }) {
  const now = useClock(30_000);
  return (
    <main className="eink-display">
      <header><div><h1>{(status.site?.name || "Ambient Ops").toUpperCase()}</h1><time>{formatTime(now, status.site?.timeZone)}</time></div><StatusLabel status={connection === "live" ? status.overallStatus : "stale"} /></header>
      <section className="eink-network">
        <h2>INTERNET</h2>
        <Metric label="DOWNLOAD" value={formatMetric(status.network.downloadMbps)} unit="Mbps" />
        <Metric label="UPLOAD" value={formatMetric(status.network.uploadMbps)} unit="Mbps" />
      </section>
      <section className="eink-codex">
        <h2>CODEX</h2>
        <Metric label="1 MINUTE" value={formatTps(status.codex.oneMinuteTps)} unit="TPS" />
        <Metric label="ACTIVE" value={status.codex.activeSessions} unit="SESSIONS" />
      </section>
      <footer><span>{status.machines.length} MACHINES</span><span>UPDATED {formatAge(status.generatedAt, true).toUpperCase()}</span></footer>
    </main>
  );
}

function useClock(interval = 1000) {
  const [now, setNow] = useState(new Date());
  useEffect(() => { const timer = setInterval(() => setNow(new Date()), interval); return () => clearInterval(timer); }, [interval]);
  return now;
}

function mergeStatusHistory(previous, next) {
  const previousMachines = new Map((previous?.machines || []).map((machine) => [machine.machineId, machine]));
  const machines = (next.machines || []).map((machine) => {
    const prior = previousMachines.get(machine.machineId);
    const sample = { at: machine.generatedAt, tps: Number(machine.oneMinute?.tps || 0) };
    return { ...machine, tpsHistory: appendHistorySample(prior?.tpsHistory, sample) };
  });
  const codexHistory = appendHistorySample(previous?.codex?.tpsHistory, {
    at: next.generatedAt,
    tps: Number(next.codex?.oneMinuteTps || 0),
  });
  return {
    ...next,
    codex: { ...next.codex, tpsHistory: codexHistory },
    machines,
  };
}

function hostFreshness(machine) {
  if (machine?.status === "error") return "OFFLINE";
  if (machine?.status === "stale") return `STALE ${formatDuration(machine.ageSeconds || 0).toUpperCase()}`;
  return Number(machine?.ageSeconds || 0) < 5 ? "NOW" : formatDuration(machine.ageSeconds).toUpperCase();
}

function machineIcon(platform = "") {
  const lower = platform.toLowerCase();
  if (lower.includes("server") || lower.includes("linux")) return Server;
  if (lower.includes("windows")) return Monitor;
  return Laptop;
}

function formatMetric(value) {
  return Number.isFinite(Number(value)) ? Number(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "--";
}

function formatScale(value) {
  return Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: Number(value) < 10 ? 1 : 0 });
}

function metricDensity(value) {
  const length = String(value ?? "").replace(/\s/g, "").length;
  if (length >= 9) return "tight";
  if (length >= 7) return "compact";
  return "normal";
}

function formatTps(value) {
  return Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: Number(value) >= 100 ? 0 : 1 });
}

function formatCompact(value) {
  return Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(value || 0);
}

function formatTime(date, timeZone) {
  return new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone }).format(date);
}

function formatAge(value, short = false) {
  if (!value) return "never";
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).valueOf()) / 1000));
  if (seconds < 5) return short ? "now" : "Just now";
  return `${formatDuration(seconds)} ago`;
}

function formatDuration(seconds) {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  return `${Math.round(seconds / 3600)}h`;
}
