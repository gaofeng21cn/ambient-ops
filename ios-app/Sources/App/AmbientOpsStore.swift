import Foundation
import Observation

enum AppConnectionState: Equatable {
    case demo
    case disconnected
    case loading
    case live
    case stale
    case error(String)
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case overview
    case network
    case load
    case pet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: "Overview"
        case .network: "Network"
        case .load: "Load"
        case .pet: "Pet"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .network: "network"
        case .load: "waveform.path.ecg.rectangle"
        case .pet: "bird"
        }
    }
}

struct LoadHistoryPoint: Identifiable, Hashable {
    let at: Date
    let tps: Double

    var id: Date { at }
}

enum LoadHistorySeries {
    static let window: TimeInterval = 30 * 60
    static let sampleInterval: TimeInterval = 4
    static let maximumPointCount = 360

    static func merged(
        existing: [LoadHistoryPoint],
        server: [MachineTPSHistoryPoint]?,
        sampleAt: Date,
        tps: Double
    ) -> [LoadHistoryPoint] {
        let serverPoints = (server ?? []).compactMap { point -> LoadHistoryPoint? in
            guard let at = point.atDate else { return nil }
            return LoadHistoryPoint(at: at, tps: max(0, point.tps))
        }
        var pointsByDate: [Date: LoadHistoryPoint] = [:]
        for point in existing {
            pointsByDate[point.at] = LoadHistoryPoint(at: point.at, tps: max(0, point.tps))
        }
        for point in serverPoints {
            pointsByDate[point.at] = point
        }
        var points = pointsByDate.values.sorted { $0.at < $1.at }

        if let last = points.last {
            let elapsed = sampleAt.timeIntervalSince(last.at)
            if elapsed == 0 {
                points[points.count - 1] = LoadHistoryPoint(at: sampleAt, tps: max(0, tps))
            } else if elapsed >= sampleInterval {
                points.append(LoadHistoryPoint(at: sampleAt, tps: max(0, tps)))
            }
        } else {
            points.append(LoadHistoryPoint(at: sampleAt, tps: max(0, tps)))
        }

        let cutoff = sampleAt.addingTimeInterval(-window)
        return Array(
            points
                .filter { $0.at >= cutoff && $0.at <= sampleAt }
                .suffix(maximumPointCount)
        )
    }

    static func coveredMinutes(_ points: [LoadHistoryPoint]) -> Int {
        guard let first = points.first?.at, let last = points.last?.at, last > first else { return 0 }
        return min(30, max(1, Int(ceil(last.timeIntervalSince(first) / 60))))
    }

    static func trendDomain(_ points: [LoadHistoryPoint]) -> ClosedRange<Double> {
        let values = points.map { max(0, $0.tps) }
        let maximum = values.max() ?? 0
        guard maximum > 0 else { return 0...1 }
        let minimum = values.min() ?? 0
        guard minimum > maximum * 0.15 else { return 0...(maximum / 0.92) }

        let observedSpan = maximum - minimum
        let span = max(observedSpan, maximum * 0.12, 1)
        let padding = span * 0.12
        let center = (minimum + maximum) / 2
        return max(0, center - span / 2 - padding)...(center + span / 2 + padding)
    }
}

@MainActor
@Observable
final class AmbientOpsStore {
    private enum Keys {
        static let demoMode = "ambient-ops.demo-mode"
        static let serverURL = "ambient-ops.server-url"
        static let selectedMachineID = "ambient-ops.selected-machine"
        static let selectedSourceID = "ambient-ops.selected-source"
    }

    var status: AmbientStatus
    var connectionState: AppConnectionState = .demo
    var serverAddress: String
    var selectedMachineID: String?
    var displayMode: DisplayMode = .load
    var discoveredServers: [DiscoveredServer] = []
    var isDiscovering = false
    var loadHistory: [String: [LoadHistoryPoint]] = [:]
    var networkHistory: [NetworkHistoryPoint] = []

    private let client = AmbientOpsClient()
    private let defaults: UserDefaults
    private let discovery: DiscoveryService
    private var refreshTask: Task<Void, Never>?
    private var automaticSelectionTask: Task<Void, Never>?
    private var startupReconnectTask: Task<Void, Never>?
    let liveActivity = LiveActivityController()

