import SwiftUI

struct MachinesView: View {
    @Bindable var store: AmbientOpsStore

    private var machines: [MachineStatus] {
        store.status.machines.sorted {
            let left = priority($0)
            let right = priority($1)
            if left != right { return left < right }
            return $0.loadVisualState.score > $1.loadVisualState.score
        }
    }

    var body: some View {
        NavigationStack {
            List(machines) { machine in
                NavigationLink {
                    MachineDetailView(machine: machine) {
                        store.selectMachine(machine.machineId)
                    }
                } label: {
                    MachineRow(machine: machine, isFocused: store.selectedMachine?.machineId == machine.machineId)
                }
                .listRowBackground(AmbientTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AmbientTheme.background)
            .navigationTitle("Machines")
            .overlay {
                if machines.isEmpty {
                    ContentUnavailableView(
                        "No machines",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text("No Codex hosts are reporting to this server.")
                    )
                }
            }
        }
    }

    private func priority(_ machine: MachineStatus) -> Int {
        switch machine.status {
        case "error": 0
        case "stale": 1
        default: machine.loadVisualState.state == "constrained" ? 2 : 3
        }
    }
}

private struct MachineRow: View {
    let machine: MachineStatus
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: machineIcon(machine.platform))
                .font(.title3)
                .foregroundStyle(AmbientTheme.statusColor(machine.status))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(machine.machineName)
                        .font(.headline)
                    if isFocused {
                        Image(systemName: "scope")
                            .font(.caption)
                            .foregroundStyle(AmbientTheme.green)
                            .accessibilityLabel("Focused machine")
                    }
                }
                Text("\(machine.platform) · \(secondaryState)")
                    .font(.caption)
                    .foregroundStyle(AmbientTheme.statusColor(
                        machine.status == "live" ? machine.loadVisualState.state : machine.status
                    ))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(MetricFormat.tps(machine.oneMinute.tps))
                    .font(.headline.monospacedDigit())
                Text("TPS")
                    .font(.caption2)
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
        .padding(.vertical, 6)
    }

    private var secondaryState: String {
        machine.status == "live"
            ? LoadStatePalette.label(for: machine.loadVisualState.state)
            : machine.status.uppercased()
    }
}

private struct MachineDetailView: View {
    let machine: MachineStatus
    let focus: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                OpsPanel {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(machine.platform.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AmbientTheme.muted)
                            Text(LoadStatePalette.label(for: machine.loadVisualState.state))
                                .font(.system(size: 38, weight: .semibold, design: .rounded))
                                .foregroundStyle(AmbientTheme.statusColor(machine.loadVisualState.state))
                        }
                        Spacer()
                        StatusPill(status: machine.status)
                    }
                    Button("Use for Display", systemImage: "scope", action: focus)
                        .buttonStyle(.borderedProminent)
                }

                OpsPanel("Current work") {
                    metricGrid
                }

                if machine.cpuPercent == nil {
                    Label(
                        "CPU telemetry is not reported by this host. Ambient Ops keeps it unknown instead of treating it as zero.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AmbientTheme.muted)
                    .padding(12)
                }
            }
            .padding(16)
        }
        .background(AmbientTheme.background)
        .navigationTitle(machine.machineName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metricGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 16) {
            GridRow {
                MetricValue(
                    label: "1 minute",
                    value: MetricFormat.tps(machine.oneMinute.tps),
                    unit: "TPS",
                    color: AmbientTheme.green
                )
                MetricValue(
                    label: "5 minute",
                    value: MetricFormat.tps(machine.fiveMinutes.tps),
                    unit: "TPS"
                )
            }
            Divider().gridCellColumns(2)
            GridRow {
                MetricValue(
                    label: "Active",
                    value: MetricFormat.integer(machine.activeSessions),
                    unit: "sessions"
                )
                MetricValue(
                    label: "CPU",
                    value: MetricFormat.percent(machine.cpuPercent),
                    unit: machine.cpuPercent == nil ? nil : "host"
                )
            }
            Divider().gridCellColumns(2)
            GridRow {
                MetricValue(
                    label: "Memory",
                    value: MetricFormat.percent(machine.memoryPercent),
                    unit: machine.memoryPercent == nil ? nil : "host"
                )
                MetricValue(
                    label: "Cache",
                    value: MetricFormat.percent(machine.cachePercent),
                    unit: "input"
                )
            }
        }
    }
}
