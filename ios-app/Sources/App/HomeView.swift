import Charts
import SwiftUI

struct HomeView: View {
    @Bindable var store: AmbientOpsStore
    let openDisplay: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    attentionPanel
                    codexMetrics
                    networkPanel
                    machineSummary
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(AmbientTheme.background)
            .refreshable { await store.refresh() }
            .navigationTitle(store.status.site.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    connectionLabel
                }
            }
        }
    }

    private var connectionLabel: some View {
        Group {
            switch store.connectionState {
            case .demo:
                StatusPill(status: "active", label: "DEMO")
            case .disconnected:
                StatusPill(status: "idle", label: "OFFLINE")
            case .loading:
                ProgressView().controlSize(.small)
            case .live:
                StatusPill(status: "live")
            case .stale:
                StatusPill(status: "stale")
            case .error:
                StatusPill(status: "error")
            }
        }
    }

    private var attentionPanel: some View {
        let machine = store.selectedMachine
        let visual = machine?.loadVisualState
        return Button(action: openDisplay) {
            OpsPanel {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(machine?.machineName ?? "No machine")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(visual.map { LoadStatePalette.label(for: $0.state) } ?? "NO DATA")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmbientTheme.statusColor(visual?.state ?? "error"))
                        Text(attentionDescription(machine))
                            .font(.subheadline)
                            .foregroundStyle(AmbientTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(AmbientTheme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open focused machine load display")
    }

    private var codexMetrics: some View {
        OpsPanel("Codex activity") {
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    MetricValue(
                        label: "1 minute",
                        value: MetricFormat.tps(store.status.codex.oneMinuteTps),
                        unit: "TPS",
                        color: AmbientTheme.green
                    )
                    MetricValue(
                        label: "Active",
                        value: MetricFormat.integer(store.status.codex.activeSessions),
                        unit: "sessions"
                    )
                }
                Divider().gridCellColumns(2)
                GridRow {
                    MetricValue(
                        label: "CPU",
                        value: MetricFormat.percent(store.status.codex.cpuPercent),
                        unit: store.status.codex.cpuPercent == nil ? nil : "host avg",
                        color: cpuColor(store.status.codex.cpuPercent)
                    )
                    MetricValue(
                        label: "Machines",
                        value: "\(Int(store.status.codex.liveMachineCount))/\(Int(store.status.codex.machineCount))",
                        unit: "live"
                    )
                }
            }
        }
    }

    private var networkPanel: some View {
        OpsPanel("Network") {
            HStack {
                MetricValue(
                    label: "Download",
                    value: MetricFormat.decimal(store.status.network.downloadMbps),
                    unit: "Mbps",
                    color: AmbientTheme.blue
                )
                Spacer()
                MetricValue(
                    label: "Upload",
                    value: MetricFormat.decimal(store.status.network.uploadMbps),
                    unit: "Mbps",
                    color: AmbientTheme.purple
                )
            }
            NetworkMiniChart(points: store.status.network.history)
                .frame(height: 84)
        }
    }

    private var machineSummary: some View {
        OpsPanel("Machines") {
            ForEach(Array(store.status.machines.prefix(4).enumerated()), id: \.element.id) { index, machine in
                if index > 0 { Divider() }
                HStack(spacing: 10) {
                    Image(systemName: machineIcon(machine.platform))
                        .foregroundStyle(AmbientTheme.statusColor(machine.status))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(machine.machineName)
                            .font(.subheadline.weight(.semibold))
                        Text(machine.platform)
                            .font(.caption)
                            .foregroundStyle(AmbientTheme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(MetricFormat.tps(machine.oneMinute.tps)) TPS")
                            .font(.subheadline.monospacedDigit())
                        Text(LoadStatePalette.label(for: machine.loadVisualState.state))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AmbientTheme.statusColor(machine.loadVisualState.state))
                    }
                }
            }
        }
    }

    private func attentionDescription(_ machine: MachineStatus?) -> String {
        guard let machine else {
            return String(localized: "Connect a server or use Demo Mode.")
        }
        return switch machine.loadVisualState.state {
        case "quiet": String(localized: "Codex is standing by.")
        case "active": String(localized: "Focused work is moving steadily.")
        case "heavy": String(localized: "Several work streams are active.")
        case "constrained": String(localized: "Host pressure is limiting active work.")
        default: String(localized: "Current development load.")
        }
    }

    private func cpuColor(_ cpu: Double?) -> Color {
        guard let cpu else { return AmbientTheme.muted }
        if cpu >= 88 { return AmbientTheme.red }
        if cpu >= 72 { return AmbientTheme.amber }
        return .primary
    }
}

struct NetworkMiniChart: View {
    let points: [NetworkHistoryPoint]

    var body: some View {
        VStack(spacing: 5) {
            NetworkSeriesChart(
                points: points,
                keyPath: \.downloadMbps,
                color: AmbientTheme.blue
            )
            NetworkSeriesChart(
                points: points,
                keyPath: \.uploadMbps,
                color: AmbientTheme.purple
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download and upload throughput trends")
    }
}

private struct NetworkSeriesChart: View {
    let points: [NetworkHistoryPoint]
    let keyPath: KeyPath<NetworkHistoryPoint, Double>
    let color: Color

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.at),
                y: .value("Throughput", point[keyPath: keyPath])
            )
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...scale)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }

    private var scale: Double {
        max(1, points.map { $0[keyPath: keyPath] }.max() ?? 1) * 1.12
    }
}

func machineIcon(_ platform: String) -> String {
    switch platform.lowercased() {
    case let value where value.contains("mac"): "macbook"
    case let value where value.contains("windows"): "desktopcomputer"
    case let value where value.contains("linux"): "server.rack"
    default: "desktopcomputer"
    }
}
