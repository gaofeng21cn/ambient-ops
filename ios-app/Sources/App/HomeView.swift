import Charts
import SwiftUI

struct HomeView: View {
    @Bindable var store: AmbientOpsStore
    let openDisplay: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width > proxy.size.height {
                    landscapeDashboard(size: proxy.size)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            attentionPanel
                            codexMetrics
                            if store.status.capabilities.supportsNetwork {
                                networkPanel
                            }
                            machineSummary
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .background(AmbientTheme.background)
            .navigationTitle(store.status.site.name)
            .navigationBarTitleDisplayMode(verticalSizeClass == .compact ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Text(largeCanvas ? store.providerLabel : (store.isFleet ? "FLEET" : "DIRECT"))
                            .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                            .foregroundStyle(AmbientTheme.muted)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        connectionLabel
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func landscapeDashboard(size: CGSize) -> some View {
        if largeCanvas {
            tabletLandscapeDashboard(size: size)
        } else {
            compactLandscapeDashboard
        }
    }

    private func tabletLandscapeDashboard(size: CGSize) -> some View {
        let contentWidth = max(0, size.width - 30)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                landscapeAttention
                    .frame(width: contentWidth * 0.34)
                landscapeCodex
            }
            HStack(spacing: 10) {
                if store.status.capabilities.supportsNetwork {
                    landscapeNetwork
                        .frame(width: contentWidth * 0.57)
                }
                landscapeMachines
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var compactLandscapeDashboard: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                landscapeAttention
                landscapeCodex
            }
            VStack(spacing: 8) {
                if store.status.capabilities.supportsNetwork {
                    landscapeNetwork
                }
                landscapeMachines
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var landscapeAttention: some View {
        let machine = store.selectedMachine
        let visual = machine?.loadVisualState
        return Button(action: openDisplay) {
            LandscapeHomePanel(large: largeCanvas) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(machine?.machineName ?? "No machine")
                            .font((largeCanvas ? Font.subheadline : .caption).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(visual.map { LoadStatePalette.label(for: $0.state) } ?? "NO DATA")
                            .font(.system(size: largeCanvas ? 46 : 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmbientTheme.statusColor(visual?.state ?? "error"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(attentionDescription(machine))
                            .font(largeCanvas ? .subheadline : .caption2)
                            .foregroundStyle(AmbientTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font((largeCanvas ? Font.headline : .caption).weight(.semibold))
                        .foregroundStyle(AmbientTheme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open focused machine load display")
    }

    private var landscapeCodex: some View {
        LandscapeHomePanel("Codex activity", large: largeCanvas) {
            HStack(alignment: .top, spacing: 8) {
                landscapeMetric(
                    "1 MIN",
                    MetricFormat.tps(store.status.codex.oneMinuteTps),
                    "TPS",
                    AmbientTheme.green
                )
                landscapeMetric(
                    "ACTIVE",
                    MetricFormat.integer(store.status.codex.activeSessions),
                    "SESSIONS"
                )
                landscapeMetric(
                    "CPU",
                    MetricFormat.percent(store.status.codex.cpuPercent),
                    store.status.codex.cpuPercent == nil ? nil : "HOST AVG",
                    cpuColor(store.status.codex.cpuPercent)
                )
                landscapeMetric(
                    "MACHINES",
                    "\(Int(store.status.codex.liveMachineCount))/\(Int(store.status.codex.machineCount))",
                    "LIVE"
                )
            }
        }
    }

    private var landscapeNetwork: some View {
        let network = store.displayNetwork
        return LandscapeHomePanel("Network", large: largeCanvas) {
            HStack(alignment: .top, spacing: 20) {
                landscapeMetric(
                    "DOWNLOAD",
                    MetricFormat.decimal(network.downloadMbps),
                    "MBPS",
                    AmbientTheme.blue
                )
                landscapeMetric(
                    "UPLOAD",
                    MetricFormat.decimal(network.uploadMbps),
                    "MBPS",
                    AmbientTheme.purple
                )
                NetworkMiniChart(points: network.history)
                    .frame(maxWidth: .infinity, maxHeight: largeCanvas ? .infinity : 44)
            }
        }
    }

    private var landscapeMachines: some View {
        LandscapeHomePanel(store.isFleet ? "Machines" : "Machine", large: largeCanvas) {
            if largeCanvas {
                VStack(spacing: 0) {
                    ForEach(Array(store.status.machines.prefix(4).enumerated()), id: \.element.id) { index, machine in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Image(systemName: machineIcon(machine.platform))
                                .font(.title3)
                                .foregroundStyle(AmbientTheme.statusColor(machine.status))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(machine.machineName)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                Text(LoadStatePalette.label(for: machine.loadVisualState.state))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AmbientTheme.statusColor(machine.loadVisualState.state))
                            }
                            Spacer(minLength: 6)
                            Text("\(MetricFormat.tps(machine.oneMinute.tps)) TPS")
                                .font(.subheadline.monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.vertical, 8)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 7
                ) {
                    ForEach(store.status.machines.prefix(4)) { machine in
                        HStack(spacing: 7) {
                            Image(systemName: machineIcon(machine.platform))
                                .font(.caption)
                                .foregroundStyle(AmbientTheme.statusColor(machine.status))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(machine.machineName)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text("\(MetricFormat.tps(machine.oneMinute.tps)) TPS")
                                        .font(.caption2.monospacedDigit())
                                    Circle()
                                        .fill(AmbientTheme.statusColor(machine.loadVisualState.state))
                                        .frame(width: 5, height: 5)
                                }
                                .foregroundStyle(AmbientTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func landscapeMetric(
        _ label: String,
        _ value: String,
        _ unit: String?,
        _ color: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: largeCanvas ? 13 : 9, weight: .semibold))
                .foregroundStyle(AmbientTheme.muted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: largeCanvas ? 32 : 20, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let unit {
                Text(unit)
                    .font(.system(size: largeCanvas ? 12 : 8, weight: .medium))
                    .foregroundStyle(AmbientTheme.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionLabel: some View {
        Group {
            switch store.connectionState {
            case .demo:
                ToolbarStatusLabel(status: "active", label: "DEMO")
            case .disconnected:
                ToolbarStatusLabel(status: "idle", label: "OFFLINE")
            case .loading:
                ProgressView().controlSize(.small)
            case .live:
                ToolbarStatusLabel(status: "live")
            case .stale:
                ToolbarStatusLabel(status: "stale")
            case .error:
                ToolbarStatusLabel(status: "error")
            }
        }
    }

    private struct ToolbarStatusLabel: View {
        let status: String
        var label: String? = nil

        var body: some View {
            HStack(spacing: 5) {
                Circle()
                    .fill(AmbientTheme.statusColor(status))
                    .frame(width: 7, height: 7)
                Text(label ?? status.uppercased())
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(AmbientTheme.statusColor(status))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
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
                            .font(largeCanvas ? .title3 : .headline)
                            .foregroundStyle(.primary)
                        Text(visual.map { LoadStatePalette.label(for: $0.state) } ?? "NO DATA")
                            .font(.system(size: largeCanvas ? 44 : 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmbientTheme.statusColor(visual?.state ?? "error"))
                        Text(attentionDescription(machine))
                            .font(largeCanvas ? .body : .subheadline)
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
        let network = store.displayNetwork
        return OpsPanel("Network") {
            HStack {
                MetricValue(
                    label: "Download",
                    value: MetricFormat.decimal(network.downloadMbps),
                    unit: "Mbps",
                    color: AmbientTheme.blue
                )
                Spacer()
                MetricValue(
                    label: "Upload",
                    value: MetricFormat.decimal(network.uploadMbps),
                    unit: "Mbps",
                    color: AmbientTheme.purple
                )
            }
            NetworkMiniChart(points: network.history)
                .frame(height: 84)
        }
    }

    private var machineSummary: some View {
        OpsPanel(store.isFleet ? "Machines" : "Machine") {
            ForEach(Array(store.status.machines.prefix(4).enumerated()), id: \.element.id) { index, machine in
                if index > 0 { Divider() }
                HStack(spacing: 10) {
                    Image(systemName: machineIcon(machine.platform))
                        .foregroundStyle(AmbientTheme.statusColor(machine.status))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(machine.machineName)
                            .font((largeCanvas ? Font.body : .subheadline).weight(.semibold))
                        Text(machine.platform)
                            .font(largeCanvas ? .subheadline : .caption)
                            .foregroundStyle(AmbientTheme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(MetricFormat.tps(machine.oneMinute.tps)) TPS")
                            .font((largeCanvas ? Font.body : .subheadline).monospacedDigit())
                        Text(LoadStatePalette.label(for: machine.loadVisualState.state))
                            .font((largeCanvas ? Font.caption : .caption2).weight(.bold))
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

private struct LandscapeHomePanel<Content: View>: View {
    let title: String?
    let large: Bool
    @ViewBuilder let content: Content

    init(_ title: String? = nil, large: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.large = large
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 10 : 7) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: large ? 12 : 9, weight: .semibold))
                    .foregroundStyle(AmbientTheme.muted)
            }
            content
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: large ? .center : .topLeading
                )
        }
        .padding(large ? 14 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AmbientTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(AmbientTheme.line)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
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
