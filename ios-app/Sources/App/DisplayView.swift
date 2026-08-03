import Charts
import SwiftUI

struct DisplayView: View {
    @Bindable var store: OPLFleetCockpitStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }
    private var compactLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let compactHeader = proxy.size.width < 900
            VStack(spacing: 0) {
                displayHeader(compact: compactHeader, availableWidth: proxy.size.width)
                Divider().overlay(AmbientTheme.line)
                Group {
                    switch store.displayMode {
                    case .overview:
                        OverviewDisplay(
                            status: store.status,
                            network: store.displayNetwork,
                            landscape: landscape
                        )
                    case .network:
                        NetworkDisplay(network: store.displayNetwork, landscape: landscape)
                    case .load:
                        if store.displayScope == .fleet, store.isFleet {
                            FleetLoadDisplay(
                                presentation: store.fleetLoadPresentation,
                                history: store.fleetLoadHistory,
                                landscape: landscape
                            )
                        } else if let machine = store.selectedMachine {
                            HostLoadDisplay(
                                machine: machine,
                                history: store.loadHistory[machine.machineId] ?? [],
                                landscape: landscape
                            )
                        } else {
                            unavailable
                        }
                    case .pet:
                        if let machine = store.selectedMachine {
                            PetDisplay(
                                machine: machine,
                                serverURL: OPLFleetCockpitClient.normalizedServerURL(store.serverAddress),
                                landscape: landscape
                            )
                        } else {
                            unavailable
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(
                .bottom,
                DisplayLayoutProfile.tabBarClearance(compactLandscape: compactLandscape)
            )
            .background(AmbientTheme.background)
        }
    }

    @ViewBuilder
    private func displayHeader(compact: Bool, availableWidth: CGFloat) -> some View {
        if availableWidth < 620 {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    scopeControl(compact: true)
                    displayIdentity
                    Spacer(minLength: 4)
                    StatusPill(status: store.status.overallStatus)
                }
                displayModePicker(compact: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(height: 84)
        } else {
            HStack(spacing: compact ? 10 : 12) {
                scopeControl(compact: compact)
                displayIdentity
                Spacer(minLength: 6)
                displayModePicker(compact: compact)
                    .frame(maxWidth: compact ? 280 : 360)
                Spacer(minLength: 6)
                StatusPill(status: store.status.overallStatus)
            }
            .padding(.horizontal, largeCanvas ? 16 : compact ? 12 : 16)
            .frame(height: largeCanvas ? 54 : compact ? 44 : 54)
        }
    }

    @ViewBuilder
    private func scopeControl(compact: Bool) -> some View {
        if store.isFleet, store.displayMode == .load {
            Picker(
                "Display scope",
                selection: Binding(
                    get: { store.displayScope },
                    set: { store.displayScope = $0 }
                )
            ) {
                ForEach(DisplayScope.allCases) { scope in
                    if compact {
                        Label(scope.label, systemImage: scope.systemImage)
                            .labelStyle(.iconOnly)
                            .tag(scope)
                    } else {
                        Label(scope.label, systemImage: scope.systemImage)
                            .tag(scope)
                    }
                }
            }
            .pickerStyle(.segmented)
            .frame(width: compact ? 104 : 172)
        } else {
            Text(store.isFleet ? "FLEET" : "DIRECT")
                .font((largeCanvas ? Font.caption : .caption2).weight(.bold))
                .foregroundStyle(store.isFleet ? AmbientTheme.blue : AmbientTheme.green)
        }
    }

    @ViewBuilder
    private var displayIdentity: some View {
        if store.isFleet, store.displayScope == .fleet, store.displayMode == .load {
            HStack(spacing: 6) {
                Image(systemName: "network")
                Text("\(store.fleetLoadPresentation.liveNodeCount)/\(store.fleetLoadPresentation.totalNodeCount) nodes")
                    .lineLimit(1)
            }
            .font((largeCanvas ? Font.headline : .subheadline).weight(.semibold))
            .foregroundStyle(AmbientTheme.blue)
        } else {
            Menu {
                ForEach(store.status.machines) { machine in
                    Button {
                        store.selectMachine(machine.machineId)
                    } label: {
                        Label(machine.machineName, systemImage: machineIcon(machine.platform))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: machineIcon(store.selectedMachine?.platform ?? ""))
                    Text(store.selectedMachine?.machineName ?? String(localized: "No machine"))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(largeCanvas ? .caption : .caption2)
                }
                .font((largeCanvas ? Font.headline : .subheadline).weight(.semibold))
            }
        }
    }

    private func displayModePicker(compact: Bool) -> some View {
        Picker("Display mode", selection: $store.displayMode) {
            ForEach(store.availableDisplayModes) { mode in
                if compact {
                    localizedModeLabel(mode)
                        .labelStyle(.iconOnly)
                        .tag(mode)
                } else {
                    localizedModeLabel(mode)
                        .tag(mode)
                }
            }
        }
        .pickerStyle(.segmented)
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "No machine",
            systemImage: "desktopcomputer.trianglebadge.exclamationmark",
            description: Text("Connect a server or enable Demo Mode.")
        )
    }

    private func localizedModeLabel(_ mode: DisplayMode) -> some View {
        Label {
            Text(LocalizedStringKey(mode.label))
        } icon: {
            Image(systemName: mode.systemImage)
        }
    }
}

