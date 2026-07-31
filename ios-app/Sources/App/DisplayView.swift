import Charts
import SwiftUI

struct DisplayView: View {
    @Bindable var store: AmbientOpsStore

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let compactHeader = proxy.size.width < 900
            VStack(spacing: 0) {
                displayHeader(compact: compactHeader)
                Divider().overlay(AmbientTheme.line)
                Group {
                    switch store.displayMode {
                    case .overview:
                        OverviewDisplay(status: store.status, landscape: landscape)
                    case .network:
                        NetworkDisplay(network: store.status.network, landscape: landscape)
                    case .load:
                        if let machine = store.selectedMachine {
                            LoadDisplay(
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
                                serverURL: AmbientOpsClient.normalizedServerURL(store.serverAddress),
                                landscape: landscape
                            )
                        } else {
                            unavailable
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AmbientTheme.background)
        }
    }

    private func displayHeader(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
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
                        .font(.caption2)
                }
                .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 6)

            Picker("Display mode", selection: $store.displayMode) {
                ForEach(DisplayMode.allCases) { mode in
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
            .frame(maxWidth: compact ? 280 : 360)

            Spacer(minLength: 6)
            StatusPill(status: store.status.overallStatus)
        }
        .padding(.horizontal, compact ? 12 : 16)
        .frame(height: compact ? 44 : 54)
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

private struct LoadDisplay: View {
    let machine: MachineStatus
    let history: [LoadHistoryPoint]
    let landscape: Bool

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: 0) {
                    stage
                    metrics
                        .frame(width: 252)
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
        ZStack(alignment: .topLeading) {
            LoadSceneView(visual: machine.loadVisualState)
            VStack(alignment: .leading, spacing: 4) {
                Text("DEVELOPMENT LOAD")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AmbientTheme.muted)
                Text(LoadStatePalette.label(for: machine.loadVisualState.state))
                    .font(.system(size: landscape ? 35 : 29, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmbientTheme.statusColor(machine.loadVisualState.state))
            }
            .padding(14)
        }
        .clipped()
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
            .padding(14)
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(AmbientTheme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(value == "N/A" ? AmbientTheme.muted : .primary)
            Text(unit)
                .font(.system(size: 8))
                .foregroundStyle(AmbientTheme.muted)
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("30 MIN TREND")
                Spacer()
                Text(history.count > 1 ? "LOCAL" : "COLLECTING")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AmbientTheme.muted)

            Chart(history) { point in
                LineMark(
                    x: .value("Time", point.at),
                    y: .value("TPS", point.tps)
                )
                .foregroundStyle(AmbientTheme.green)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: landscape ? 58 : 46)
        }
        .padding(14)
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
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(AmbientTheme.muted)
        }
        .padding(14)
    }
}

private struct OverviewDisplay: View {
    let status: AmbientStatus
    let landscape: Bool

    var body: some View {
        let content = [
            ("CODEX", MetricFormat.tps(status.codex.oneMinuteTps), "TPS", AmbientTheme.green),
            ("DOWNLOAD", MetricFormat.decimal(status.network.downloadMbps), "Mbps", AmbientTheme.blue),
            ("UPLOAD", MetricFormat.decimal(status.network.uploadMbps), "Mbps", AmbientTheme.purple),
        ]
        Group {
            if landscape {
                HStack(spacing: 1) {
                    ForEach(Array(content.enumerated()), id: \.offset) { _, item in
                        hero(item)
                    }
                }
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(content.enumerated()), id: \.offset) { _, item in
                        hero(item)
                    }
                }
            }
        }
        .padding(1)
        .background(AmbientTheme.line)
    }

    private func hero(_ item: (String, String, String, Color)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.0)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmbientTheme.muted)
            Spacer()
            Text(item.1)
                .font(.system(size: landscape ? 54 : 44, weight: .semibold, design: .rounded))
                .foregroundStyle(item.3)
                .minimumScaleFactor(0.58)
                .lineLimit(1)
            Text(item.2)
                .font(.caption)
                .foregroundStyle(AmbientTheme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AmbientTheme.surface)
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

    var body: some View {
        Group {
            if let pet = machine.pet {
                ZStack(alignment: .topLeading) {
                    PetSceneView(pet: pet, serverURL: serverURL)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(pet.displayName)
                            .font(.title2.weight(.semibold))
                        Text(pet.state.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AmbientTheme.statusColor(pet.state))
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "No companion configured",
                    systemImage: "bird",
                    description: Text("\(machine.machineName) is reporting normally without a Codex Pet.")
                )
            }
        }
        .background(AmbientTheme.background)
    }
}