    init(
        defaults: UserDefaults = .standard,
        discovery: DiscoveryService? = nil,
        automaticallyConnect: Bool = true
    ) {
        self.defaults = defaults
        self.discovery = discovery ?? DiscoveryService()
        let initialDemo = defaults.object(forKey: Keys.demoMode) as? Bool ?? false
        serverAddress = defaults.string(forKey: Keys.serverURL) ?? ""
        selectedMachineID = defaults.string(forKey: Keys.selectedMachineID)
        status = initialDemo ? DemoFixtures.status() : .unavailable()

        self.discovery.onChange = { [weak self] servers in
            self?.handleDiscoveredServers(servers)
        }
        self.discovery.onError = { [weak self] message in
            guard let self else { return }
            self.isDiscovering = false
            if self.connectionState != .live && self.connectionState != .stale {
                self.connectionState = .error(message)
            }
        }

        if initialDemo {
            useDemoMode()
        } else if automaticallyConnect {
            useAutomaticSourceMode()
        } else {
            useLiveMode()
        }
    }

    var selectedMachine: MachineStatus? {
        status.focusedMachine(preferredID: selectedMachineID)
    }

    var isDemoMode: Bool {
        connectionState == .demo
    }

    var isFleet: Bool {
        status.effectiveProvider.isFleet
    }

    var providerLabel: String {
        isDemoMode ? "DEMO · FLEET" : "\(isFleet ? "FLEET" : "DIRECT") · \(status.effectiveProvider.name)"
    }

    var availableDisplayModes: [DisplayMode] {
        DisplayMode.allCases.filter { mode in
            mode != .network || status.capabilities.supportsNetwork
        }
    }

    var displayNetwork: NetworkStatus {
        guard !status.capabilities.networkHistory else { return status.network }
        return NetworkStatus(
            status: status.network.status,
            source: status.network.source,
            downloadMbps: status.network.downloadMbps,
            uploadMbps: status.network.uploadMbps,
            clients: status.network.clients,
            latencyMs: status.network.latencyMs,
            updatedAt: status.network.updatedAt,
            error: status.network.error,
            ageSeconds: status.network.ageSeconds,
            history: networkHistory
        )
    }

    func useDemoMode() {
        refreshTask?.cancel()
        automaticSelectionTask?.cancel()
        startupReconnectTask?.cancel()
        discovery.stop()
        isDiscovering = false
        status = DemoFixtures.status()
        networkHistory = []
        loadHistory = Dictionary(uniqueKeysWithValues: status.machines.map { machine in
            let points = (0..<60).map { index in
                let elapsed = Double(59 - index)
                let phase = Double(index) / 6 + Double(machine.machineId.hashValue % 11)
                return LoadHistoryPoint(
                    at: .now.addingTimeInterval(-elapsed * 30),
                    tps: max(0, machine.fiveMinutes.tps + sin(phase) * max(400, machine.oneMinute.tps * 0.14))
                )
            }
            return (machine.machineId, points)
        })
        connectionState = .demo
        persistSelection()
        defaults.set(true, forKey: Keys.demoMode)
        SharedSnapshotStore.saveSourceURL(nil)
        SharedSnapshotStore.save(status, focusedMachineID: selectedMachine?.machineId)
    }

    func useLiveMode() {
        refreshTask?.cancel()
        automaticSelectionTask?.cancel()
        startupReconnectTask?.cancel()
        discovery.stop()
        isDiscovering = false
        if status.demo {
            status = .unavailable()
            loadHistory = [:]
            networkHistory = []
        }
        connectionState = .disconnected
        defaults.set(false, forKey: Keys.demoMode)
    }

    func useAutomaticSourceMode() {
        useLiveMode()
        beginDiscovery()

        guard AmbientOpsClient.normalizedServerURL(serverAddress) != nil else { return }
        startupReconnectTask = Task { [weak self] in
            await self?.reconnectSavedSourceWhileDiscovering()
        }
    }