enum DisplayLayoutProfile {
    static let compactLandscapeTabBarClearance: CGFloat = 56

    static func tabBarClearance(compactLandscape: Bool) -> CGFloat {
        compactLandscape ? compactLandscapeTabBarClearance : 0
    }
}

private struct FleetLoadDisplay: View {
    let presentation: FleetLoadPresentation
    let history: [LoadHistoryPoint]
    let landscape: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }
    private var compactLandscape: Bool { landscape && verticalSizeClass == .compact }

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: 0) {
                    stage
                    metrics
                        .frame(width: largeCanvas ? 320 : 268)
                }
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        stage
                            .frame(
                                width: proxy.size.width,
                                height: min(proxy.size.width * 0.68, proxy.size.height * 0.54)
                            )
                        metrics
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    }
                }
            }
        }
        .background(AmbientTheme.background)
    }

    private var stage: some View {
        VStack(spacing: 0) {
            stageHeader
            FleetLoadSceneView(presentation: presentation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AmbientTheme.background)
        .clipped()
    }

    private var stageHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "network")
                .foregroundStyle(AmbientTheme.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("FLEET ACTIVITY")
                    .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                    .foregroundStyle(AmbientTheme.muted)
                Text("\(presentation.workingNodeCount) working · \(presentation.liveNodeCount) connected")
                    .font(.system(size: largeCanvas ? 10 : 8, weight: .medium))
                    .foregroundStyle(AmbientTheme.muted)
            }
            Spacer(minLength: 10)
            Circle()
                .fill(AmbientTheme.statusColor(presentation.visual.state))
                .frame(width: largeCanvas ? 8 : 7, height: largeCanvas ? 8 : 7)
            VStack(alignment: .trailing, spacing: 1) {
                Text(LoadStatePalette.label(for: presentation.visual.state))
                    .font(
                        .system(
                            size: largeCanvas ? 24 : landscape ? 19 : 17,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(AmbientTheme.statusColor(presentation.visual.state))
                    .lineLimit(1)
                Text(fleetDescription)
                    .font(.system(size: largeCanvas ? 10 : 8, weight: .medium))
                    .foregroundStyle(AmbientTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, largeCanvas ? 18 : 14)
        .frame(height: largeCanvas ? 62 : compactLandscape ? 38 : landscape ? 50 : 48)
        .background(AmbientTheme.surface.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AmbientTheme.line).frame(height: 1)
        }
    }

    private var metrics: some View {
        VStack(spacing: 0) {
            sideMetric(
                "1 MINUTE",
                value: MetricFormat.tps(presentation.oneMinuteTps),
                unit: "TPS",
                color: AmbientTheme.statusColor(presentation.visual.state)
            )
            Divider().overlay(AmbientTheme.line)
            HStack(spacing: 14) {
                compactMetric("ACTIVE", MetricFormat.integer(presentation.activeSessions), "SESSIONS")
                compactMetric(
                    "NODES",
                    "\(presentation.liveNodeCount)/\(presentation.totalNodeCount)",
                    "LIVE / TOTAL"
                )
                compactMetric(
                    "CPU",
                    MetricFormat.percent(presentation.cpuPercent),
                    presentation.cpuReportedNodeCount > 0
                        ? "\(presentation.cpuReportedNodeCount) HOSTS"
                        : "NO REPORTS"
                )
            }
            .padding(compactLandscape ? 8 : 14)
            Divider().overlay(AmbientTheme.line)
            trend
            Divider().overlay(AmbientTheme.line)
            loadScale
        }
        .background(AmbientTheme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(AmbientTheme.line).frame(width: 1)
        }
    }

    private func sideMetric(_ label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(
                        .system(
                            size: largeCanvas ? 48 : compactLandscape ? 30 : 38,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text(unit)
                    .font(largeCanvas ? .caption : .caption2)
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
        .padding(compactLandscape ? 8 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: largeCanvas ? 10 : 8, weight: .semibold))
                .foregroundStyle(AmbientTheme.muted)
            Text(value)
                .font(.system(size: largeCanvas ? 21 : 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == "N/A" ? AmbientTheme.muted : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.system(size: largeCanvas ? 9 : 7))
                .foregroundStyle(AmbientTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(trendTitle)
                Spacer()
                Text(trendSummary)
            }
            .font(.system(size: largeCanvas ? 11 : 9, weight: .semibold))
            .foregroundStyle(AmbientTheme.muted)

            Chart(history) { point in
                LineMark(
                    x: .value("Time", point.at),
                    y: .value("TPS", point.tps)
                )
                .foregroundStyle(AmbientTheme.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: 0...trendScale)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: largeCanvas ? 80 : compactLandscape ? 34 : landscape ? 58 : 46)

            HStack {
                Text(coveredMinutes > 0 ? "-\(coveredMinutes)M" : "NOW")
                Spacer()
                Text("NOW")
            }
            .font(.system(size: largeCanvas ? 9 : 7, weight: .medium))
            .foregroundStyle(AmbientTheme.muted)
        }
        .padding(compactLandscape ? 8 : 14)
    }

    private var loadScale: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AmbientTheme.line)
                    Rectangle()
                        .fill(AmbientTheme.statusColor(presentation.visual.state))
                        .frame(width: max(3, proxy.size.width * presentation.visual.normalizedScore))
                }
            }
            .frame(height: 6)
            HStack {
                Text("QUIET")
                Spacer()
                Text("ACTIVE")
                Spacer()
                Text("HEAVY")
                Spacer()
                Text("LIMIT")
            }
            .font(.system(size: largeCanvas ? 9 : 7, weight: .semibold))
            .foregroundStyle(AmbientTheme.muted)
        }
        .padding(compactLandscape ? 8 : 14)
    }

    private var coveredMinutes: Int { LoadHistorySeries.coveredMinutes(history) }

    private var trendTitle: String {
        coveredMinutes >= 30 ? "30 MIN TREND" : coveredMinutes > 0 ? "\(coveredMinutes) MIN TREND" : "LIVE TREND"
    }

    private var trendSummary: String {
        guard history.count > 1 else { return "COLLECTING" }
        let average = history.map(\.tps).reduce(0, +) / Double(history.count)
        return "\(MetricFormat.tps(average)) TPS AVG"
    }

    private var trendScale: Double {
        max(1, history.map(\.tps).max() ?? 1) / 0.92
    }

    private var fleetDescription: String {
        switch presentation.visual.state {
        case "quiet": String(localized: "Fleet standing by")
        case "active": String(localized: "Nodes in motion")
        case "heavy": String(localized: "Parallel fleet work")
        case "constrained": String(localized: "Host pressure detected")
        default: String(localized: "Fleet activity")
        }
    }
}

