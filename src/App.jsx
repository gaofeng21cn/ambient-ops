import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import {
  Activity,
  Bird,
  Bot,
  ChevronDown,
  ChevronRight,
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
  WifiOff,
} from "lucide-react";
import {
  scaledTrafficY,
  smoothTrafficPath,
  smoothTrafficValues,
  trafficScale,
} from "./traffic-chart.mjs";
import {
  petSpriteGrid,
  petSpriteKey,
  resolvePetSpriteUrl,
  selectDisplayMachine,
} from "./pet-display.mjs";

const VIEWS = ["overview", "network", "machines", "pet"];
const VIEW_LABELS = { overview: "Overview", network: "Network", machines: "Machines", pet: "Pet" };
const PET_ANIMATIONS = {
  idle: { row: 0, frames: 6, interval: 620 },
  failed: { row: 5, frames: 8, interval: 480 },
  waiting: { row: 6, frames: 6, interval: 420 },
  running: { row: 7, frames: 6, interval: 180 },
  review: { row: 8, frames: 6, interval: 320 },
};
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
  codex: { status: "error", oneMinuteTps: 0, fiveMinuteTps: 0, cachePercent: 0, activeSessions: 0, machineCount: 0 },
  machines: [],
};

export function App() {
  const eink = location.pathname.startsWith("/display/eink");
  const [status, connection] = useStatus();
  if (eink) return <EinkDisplay status={status} connection={connection} />;
  return <Dashboard status={status} connection={connection} />;
}

