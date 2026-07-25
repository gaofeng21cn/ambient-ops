import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Activity,
  Bot,
  ChevronRight,
  Expand,
  Gauge,
  Globe2,
  Laptop,
  LayoutDashboard,
  Monitor,
  Network,
  Server,
  WifiOff,
} from "lucide-react";

const VIEWS = ["overview", "network", "machines"];
const VIEW_LABELS = { overview: "Overview", network: "Network", machines: "Machines" };
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
        setStatus(next);
        setConnection("live");
        localStorage.setItem("home-status-last", JSON.stringify(next));
      } catch {
        if (!stopped) setConnection("stale");
      } finally {
        if (!stopped) timer = setTimeout(refresh, 2000);
      }
    };
    refresh();
    return () => { stopped = true; clearTimeout(timer); };
  }, []);

  return [status, connection];
}

function Dashboard({ status, connection }) {
  const [view, setView] = useState(initialView);
  const [selectedMachineId, setSelectedMachineId] = useState(status.machines[0]?.machineId || null);
  const pointerStart = useRef(null);
  const selectedMachine = status.machines.find((machine) => machine.machineId === selectedMachineId) || status.machines[0];

  useEffect(() => {
    const next = `/display/${view}`;
    if (location.pathname !== next) history.replaceState(null, "", next);
  }, [view]);

  const switchBy = useCallback((offset) => {
    setView((current) => VIEWS[(VIEWS.indexOf(current) + offset + VIEWS.length) % VIEWS.length]);
  }, []);

  const onPointerDown = (event) => {
    if (event.target.closest("button")) return;
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
    setView("machines");
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
            onSelect={setSelectedMachineId}
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
          <Sparkline values={status.machines.map((machine) => machine.oneMinute.tps)} color="green" compact />
        </Panel>
        <Panel className="machine-panel" title={`Machines (${status.machines.length})`} icon={Monitor} action={<button className="panel-link" type="button" onClick={onAllMachines}>All <ChevronRight size={20} /></button>}>
          <MachineList machines={status.machines} onMachine={onMachine} />
        </Panel>
      </div>
    </div>
  );
}

function NetworkView({ network }) {
  return (
    <div className="network-view">
      <section className="network-hero">
        <div className="section-heading"><Globe2 size={26} /><h2>Internet</h2><StatusLabel status={network.status} /></div>
        <ThroughputSummary network={network} large />
        <div className="network-facts">
          <Fact label="Connected clients" value={network.clients ?? "--"} />
          <Fact label="Gateway latency" value={network.latencyMs == null ? "--" : `${network.latencyMs} ms`} />
          <Fact label="Data source" value={network.source === "unifi" ? "UniFi Gateway" : network.source === "demo" ? "Demonstration" : "Unconfigured"} />
          <Fact label="Last update" value={formatAge(network.updatedAt)} />
        </div>
      </section>
      <section className="network-chart-wrap">
        <div className="section-heading"><Activity size={24} /><h2>WAN throughput</h2><span>Last {historyWindowSeconds(network.history)}s</span></div>
        <TrafficChart points={network.history} detailed allowSampleData={network.source === "demo"} />
        <div className="chart-legend"><Legend color="blue" label="Download" /><Legend color="green" label="Upload" /></div>
      </section>
    </div>
  );
}