private struct HostLoadDisplay: View {
    let machine: MachineStatus
    let history: [LoadHistoryPoint]
    let landscape: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }
    private var compactLandscape: Bool { landscape && verticalSizeClass == .compact }

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: 0) {
                    stage
                    metrics
                        .frame(width: largeCanvas ? 300 : 252)
                }
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        stage
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.width * 9 / 16
                            )
                        metrics
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                            .background(AmbientTheme.surface)
                    }
                }
            }
        }
        .background(AmbientTheme.background)
    }

    private var stage: some View {
        VStack(spacing: 0) {
            stageHeader
            LoadSceneView(visual: machine.loadVisualState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AmbientTheme.background)
        .clipped()
    }

    private var stageHeader: some View {
        HStack(spacing: 8) {
            Text("HOST LOAD")
                .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            Spacer(minLength: 12)
            Circle()
                .fill(AmbientTheme.statusColor(machine.loadVisualState.state))
                .frame(width: largeCanvas ? 8 : 7, height: largeCanvas ? 8 : 7)
            Text(LoadStatePalette.label(for: machine.loadVisualState.state))
                .font(
                    .system(
                        size: largeCanvas ? 26 : landscape ? 20 : 18,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(AmbientTheme.statusColor(machine.loadVisualState.state))
                .lineLimit(1)
        }
        .padding(.horizontal, largeCanvas ? 18 : 14)
        .frame(height: largeCanvas ? 54 : compactLandscape ? 36 : landscape ? 44 : 40)
        .background(AmbientTheme.surface.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AmbientTheme.line)
                .frame(height: 1)
        }
    }

    private var metrics: some View {
        VStack(spacing: 0) {
            sideMetric(
                "1 MINUTE",
                value: MetricFormat.tps(machine.oneMinute.tps),
                unit: "TPS",
                color: AmbientTheme.statusColor(machine.loadVisualState.state)
            )
            Divider().overlay(AmbientTheme.line)
            HStack {
                compactMetric("ACTIVE", MetricFormat.integer(machine.activeSessions), "SESSIONS")
                Spacer()
                compactMetric(
                    "CPU",
                    MetricFormat.percent(machine.cpuPercent),
                    machine.cpuPercent == nil ? "" : "HOST"
                )
            }
            .padding(compactLandscape ? 8 : 14)
            Divider().overlay(AmbientTheme.line)
            trend
            Divider().overlay(AmbientTheme.line)
            loadScale
        }
        .background(AmbientTheme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(AmbientTheme.line).frame(width: 1)
        }
    }

    private func sideMetric(_ label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(
                        .system(
                            size: largeCanvas ? 48 : compactLandscape ? 30 : 38,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(unit)
                    .font(largeCanvas ? .caption : .caption2)
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
        .padding(compactLandscape ? 8 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            Text(value)
                .font((largeCanvas ? Font.title2 : .title3).monospacedDigit().weight(.semibold))
                .foregroundStyle(value == "N/A" ? AmbientTheme.muted : .primary)
            Text(unit)
                .font(.system(size: largeCanvas ? 10 : 8))
                .foregroundStyle(AmbientTheme.muted)
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(trendTitle)
                Spacer()
                Text(trendSummary)
            }
            .font(.system(size: largeCanvas ? 11 : 9, weight: .semibold))
            .foregroundStyle(AmbientTheme.muted)

            Chart(history) { point in
                LineMark(
                    x: .value("Time", point.at),
                    y: .value("TPS", point.tps)
                )
                .foregroundStyle(AmbientTheme.green)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: 0...trendScale)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: largeCanvas ? 80 : compactLandscape ? 34 : landscape ? 58 : 46)

            HStack {
                Text(trendStartLabel)
                Spacer()
                Text("NOW")
            }
            .font(.system(size: largeCanvas ? 9 : 7, weight: .medium))
            .foregroundStyle(AmbientTheme.muted)
        }
        .padding(compactLandscape ? 8 : 14)
    }

    private var coveredMinutes: Int {
        LoadHistorySeries.coveredMinutes(history)
    }

    private var trendTitle: String {
        coveredMinutes >= 30 ? "30 MIN TREND" : coveredMinutes > 0 ? "\(coveredMinutes) MIN TREND" : "LIVE TREND"
    }

    private var trendSummary: String {
        guard history.count > 1 else { return "COLLECTING" }
        let average = history.map(\.tps).reduce(0, +) / Double(history.count)
        return "\(MetricFormat.tps(average)) TPS AVG"
    }

    private var trendStartLabel: String {
        coveredMinutes > 0 ? "-\(coveredMinutes)M" : "NOW"
    }

    private var trendScale: Double {
        max(1, history.map(\.tps).max() ?? 1) / 0.92
    }

    private var loadScale: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AmbientTheme.line)
                    Rectangle()
                        .fill(AmbientTheme.statusColor(machine.loadVisualState.state))
                        .frame(width: max(3, proxy.size.width * machine.loadVisualState.normalizedScore))
                }
            }
            .frame(height: 6)
            HStack {
                Text("QUIET")
                Spacer()
                Text("ACTIVE")
                Spacer()
                Text("HEAVY")
                Spacer()
                Text("LIMIT")
            }
            .font(.system(size: largeCanvas ? 9 : 7, weight: .semibold))
            .foregroundStyle(AmbientTheme.muted)
        }
        .padding(compactLandscape ? 8 : 14)
    }
}