function useStatus() {
  const cached = useMemo(() => {
    try { return JSON.parse(localStorage.getItem("home-status-last") || "null"); } catch { return null; }
  }, []);
  const [status, setStatus] = useState(cached || EMPTY_STATUS);
  const [connection, setConnection] = useState(cached ? "stale" : "loading");

  useEffect(() => {
    let stopped = false;
    let timer;
    const refresh = async () => {
      try {
        const response = await fetch("/api/status", { cache: "no-store", signal: AbortSignal.timeout(4000) });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const next = await response.json();
        if (stopped) return;
        setStatus((current) => {
          const merged = mergeStatusHistory(current, next);
          localStorage.setItem("home-status-last", JSON.stringify(merged));
          return merged;
        });
        setConnection("live");
      } catch {
        if (!stopped) setConnection("stale");
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
        <DeviceStat label="5 MIN" value={formatTps(status.codex.fiveMinuteTps)} unit="TPS" />
        <DeviceStat label="CACHE" value={status.codex.cachePercent} unit="%" />
        <DeviceStat label="LIVE" value={`${liveMachines}/${status.machines.length}`} accent={liveMachines === status.machines.length ? "green" : "amber"} />
      </div>
    </section>
  );
}

function DeviceMetric({ label, value, unit, accent, className = "" }) {
  return (
    <div className={`device-metric ${accent || ""} ${className}`}>
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
  const glowId = `${chartId}-airview-glow`;
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
    <svg className="airview-chart" viewBox="0 0 1000 100" preserveAspectRatio="none" role="img" aria-label="Live WAN throughput">
      <defs>
        <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#38bdf8" stopOpacity=".24" /><stop offset="1" stopColor="#38bdf8" stopOpacity=".04" /></linearGradient>
        <filter id={glowId} x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="2.5" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
      </defs>
      <g className="airview-grid"><line x1="0" y1="25" x2="1000" y2="25" /><line x1="0" y1="50" x2="1000" y2="50" /><line x1="0" y1="75" x2="1000" y2="75" /></g>
      <line className="airview-baseline" x1="0" y1="99" x2="1000" y2="99" />
      <path className="airview-fill" fill={`url(#${fillId})`} d={`${download} L 1000 100 L 0 100 Z`} />
      <path className="airview-download" d={download} />
      <path className="airview-upload" d={upload} />
      <line className="airview-cursor" x1="998" y1="0" x2="998" y2="100" />
      <g className="airview-live-edge" filter={`url(#${glowId})`}>
        <circle className="airview-halo download" cx="998" cy={lastDownloadY} r="7" />
        <circle className="airview-dot download" cx="998" cy={lastDownloadY} r="3.2" />
        <circle className="airview-halo upload" cx="998" cy={lastUploadY} r="5.5" />
        <circle className="airview-dot upload" cx="998" cy={lastUploadY} r="2.5" />
      </g>
    </svg>
  );
}

function NetworkView({ network }) {
  return (
    <>
      <DeviceNetworkView network={network} />
      <div className="network-view">
        <section className="network-hero">
          <div className="section-heading"><Globe2 size={26} /><h2>Internet</h2><StatusLabel status={network.status} /></div>
          <ThroughputSummary network={network} large />
          <div className="network-facts">
            <Fact label="Connected clients" value={network.clients ?? "--"} />
            <Fact label="Gateway latency" value={network.latencyMs == null ? "--" : `${network.latencyMs} ms`} />
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
  return (
    <section className="device-network-view">
      <div className="device-network-metrics">
        <DeviceMetric label="Download" value={formatMetric(network.downloadMbps)} unit="Mbps" accent="download" />
        <DeviceMetric label="Upload" value={formatMetric(network.uploadMbps)} unit="Mbps" accent="upload" />
      </div>
      <section className="device-airview network-airview"><AirViewChart points={network.history} allowSampleData={network.source === "demo"} /></section>
      <div className="device-summary-grid network-summary">
        <DeviceStat label="CLIENTS" value={network.clients ?? "--"} />
        <DeviceStat label="LATENCY" value={network.latencyMs ?? "--"} unit="ms" />
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
  return (
    <section className="device-machines-view">
      <div className="device-machine-tabs">
        {machines.map((machine) => <button className={selected.machineId === machine.machineId ? "selected" : ""} key={machine.machineId} onClick={() => onSelect(machine.machineId)}><i className={machine.status} />{machine.machineName}</button>)}
      </div>
      <div className="device-machine-body">
        <div className="device-machine-primary">
          <span>1 MIN · {selected.platform}</span>
          <DeviceMetric label="1 min" value={formatTps(selected.oneMinute.tps)} unit="TPS" accent="codex" className="machine-tps-primary" />
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
  return (
    <section className={`pet-view ${pet ? "" : "pet-unconfigured"}`}>
      <div className="pet-stage">
        <PetMachineControl
          machines={machines}
          selected={selected}
          followMode={followMode}
          onFollowMode={onFollowMode}
          onSelect={onSelect}
        />
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
              <MachineTrendChart values={selected.tpsHistory?.map((sample) => sample.tps) || []} />
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
        <div className="pet-host-status">
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

function PetMachineControl({ machines, selected, followMode, onFollowMode, onSelect }) {
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
          aria-label="Pet host"
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
  const animation = PET_ANIMATIONS[pet.state] || PET_ANIMATIONS.idle;
  const spriteGrid = petSpriteGrid(pet);
  const reduceMotion = useMemo(
    () => window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false,
    [],
  );
  const [frame, setFrame] = useState(0);
  useEffect(() => {
    setFrame(0);
    if (reduceMotion) return undefined;
    const timer = setInterval(() => {
      setFrame((current) => (current + 1) % animation.frames);
    }, animation.interval);
    return () => clearInterval(timer);
  }, [animation.frames, animation.interval, pet.state, reduceMotion]);
  return (
    <div
      className={`pet-sprite ${pet.state}`}
      role="img"
      aria-label={`${pet.displayName} on ${machineName}, ${PET_STATE_LABELS[pet.state] || pet.state}`}
      style={{
        backgroundImage: `url(${spriteUrl})`,
        backgroundPosition: `${frame * 100 / 7}% ${spriteGrid.rowPosition(animation.row)}`,
        backgroundSize: spriteGrid.backgroundSize,
      }}
    />
  );
}

function MachineTrendChart({ values = [] }) {
  const fillId = useId().replace(/:/g, "");
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

function Fact({ label, value }) {
  return <div className="fact"><span>{label}</span><strong>{value}</strong></div>;
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

function BottomNav({ view, setView, status, connection }) {
  const items = [
    ["overview", LayoutDashboard],
    ["network", Globe2],
    ["machines", Monitor],
    ["pet", Bird],
  ];
  return (
    <nav className="bottom-nav">
      <div className="nav-tabs">
        {items.map(([id, Icon]) => <button key={id} aria-label={VIEW_LABELS[id]} className={view === id ? "active" : ""} onClick={() => setView(id)}><Icon size={24} /><span>{VIEW_LABELS[id]}</span></button>)}
      </div>
      <div className="freshness"><span>Data freshness</span><StatusLabel status={connection === "live" ? status.overallStatus : "stale"} /><span className="divider" /><span>Updated: {formatAge(status.generatedAt, true)}</span></div>
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
    const history = Array.isArray(prior?.tpsHistory) ? [...prior.tpsHistory] : [];
    const sample = { at: machine.generatedAt, tps: Number(machine.oneMinute?.tps || 0) };
    if (!history.length || history.at(-1).at !== sample.at) history.push(sample);
    return { ...machine, tpsHistory: history.slice(-60) };
  });
  const codexHistory = Array.isArray(previous?.codex?.tpsHistory)
    ? [...previous.codex.tpsHistory]
    : [];
  codexHistory.push({ at: next.generatedAt, tps: Number(next.codex?.oneMinuteTps || 0) });
  return {
    ...next,
    codex: { ...next.codex, tpsHistory: codexHistory.slice(-120) },
    machines,
  };
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