    func connect() async {
        useLiveMode()
        guard let serverURL = AmbientOpsClient.normalizedServerURL(serverAddress) else {
            connectionState = .error(AmbientOpsClientError.invalidServerURL.localizedDescription)
            return
        }
        connectionState = .loading
        defaults.set(serverAddress, forKey: Keys.serverURL)
        do {
            try await fetch(serverURL)
            scheduleRefresh(serverURL)
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        guard !isDemoMode,
              let serverURL = AmbientOpsClient.normalizedServerURL(serverAddress) else {
            return
        }
        do {
            try await fetch(serverURL)
        } catch {
            connectionState = .stale
        }
    }

    func startDiscovery() {
        useLiveMode()
        beginDiscovery()
    }

    private func beginDiscovery() {
        isDiscovering = true
        discoveredServers = []
        connectionState = .loading
        discovery.start()
    }

    func choose(_ server: DiscoveredServer) {
        startupReconnectTask?.cancel()
        automaticSelectionTask?.cancel()
        discovery.stop()
        isDiscovering = false
        defaults.set(server.id, forKey: Keys.selectedSourceID)
        serverAddress = server.url.absoluteString
        Task { await connect() }
    }

    func selectMachine(_ id: String?) {
        selectedMachineID = id
        persistSelection()
        SharedSnapshotStore.save(status, focusedMachineID: selectedMachine?.machineId)
    }

    func scenePhaseChanged(isActive: Bool) {
        if !isActive {
            refreshTask?.cancel()
        } else if !isDemoMode,
                  let serverURL = AmbientOpsClient.normalizedServerURL(serverAddress) {
            scheduleRefresh(serverURL)
        } else if !isDemoMode, !isDiscovering {
            startDiscovery()
        }
        if isActive {
            consumePendingRoute()
            liveActivity.refreshState()
        }
    }

    private func fetch(_ serverURL: URL) async throws {
        let fetched = try await client.fetchStatus(from: serverURL)
        status = fetched
        recordHistory(fetched)
        if displayMode == .network, !fetched.capabilities.supportsNetwork {
            displayMode = .load
        }
        if let selectedMachineID,
           !fetched.machines.contains(where: { $0.machineId == selectedMachineID }) {
            self.selectedMachineID = nil
        }
        connectionState = fetched.overallStatus == "live" ? .live : .stale
        persistSelection()
        SharedSnapshotStore.save(fetched, focusedMachineID: selectedMachine?.machineId)
        SharedSnapshotStore.saveSourceURL(serverURL)
        if let selectedMachine {
            Task { await liveActivity.update(status: fetched, machine: selectedMachine) }
        }
    }

    private func scheduleRefresh(_ serverURL: URL) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                do {
                    try await self.fetch(serverURL)
                } catch {
                    self.connectionState = .stale
                }
            }
        }
    }

    private func handleDiscoveredServers(_ servers: [DiscoveredServer]) {
        discoveredServers = servers
        guard isDiscovering, !servers.isEmpty else { return }

        let preferredID = defaults.string(forKey: Keys.selectedSourceID)
        if let preferredID,
           let preferred = servers.first(where: { $0.id == preferredID }) {
            choose(preferred)
            return
        }

        automaticSelectionTask?.cancel()
        automaticSelectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, self.isDiscovering else { return }
            if let source = SourceSelectionPolicy.automaticSource(
                from: self.discoveredServers,
                preferredID: preferredID
            ) {
                self.choose(source)
            }
        }
    }

    private func persistSelection() {
        defaults.set(selectedMachineID, forKey: Keys.selectedMachineID)
    }

    private func reconnectSavedSourceWhileDiscovering() async {
        guard let serverURL = AmbientOpsClient.normalizedServerURL(serverAddress) else { return }
        do {
            try Task.checkCancellation()
            try await fetch(serverURL)
            try Task.checkCancellation()
            scheduleRefresh(serverURL)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, discoveredServers.isEmpty else { return }
            connectionState = .error(error.localizedDescription)
        }
    }

    private func recordHistory(_ snapshot: AmbientStatus) {
        let now = snapshot.generatedDate ?? .now
        let cutoff = now.addingTimeInterval(-LoadHistorySeries.window)
        for machine in snapshot.machines {
            loadHistory[machine.machineId] = LoadHistorySeries.merged(
                existing: loadHistory[machine.machineId, default: []],
                server: machine.tpsHistory,
                sampleAt: machine.generatedDate ?? now,
                tps: machine.oneMinute.tps
            )
        }
        guard
            !snapshot.capabilities.networkHistory,
            let download = snapshot.network.downloadMbps,
            let upload = snapshot.network.uploadMbps
        else { return }
        let sampledAt = snapshot.network.updatedAt
            .flatMap(AmbientISO8601.date(from:)) ?? now
        if networkHistory.last?.atDate.map({ sampledAt.timeIntervalSince($0) >= 1 }) ?? true {
            networkHistory.append(
                NetworkHistoryPoint(
                    at: AmbientISO8601.string(from: sampledAt),
                    downloadMbps: download,
                    uploadMbps: upload
                )
            )
        }
        networkHistory = Array(
            networkHistory
                .filter { ($0.atDate ?? .distantPast) >= cutoff }
                .suffix(360)
        )
    }

    private func consumePendingRoute() {
        guard let defaults = UserDefaults(suiteName: SharedSnapshotStore.appGroup),
              defaults.string(forKey: "pending-route") == "load" else {
            return
        }
        defaults.removeObject(forKey: "pending-route")
        displayMode = .load
    }
}