private struct OverviewDisplay: View {
    let status: AmbientStatus
    let network: NetworkStatus
    let landscape: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if landscape {
                    HStack(spacing: 0) {
                        primaryMetric(
                            "CODEX",
                            MetricFormat.tps(status.codex.oneMinuteTps),
                            "TPS",
                            AmbientTheme.green
                        )
                        Divider().overlay(AmbientTheme.line)
                        primaryMetric(
                            "DOWNLOAD",
                            MetricFormat.decimal(network.downloadMbps),
                            "Mbps",
                            AmbientTheme.blue
                        )
                        Divider().overlay(AmbientTheme.line)
                        primaryMetric(
                            "UPLOAD",
                            MetricFormat.decimal(network.uploadMbps),
                            "Mbps",
                            AmbientTheme.purple
                        )
                    }
                    .frame(height: min(largeCanvas ? 132 : 104, proxy.size.height * 0.38))
                } else {
                    VStack(spacing: 0) {
                        primaryMetric(
                            "CODEX",
                            MetricFormat.tps(status.codex.oneMinuteTps),
                            "TPS",
                            AmbientTheme.green
                        )
                        Divider().overlay(AmbientTheme.line)
                        HStack(spacing: 0) {
                            primaryMetric(
                                "DOWNLOAD",
                                MetricFormat.decimal(network.downloadMbps),
                                "Mbps",
                                AmbientTheme.blue
                            )
                            Divider().overlay(AmbientTheme.line)
                            primaryMetric(
                                "UPLOAD",
                                MetricFormat.decimal(network.uploadMbps),
                                "Mbps",
                                AmbientTheme.purple
                            )
                        }
                    }
                    .frame(height: min(196, proxy.size.height * 0.36))
                }

