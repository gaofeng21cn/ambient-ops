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

@MainActor
@Observable
final class AmbientOpsStore {
    private enum Keys {
        static let demoMode = "ambient-ops.demo-mode"
        static let serverURL = "ambient-ops.server-url"
        static let selectedMachineID = "ambient-ops.selected-machine"
    }

    var status: AmbientStatus
    var connectionState: AppConnectionState = .demo
    var serverAddress: String
    var selectedMachineID: String?
    var displayMode: DisplayMode = .load
    var discoveredServers: [DiscoveredServer] = []
    var isDiscovering = false
    var hasExplainedLocalNetwork = false
    var loadHistory: [String: [LoadHistoryPoint]] = [:]

    private let client = AmbientOpsClient()
    private let discovery = DiscoveryService()
    private var refreshTask: Task<Void, Never>?
    let liveActivity = LiveActivityController()

    init() {
        let defaults = UserDefaults.standard
        let initialDemo = defaults.object(forKey: Keys.demoMode) as? Bool ?? true
        serverAddress = defaults.string(forKey: Keys.serverURL) ?? ""
        selectedMachineID = defaults.string(forKey: Keys.selectedMachineID)
        status = initialDemo ? DemoFixtures.status() : .unavailable()

        discovery.onChange = { [weak self] servers in
            self?.discoveredServers = servers
        }
        discovery.onError = { [weak self] message in
            self?.isDiscovering = false
            self?.connectionState = .error(message)
        }

        if initialDemo {
            useDemoMode()
        } else if AmbientOpsClient.normalizedServerURL(serverAddress) != nil {
            Task { await connect() }
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

    func useDemoMode() {
        refreshTask?.cancel()
        discovery.stop()
        isDiscovering = false
        status = DemoFixtures.status()
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
        UserDefaults.standard.set(true, forKey: Keys.demoMode)
        SharedSnapshotStore.save(status, focusedMachineID: selectedMachine?.machineId)
    }

    func useLiveMode() {
        refreshTask?.cancel()
        discovery.stop()
        isDiscovering = false
        if status.demo {
            status = .unavailable()
            loadHistory = [:]
        }
        connectionState = .disconnected
        UserDefaults.standard.set(false, forKey: Keys.demoMode)
    }

    func connect() async {
        useLiveMode()
        guard let serverURL = AmbientOpsClient.normalizedServerURL(serverAddress) else {
            connectionState = .error(AmbientOpsClientError.invalidServerURL.localizedDescription)
            return
        }
        connectionState = .loading
        UserDefaults.standard.set(serverAddress, forKey: Keys.serverURL)
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
        hasExplainedLocalNetwork = true
        isDiscovering = true
        discoveredServers = []
        connectionState = .loading
        discovery.start()
    }

    func choose(_ server: DiscoveredServer) {
        discovery.stop()
        isDiscovering = false
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
        if let selectedMachineID,
           !fetched.machines.contains(where: { $0.machineId == selectedMachineID }) {
            self.selectedMachineID = nil
        }
        connectionState = fetched.overallStatus == "live" ? .live : .stale
        persistSelection()
        SharedSnapshotStore.save(fetched, focusedMachineID: selectedMachine?.machineId)
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

    private func persistSelection() {
        let defaults = UserDefaults.standard
        defaults.set(selectedMachineID, forKey: Keys.selectedMachineID)
    }

    private func recordHistory(_ snapshot: AmbientStatus) {
        let now = snapshot.generatedDate ?? .now
        let cutoff = now.addingTimeInterval(-30 * 60)
        for machine in snapshot.machines {
            var points = loadHistory[machine.machineId, default: []]
            if points.last.map({ now.timeIntervalSince($0.at) >= 4 }) ?? true {
                points.append(LoadHistoryPoint(at: now, tps: machine.oneMinute.tps))
            }
            loadHistory[machine.machineId] = Array(points.filter { $0.at >= cutoff }.suffix(360))
        }
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
