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

enum DisplayScope: String, CaseIterable, Identifiable {
    case fleet
    case host

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fleet: "Fleet"
        case .host: "Host"
        }
    }

    var systemImage: String {
        switch self {
        case .fleet: "network"
        case .host: "desktopcomputer"
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

    static func fleetHistory(_ histories: [String: [LoadHistoryPoint]]) -> [LoadHistoryPoint] {
        var totalsByBucket: [Date: Double] = [:]
        for point in histories.values.flatMap({ $0 }) {
            let bucket = Date(
                timeIntervalSince1970: floor(point.at.timeIntervalSince1970 / sampleInterval) * sampleInterval
            )
            totalsByBucket[bucket, default: 0] += max(0, point.tps)
        }
        return Array(
            totalsByBucket
                .map { LoadHistoryPoint(at: $0.key, tps: $0.value) }
                .sorted { $0.at < $1.at }
                .suffix(maximumPointCount)
        )
    }

}

struct FleetLoadNode: Identifiable, Hashable {
    let id: String
    let name: String
    let platform: String
    let status: String
    let tps: Double
    let sessions: Double
    let cpuPercent: Double?
    let intensity: Double
    let travelMs: Double

    var isWorking: Bool { status == "live" && (tps > 0 || sessions > 0) }
    var isPressured: Bool { status == "live" && (cpuPercent ?? 0) >= 82 }
}

struct FleetLoadPresentation: Hashable {
    let visual: LoadVisualState
    let oneMinuteTps: Double
    let fiveMinuteTps: Double
    let activeSessions: Double
    let cpuPercent: Double?
    let cpuReportedNodeCount: Int
    let totalNodeCount: Int
    let liveNodeCount: Int
    let workingNodeCount: Int
    let nodes: [FleetLoadNode]

    init(status: AmbientStatus) {
        let liveMachines = status.machines.filter { $0.status == "live" }
        let liveCount = liveMachines.count
        let reportedLiveCount = max(liveCount, Int(status.codex.liveMachineCount))
        let liveDivisor = Double(max(1, reportedLiveCount))
        let workingCount = liveMachines.filter {
            $0.oneMinute.tps > 0 || $0.activeSessions > 0
        }.count
        let averageTPS = max(0, status.codex.oneMinuteTps) / liveDivisor
        let averageSessions = max(0, status.codex.activeSessions) / liveDivisor
        let cpu = status.codex.cpuPercent
        let tpsIntensity = sqrt(averageTPS / 60_000).clamped(to: 0...1)
        let sessionIntensity = (averageSessions / 12).clamped(to: 0...1)
        let cpuIntensity = cpu.map { ($0 / 100).clamped(to: 0...1) }
        let baseScore = cpuIntensity.map {
            tpsIntensity * 0.56 + sessionIntensity * 0.22 + $0 * 0.22
        } ?? (tpsIntensity * 0.72 + sessionIntensity * 0.28)
        let engagement = (Double(workingCount) / liveDivisor).clamped(to: 0...1)
        let score = (baseScore * 0.78 + engagement * 0.22).clamped(to: 0...1)
        let hasWork = status.codex.oneMinuteTps > 0 || status.codex.activeSessions > 0
        let constrained = hasWork && (cpu ?? 0) >= 88 && baseScore >= 0.35
        let pressure = cpu.map { (($0 - 68) / 32).clamped(to: 0...1) } ?? 0
        let parallel = hasWork ? sqrt(max(0, status.codex.activeSessions) / 18).clamped(to: 0...1) : 0
        let tempo = hasWork
            ? (0.45 + score * 1.35 + sqrt(max(0, status.codex.oneMinuteTps) / 90_000) * 0.7)
                .clamped(to: 0.45...2.5)
            : 0.2
        let travelMs = hasWork
            ? ((3.1 - tpsIntensity * 1.8 - sessionIntensity * 0.35) * 1_000)
                .clamped(to: 800...3_100)
            : 4_800
        let activity = hasWork ? (score * 0.72 + parallel * 0.28).clamped(to: 0...1) : 0
        let queueDepth = constrained
            ? (0.24 + pressure * 0.76).clamped(to: 0.24...1)
            : (max(0, score - 0.68) * 0.7).clamped(to: 0...0.25)
        let state = constrained ? "constrained" : score >= 0.45 ? "heavy" : score >= 0.18 ? "active" : "quiet"

        visual = LoadVisualState(
            state: state,
            label: LoadStatePalette.label(for: state),
            score: score,
            constrained: constrained,
            activity: activity,
            parallel: parallel,
            tempo: tempo,
            travelMs: travelMs,
            clusterCount: hasWork ? max(1, min(4, Int((1 + parallel * 3).rounded()))) : 0,
            taskDensity: hasWork
                ? (0.16 + activity * 0.68 + parallel * 0.16).clamped(to: 0.16...1)
                : 0,
            pressure: pressure,
            queueDepth: queueDepth,
            heat: (pressure * 0.9 + activity * 0.12).clamped(to: 0...1)
        )
        oneMinuteTps = max(0, status.codex.oneMinuteTps)
        fiveMinuteTps = max(0, status.codex.fiveMinuteTps)
        activeSessions = max(0, status.codex.activeSessions)
        cpuPercent = cpu
        cpuReportedNodeCount = Int(status.codex.cpuReportedMachineCount ?? 0)
        totalNodeCount = max(status.machines.count, Int(status.codex.machineCount))
        liveNodeCount = reportedLiveCount
        workingNodeCount = workingCount
        nodes = Self.visualNodes(status.machines)
    }

    private static func visualNodes(_ machines: [MachineStatus]) -> [FleetLoadNode] {
        machines
            .sorted {
                let leftRank = statusRank($0.status)
                let rightRank = statusRank($1.status)
                if leftRank != rightRank { return leftRank < rightRank }
                let nameOrder = $0.machineName.localizedCaseInsensitiveCompare($1.machineName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return $0.machineId < $1.machineId
            }
            .prefix(6)
            .map { machine in
                let tps = max(0, machine.oneMinute.tps)
                let sessions = max(0, machine.activeSessions)
                let tpsIntensity = sqrt(tps / 60_000).clamped(to: 0...1)
                let sessionIntensity = (sessions / 8).clamped(to: 0...1)
                let hasWork = machine.status == "live" && (tps > 0 || sessions > 0)
                return FleetLoadNode(
                    id: machine.machineId,
                    name: machine.machineName,
                    platform: machine.platform,
                    status: machine.status,
                    tps: tps,
                    sessions: sessions,
                    cpuPercent: machine.cpuPercent,
                    intensity: hasWork
                        ? (tpsIntensity * 0.75 + sessionIntensity * 0.25).clamped(to: 0...1)
                        : 0,
                    travelMs: hasWork
                        ? (3_200 - tpsIntensity * 2_400).clamped(to: 800...3_200)
                        : 4_800
                )
            }
    }

    private static func statusRank(_ status: String) -> Int {
        switch status {
        case "live": 0
        case "stale": 1
        case "error": 2
        default: 3
        }
    }
}

@MainActor
@Observable
final class OPLFleetCockpitStore {
    private enum Keys {
        static let demoMode = "opl-fleet-cockpit.demo-mode"
        static let serverURL = "opl-fleet-cockpit.server-url"
        static let selectedMachineID = "opl-fleet-cockpit.selected-machine"
        static let selectedSourceID = "opl-fleet-cockpit.selected-source"
        static let displayScope = "opl-fleet-cockpit.display-scope"
    }

    var status: AmbientStatus
    var connectionState: AppConnectionState = .demo
    var serverAddress: String
    var selectedMachineID: String?
    private var preferredDisplayScope: DisplayScope
    var displayMode: DisplayMode = .load
    var discoveredServers: [DiscoveredServer] = []
    var isDiscovering = false
    var loadHistory: [String: [LoadHistoryPoint]] = [:]
    var networkHistory: [NetworkHistoryPoint] = []

    private let client = OPLFleetCockpitClient()
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
        preferredDisplayScope = defaults.string(forKey: Keys.displayScope)
            .flatMap(DisplayScope.init(rawValue:)) ?? .fleet
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

    var displayScope: DisplayScope {
        get { isFleet ? preferredDisplayScope : .host }
        set {
            preferredDisplayScope = isFleet ? newValue : .host
            defaults.set(preferredDisplayScope.rawValue, forKey: Keys.displayScope)
        }
    }

    var fleetLoadPresentation: FleetLoadPresentation {
        FleetLoadPresentation(status: status)
    }

    var fleetLoadHistory: [LoadHistoryPoint] {
        LoadHistorySeries.fleetHistory(loadHistory)
    }

    var providerLabel: String {
        isDemoMode ? "DEMO · FLEET COCKPIT" : "\(isFleet ? "GATEWAY" : "AGENT") · \(status.effectiveProvider.name)"
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

        guard OPLFleetCockpitClient.normalizedServerURL(serverAddress) != nil else { return }
        startupReconnectTask = Task { [weak self] in
            await self?.reconnectSavedSourceWhileDiscovering()
        }
    }

    func connect() async {
        useLiveMode()
        guard let serverURL = OPLFleetCockpitClient.normalizedServerURL(serverAddress) else {
            connectionState = .error(OPLFleetCockpitClientError.invalidServerURL.localizedDescription)
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
              let serverURL = OPLFleetCockpitClient.normalizedServerURL(serverAddress) else {
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
        if id != nil, isFleet {
            displayScope = .host
        }
        persistSelection()
        SharedSnapshotStore.save(status, focusedMachineID: selectedMachine?.machineId)
    }

    func scenePhaseChanged(isActive: Bool) {
        if !isActive {
            refreshTask?.cancel()
        } else if !isDemoMode,
                  let serverURL = OPLFleetCockpitClient.normalizedServerURL(serverAddress) {
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
        guard let serverURL = OPLFleetCockpitClient.normalizedServerURL(serverAddress) else { return }
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