                Divider().overlay(AmbientTheme.line)
                networkTrend
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(AmbientTheme.line)
                summaryBar
                    .frame(height: largeCanvas ? 64 : landscape ? 48 : 58)
            }
        }
        .background(AmbientTheme.surface)
    }

    private func primaryMetric(
        _ label: String,
        _ value: String,
        _ unit: String,
        _ color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(
                        size: largeCanvas ? 48 : landscape ? 36 : 34,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: largeCanvas ? 11 : 9, weight: .medium))
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
        .padding(landscape ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var networkTrend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("30 MIN NETWORK")
                Spacer()
                legend("DOWN", AmbientTheme.blue)
                legend("UP", AmbientTheme.purple)
            }
            .font(.system(size: largeCanvas ? 11 : 9, weight: .semibold))
            .foregroundStyle(AmbientTheme.muted)

            if network.history.count > 1 {
                Chart {
                    ForEach(network.history) { point in
                        LineMark(
                            x: .value("Time", point.atDate ?? .distantPast),
                            y: .value("Download", point.downloadMbps),
                            series: .value("Direction", "Download")
                        )
                        .foregroundStyle(AmbientTheme.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    ForEach(network.history) { point in
                        LineMark(
                            x: .value("Time", point.atDate ?? .distantPast),
                            y: .value("Upload", point.uploadMbps),
                            series: .value("Direction", "Upload")
                        )
                        .foregroundStyle(AmbientTheme.purple)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(largeCanvas ? .title2 : .title3)
                    Text(network.status == "live" ? "COLLECTING NETWORK HISTORY" : "NETWORK HISTORY UNAVAILABLE")
                        .font(.system(size: largeCanvas ? 11 : 9, weight: .semibold))
                }
                .foregroundStyle(AmbientTheme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 2)
            Text(label)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryMetric(
                "CODEX 5M",
                MetricFormat.tps(status.codex.fiveMinuteTps),
                "TPS"
            )
            Divider().overlay(AmbientTheme.line)
            summaryMetric(
                "CACHE",
                MetricFormat.integer(status.codex.cachePercent),
                "%"
            )
            Divider().overlay(AmbientTheme.line)
            summaryMetric(
                "LIVE",
                "\(Int(status.codex.liveMachineCount))/\(Int(status.codex.machineCount))",
                nil,
                status.codex.liveMachineCount == status.codex.machineCount
                    ? AmbientTheme.green
                    : AmbientTheme.amber
            )
        }
    }

    private func summaryMetric(
        _ label: String,
        _ value: String,
        _ unit: String?,
        _ color: Color = .primary
    ) -> some View {
        Group {
            if landscape {
                HStack(spacing: 7) {
                    Text(label)
                        .font(.system(size: largeCanvas ? 10 : 8, weight: .semibold))
                        .foregroundStyle(AmbientTheme.muted)
                    Spacer(minLength: 4)
                    summaryValue(value, unit: unit, color: color)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: largeCanvas ? 10 : 8, weight: .semibold))
                        .foregroundStyle(AmbientTheme.muted)
                    summaryValue(value, unit: unit, color: color)
                }
            }
        }
        .padding(.horizontal, landscape ? 14 : 10)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: landscape ? .center : .leading
        )
    }

    private func summaryValue(_ value: String, unit: String?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(largeCanvas ? .title2 : .headline, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            if let unit {
                Text(unit)
                    .font(.system(size: largeCanvas ? 10 : 8, weight: .medium))
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
    }
}

private struct NetworkDisplay: View {
    let network: NetworkStatus
    let landscape: Bool

    var body: some View {
        VStack(spacing: 0) {
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
                Spacer()
                MetricValue(
                    label: "Latency",
                    value: MetricFormat.decimal(network.latencyMs),
                    unit: network.latencyMs == nil ? nil : "ms"
                )
            }
            .padding(landscape ? 16 : 20)
            Divider().overlay(AmbientTheme.line)
            NetworkMiniChart(points: network.history)
                .padding(16)
        }
    }
}

