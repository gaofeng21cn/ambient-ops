import SwiftUI

struct MachinesView: View {
    @Bindable var store: OPLFleetCockpitStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }

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
            Group {
                if largeCanvas {
                    ScrollView {
                        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                            ForEach(Array(stride(from: 0, to: machines.count, by: 2)), id: \.self) { index in
                                if index + 1 < machines.count {
                                    GridRow {
                                        machineLink(machines[index])
                                        machineLink(machines[index + 1])
                                    }
                                } else {
                                    machineLink(machines[index])
                                        .gridCellColumns(2)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                } else {
                    List(machines) { machine in
                        NavigationLink {
                            MachineDetailView(machine: machine) {
                                store.selectMachine(machine.machineId)
                            }
                        } label: {
                            MachineRow(
                                machine: machine,
                                isFocused: store.selectedMachine?.machineId == machine.machineId
                            )
                        }
                        .listRowBackground(AmbientTheme.surface)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AmbientTheme.background)
            .navigationTitle(store.isFleet ? "Machines" : "Machine")
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

    private func machineLink(_ machine: MachineStatus) -> some View {
        NavigationLink {
            MachineDetailView(machine: machine) {
                store.selectMachine(machine.machineId)
            }
        } label: {
            MachineCard(
                machine: machine,
                isFocused: store.selectedMachine?.machineId == machine.machineId
            )
        }
        .buttonStyle(.plain)
    }

    private func priority(_ machine: MachineStatus) -> Int {
        switch machine.status {
        case "error": 0
        case "stale": 1
        default: machine.loadVisualState.state == "constrained" ? 2 : 3
        }
    }
}

private struct MachineCard: View {
    let machine: MachineStatus
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 11) {
                Image(systemName: machineIcon(machine.platform))
                    .font(.title2)
                    .foregroundStyle(AmbientTheme.statusColor(machine.status))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(machine.machineName)
                            .font(.headline)
                            .lineLimit(1)
                        if isFocused {
                            Image(systemName: "scope")
                                .font(.subheadline)
                                .foregroundStyle(AmbientTheme.green)
                                .accessibilityLabel("Focused machine")
                        }
                    }
                    Text(machine.platform)
                        .font(.subheadline)
                        .foregroundStyle(AmbientTheme.muted)
                }
                Spacer(minLength: 6)
                Text(secondaryState)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AmbientTheme.statusColor(
                        machine.status == "live" ? machine.loadVisualState.state : machine.status
                    ))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmbientTheme.muted)
            }

            Divider()

            HStack(alignment: .bottom, spacing: 16) {
                cardMetric(
                    "TPS",
                    MetricFormat.tps(machine.oneMinute.tps),
                    color: AmbientTheme.green,
                    primary: true
                )
                cardMetric("Active", MetricFormat.integer(machine.activeSessions))
                cardMetric("CPU", MetricFormat.percent(machine.cpuPercent))
            }

            Divider()

            HStack(alignment: .bottom, spacing: 16) {
                cardMetric("5 min", MetricFormat.tps(machine.fiveMinutes.tps), compact: true)
                cardMetric("Memory", MetricFormat.percent(machine.memoryPercent), compact: true)
                cardMetric("Cache", MetricFormat.percent(machine.cachePercent), compact: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 214, alignment: .topLeading)
        .background(AmbientTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? AmbientTheme.green.opacity(0.35) : AmbientTheme.line)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    private func cardMetric(
        _ label: String,
        _ value: String,
        color: Color = .primary,
        primary: Bool = false,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            Text(value)
                .font(.system(
                    size: primary ? 27 : (compact ? 18 : 22),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var secondaryState: String {
        machine.status == "live"
            ? LoadStatePalette.label(for: machine.loadVisualState.state)
            : machine.status.uppercased()
    }
}

private struct MachineRow: View {
    let machine: MachineStatus
    let isFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: machineIcon(machine.platform))
                .font(largeCanvas ? .title2 : .title3)
                .foregroundStyle(AmbientTheme.statusColor(machine.status))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(machine.machineName)
                        .font(largeCanvas ? .title3 : .headline)
                    if isFocused {
                        Image(systemName: "scope")
                            .font(largeCanvas ? .subheadline : .caption)
                            .foregroundStyle(AmbientTheme.green)
                            .accessibilityLabel("Focused machine")
                    }
                }
                Text("\(machine.platform) · \(secondaryState)")
                    .font(largeCanvas ? .subheadline : .caption)
                    .foregroundStyle(AmbientTheme.statusColor(
                        machine.status == "live" ? machine.loadVisualState.state : machine.status
                    ))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(MetricFormat.tps(machine.oneMinute.tps))
                    .font((largeCanvas ? Font.title3 : .headline).monospacedDigit())
                Text("TPS")
                    .font(largeCanvas ? .caption : .caption2)
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
        .padding(.vertical, largeCanvas ? 10 : 6)
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                OpsPanel {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(machine.platform.uppercased())
                                .font((largeCanvas ? Font.subheadline : .caption).weight(.semibold))
                                .foregroundStyle(AmbientTheme.muted)
                            Text(LoadStatePalette.label(for: machine.loadVisualState.state))
                                .font(.system(size: largeCanvas ? 48 : 38, weight: .semibold, design: .rounded))
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
                        "CPU telemetry is not reported by this host. OPL Fleet Cockpit keeps it unknown instead of treating it as zero.",
                        systemImage: "info.circle"
                    )
                    .font(largeCanvas ? .body : .footnote)
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
