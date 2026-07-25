export function renderPrometheus(dashboard) {
  const lines = [
    "# HELP ambient_ops_network_download_megabits_per_second Current WAN download throughput.",
    "# TYPE ambient_ops_network_download_megabits_per_second gauge",
    `ambient_ops_network_download_megabits_per_second ${number(dashboard.network.downloadMbps)}`,
    "# HELP ambient_ops_network_upload_megabits_per_second Current WAN upload throughput.",
    "# TYPE ambient_ops_network_upload_megabits_per_second gauge",
    `ambient_ops_network_upload_megabits_per_second ${number(dashboard.network.uploadMbps)}`,
    "# HELP ambient_ops_codex_tokens_per_second Aggregated Codex token throughput.",
    "# TYPE ambient_ops_codex_tokens_per_second gauge",
    `ambient_ops_codex_tokens_per_second{window="1m"} ${number(dashboard.codex.oneMinuteTps)}`,
    `ambient_ops_codex_tokens_per_second{window="5m"} ${number(dashboard.codex.fiveMinuteTps)}`,
    "# HELP ambient_ops_codex_active_sessions Aggregated active Codex sessions.",
    "# TYPE ambient_ops_codex_active_sessions gauge",
    `ambient_ops_codex_active_sessions ${number(dashboard.codex.activeSessions)}`,
    "# HELP ambient_ops_machine_freshness_seconds Age of the last machine snapshot.",
    "# TYPE ambient_ops_machine_freshness_seconds gauge",
    "# HELP ambient_ops_machine_codex_tokens_per_second Per-machine Codex throughput.",
    "# TYPE ambient_ops_machine_codex_tokens_per_second gauge",
    "# HELP ambient_ops_machine_live Machine is inside the live freshness window.",
    "# TYPE ambient_ops_machine_live gauge",
  ];
  for (const machine of dashboard.machines) {
    const labels = `machine_id="${escapeLabel(machine.machineId)}",machine_name="${escapeLabel(machine.machineName)}",platform="${escapeLabel(machine.platform)}"`;
    lines.push(`ambient_ops_machine_freshness_seconds{${labels}} ${number(machine.ageSeconds)}`);
    lines.push(`ambient_ops_machine_codex_tokens_per_second{${labels},window="1m"} ${number(machine.oneMinute.tps)}`);
    lines.push(`ambient_ops_machine_codex_tokens_per_second{${labels},window="5m"} ${number(machine.fiveMinutes.tps)}`);
    lines.push(`ambient_ops_machine_live{${labels},status="${escapeLabel(machine.status)}"} ${machine.status === "live" ? 1 : 0}`);
  }
  return `${lines.join("\n")}\n`;
}

function number(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function escapeLabel(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/"/g, '\\"');
}