private struct PetDisplay: View {
    let machine: MachineStatus
    let serverURL: URL?
    let landscape: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var largeCanvas: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            if landscape {
                HStack(spacing: 0) {
                    stage
                    metrics
                        .frame(width: largeCanvas ? 330 : min(300, max(252, proxy.size.width * 0.32)))
                }
            } else {
                VStack(spacing: 0) {
                    stage
                        .frame(
                            width: proxy.size.width,
                            height: min(proxy.size.height * 0.56, proxy.size.width * 0.96)
                        )
                    metrics
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(AmbientTheme.background)
    }

    @ViewBuilder
    private var stage: some View {
        if let pet = machine.pet {
            ZStack(alignment: .topLeading) {
                PetSceneView(pet: pet, serverURL: serverURL)
                VStack(alignment: .leading, spacing: 5) {
                    Text(pet.displayName)
                        .font((largeCanvas ? Font.title : .title2).weight(.semibold))
                    Text(pet.state.uppercased())
                        .font((largeCanvas ? Font.subheadline : .caption).weight(.bold))
                        .foregroundStyle(petStateColor)
                }
                .padding(largeCanvas ? 20 : 16)
            }
            .clipped()
        } else {
            ContentUnavailableView(
                "No companion configured",
                systemImage: "bird",
                description: Text("\(machine.machineName) is reporting normally without a Codex Pet.")
            )
        }
    }

    private var metrics: some View {
        GeometryReader { proxy in
            let primaryHeight = min(
                largeCanvas ? 170 : 140,
                max(largeCanvas ? 108 : 82, proxy.size.height * 0.36)
            )
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("1 MINUTE")
                        .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                        .foregroundStyle(petStateColor)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(MetricFormat.tps(machine.oneMinute.tps))
                            .font(.system(size: largeCanvas ? 54 : 42, weight: .semibold, design: .rounded))
                            .foregroundStyle(petStateColor)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("TPS")
                            .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                            .foregroundStyle(AmbientTheme.muted)
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: primaryHeight, alignment: .leading)

                Divider().overlay(AmbientTheme.line)
                petMetric(
                    "INPUT",
                    value: tokenRate(machine.oneMinute.inputTokens),
                    unit: "TPS",
                    detail: "CACHE \(MetricFormat.percent(machine.cachePercent))"
                )
                Divider().overlay(AmbientTheme.line)
                petMetric(
                    "OUTPUT",
                    value: tokenRate(machine.oneMinute.outputTokens),
                    unit: "TPS",
                    detail: "REASON \(tokenRate(machine.oneMinute.reasoningOutputTokens)) TPS"
                )
                Divider().overlay(AmbientTheme.line)
                petMetric(
                    "ACTIVE",
                    value: MetricFormat.integer(machine.activeSessions),
                    unit: "SESSIONS"
                )
            }
        }
        .background(AmbientTheme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(AmbientTheme.line).frame(width: 1)
        }
    }

    private func petMetric(
        _ label: String,
        value: String,
        unit: String,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font((largeCanvas ? Font.caption : .caption2).weight(.semibold))
                    .foregroundStyle(AmbientTheme.muted)
                if let detail {
                    Text(detail)
                        .font(.system(size: largeCanvas ? 11 : 9, weight: .medium))
                        .foregroundStyle(AmbientTheme.muted.opacity(0.72))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(largeCanvas ? .title2 : .title3, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(unit)
                    .font(.system(size: largeCanvas ? 11 : 9, weight: .medium))
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tokenRate(_ total: Double?) -> String {
        guard let total else { return "N/A" }
        return MetricFormat.tps(total / 60)
    }

    private var petStateColor: Color {
        switch machine.pet?.state {
        case "idle": .secondary
        case "waiting": AmbientTheme.amber
        case "review": AmbientTheme.purple
        case "failed": AmbientTheme.red
        default: AmbientTheme.green
        }
    }
}