function MachinesView({ machines, selected, onSelect }) {
  return (
    <div className="machines-view">
      <section className="machine-directory">
        <div className="section-heading"><Monitor size={26} /><h2>Machines</h2><span>{machines.length} agents</span></div>
        <MachineList machines={machines} onMachine={onSelect} selectedId={selected?.machineId} expanded />
      </section>
      <section className="machine-detail">
        {selected ? <MachineDetail machine={selected} /> : <EmptyState />}
      </section>
    </div>
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
      <Sparkline values={sparkValues(machine.oneMinute.tps)} color="green" />
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
            <Sparkline values={sparkValues(machine.oneMinute.tps)} color="green" mini />
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
  const data = points.length > 1 ? points : allowSampleData ? Array.from({ length: 60 }, (_, index) => ({
    downloadMbps: 700 + Math.sin(index / 5) * 80,
    uploadMbps: 115 + Math.cos(index / 7) * 16,
  })) : [];
  if (data.length === 0) {
    return <div className={`traffic-chart chart-empty ${detailed ? "detailed" : ""}`}><Activity size={32} /><strong>Waiting for WAN samples</strong><span>The last known values will appear here when the gateway reports data.</span></div>;
  }
  const max = Math.max(100, ...data.flatMap((point) => [point.downloadMbps || 0, point.uploadMbps || 0]));
  const download = linePoints(data.map((point) => point.downloadMbps || 0), max);
  const upload = linePoints(data.map((point) => point.uploadMbps || 0), max);
  const windowSeconds = historyWindowSeconds(data);
  return (
    <div className={`traffic-chart ${detailed ? "detailed" : ""}`}>
      <div className="axis-labels"><span>{Math.ceil(max)}</span><span>{Math.ceil(max / 2)}</span><span>0</span></div>
      <svg viewBox="0 0 1000 300" preserveAspectRatio="none" role="img" aria-label="WAN throughput chart">
        <defs>
          <linearGradient id="downloadFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#2d8cff" stopOpacity=".2" /><stop offset="1" stopColor="#2d8cff" stopOpacity="0" /></linearGradient>
          <linearGradient id="uploadFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#38d891" stopOpacity=".18" /><stop offset="1" stopColor="#38d891" stopOpacity="0" /></linearGradient>
        </defs>
        <g className="grid-lines"><line x1="0" y1="0" x2="1000" y2="0" /><line x1="0" y1="150" x2="1000" y2="150" /><line x1="0" y1="299" x2="1000" y2="299" />{[0, 200, 400, 600, 800, 1000].map((x) => <line key={x} x1={x} y1="0" x2={x} y2="300" />)}</g>
        <polygon className="download-fill" points={`0,300 ${download} 1000,300`} />
        <polygon className="upload-fill" points={`0,300 ${upload} 1000,300`} />
        <polyline className="download-line" points={download} />
        <polyline className="upload-line" points={upload} />
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

function historyWindowSeconds(points = []) {
  if (points.length > 1) {
    const first = new Date(points[0].at).valueOf();
    const last = new Date(points.at(-1).at).valueOf();
    if (Number.isFinite(first) && Number.isFinite(last) && last > first) {
      return Math.max(1, Math.round((last - first) / 1000));
    }
  }
  return Math.max(60, points.length * 3);
}

function BottomNav({ view, setView, status, connection }) {
  const items = [
    ["overview", LayoutDashboard],
    ["network", Globe2],
    ["machines", Monitor],
  ];
  return (
    <nav className="bottom-nav">
      <div className="nav-tabs">
        {items.map(([id, Icon]) => <button key={id} className={view === id ? "active" : ""} onClick={() => setView(id)}><Icon size={24} /><span>{VIEW_LABELS[id]}</span></button>)}
      </div>
      <div className="freshness"><span>Data freshness</span><StatusLabel status={connection === "live" ? status.overallStatus : "stale"} /><span className="divider" /><span>Updated: {formatAge(status.generatedAt, true)}</span></div>
    </nav>
  );
}

function FullscreenButton() {
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

function machineIcon(platform = "") {
  const lower = platform.toLowerCase();
  if (lower.includes("server") || lower.includes("linux")) return Server;
  if (lower.includes("windows")) return Monitor;
  return Laptop;
}

function sparkValues(center) {
  return Array.from({ length: 24 }, (_, index) => Math.max(0, center * (0.88 + Math.sin(index * 1.7 + center) * 0.06 + (index % 5) * 0.012)));
}

function formatMetric(value) {
  return Number.isFinite(Number(value)) ? Number(value).toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 }) : "--";
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
