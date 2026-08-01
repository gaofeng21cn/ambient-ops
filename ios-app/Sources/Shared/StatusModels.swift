import Foundation

struct AmbientStatus: Codable, Hashable, Sendable {
    let schemaVersion: Int
    var productName: String? = nil
    let serverVersion: String
    let instanceId: String
    let generatedAt: String
    let demo: Bool
    let site: SiteStatus
    let overallStatus: String
    let provider: StatusProvider?
    let capabilities: ServerCapabilities
    let network: NetworkStatus
    let codex: CodexStatus
    let machines: [MachineStatus]

    var generatedDate: Date? {
        AmbientISO8601.date(from: generatedAt)
    }

    var effectiveProvider: StatusProvider {
        if let provider { return provider }
        return StatusProvider(
            kind: "gateway",
            scope: "fleet",
            id: instanceId,
            name: site.name
        )
    }

    func focusedMachine(preferredID: String?) -> MachineStatus? {
        if let preferredID,
           let preferred = machines.first(where: { $0.machineId == preferredID }) {
            return preferred
        }
        return machines.sorted {
            if $0.status == "live", $1.status != "live" { return true }
            if $0.status != "live", $1.status == "live" { return false }
            return $0.oneMinute.tps > $1.oneMinute.tps
        }.first
    }

    static func unavailable(now: Date = .now) -> AmbientStatus {
        AmbientStatus(
            schemaVersion: 1,
            serverVersion: "—",
            instanceId: "",
            generatedAt: AmbientISO8601.string(from: now),
            demo: false,
            site: SiteStatus(name: "Ambient Ops", timeZone: TimeZone.current.identifier),
            overallStatus: "error",
            provider: nil,
            capabilities: ServerCapabilities(
                loadVisualState: false,
                networkHistory: false,
                machineHistory: false,
                pets: false,
                liveActivityPush: false,
                network: false,
                persistentHistory: false,
                webDisplay: false
            ),
            network: NetworkStatus(
                status: "error",
                source: nil,
                downloadMbps: nil,
                uploadMbps: nil,
                clients: nil,
                latencyMs: nil,
                updatedAt: nil,
                error: nil,
                ageSeconds: nil,
                history: []
            ),
            codex: CodexStatus(
                status: "error",
                oneMinuteTps: 0,
                fiveMinuteTps: 0,
                cachePercent: 0,
                activeSessions: 0,
                cpuPercent: nil,
                cpuReportedMachineCount: 0,
                memoryPercent: nil,
                memoryReportedMachineCount: 0,
                machineCount: 0,
                liveMachineCount: 0,
                staleMachineCount: 0
            ),
            machines: []
        )
    }
}

struct StatusProvider: Codable, Hashable, Sendable {
    let kind: String
    let scope: String
    let id: String
    let name: String
    var productName: String? = nil

    var isFleet: Bool { scope == "fleet" }
}

struct SiteStatus: Codable, Hashable, Sendable {
    let name: String
    let timeZone: String
}

struct ServerCapabilities: Codable, Hashable, Sendable {
    let loadVisualState: Bool
    let networkHistory: Bool
    let machineHistory: Bool?
    let pets: Bool
    let liveActivityPush: Bool
    let network: Bool?
    let persistentHistory: Bool?
    let webDisplay: Bool?

    var supportsNetwork: Bool {
        network ?? networkHistory
    }

    var supportsPersistentHistory: Bool {
        persistentHistory ?? networkHistory
    }
}

struct NetworkStatus: Codable, Hashable, Sendable {
    let status: String
    let source: String?
    let downloadMbps: Double?
    let uploadMbps: Double?
    let clients: Double?
    let latencyMs: Double?
    let updatedAt: String?
    let error: String?
    let ageSeconds: Double?
    let history: [NetworkHistoryPoint]
}

struct NetworkHistoryPoint: Codable, Hashable, Sendable, Identifiable {
    let at: String
    let downloadMbps: Double
    let uploadMbps: Double

    var id: String { at }
    var atDate: Date? { AmbientISO8601.date(from: at) }
}

struct CodexStatus: Codable, Hashable, Sendable {
    let status: String
    let oneMinuteTps: Double
    let fiveMinuteTps: Double
    let cachePercent: Double
    let activeSessions: Double
    let cpuPercent: Double?
    let cpuReportedMachineCount: Double?
    let memoryPercent: Double?
    let memoryReportedMachineCount: Double?
    let machineCount: Double
    let liveMachineCount: Double
    let staleMachineCount: Double
}

struct MachineStatus: Codable, Hashable, Sendable, Identifiable {
    let machineId: String
    let machineName: String
    let platform: String
    let generatedAt: String
    let receivedAt: String?
    let reportedStatus: String?
    let error: String?
    let oneMinute: TokenWindow
    let fiveMinutes: TokenWindow
    let tpsHistory: [MachineTPSHistoryPoint]?
    let activeSessions: Double
    let cpuPercent: Double?
    let memoryPercent: Double?
    let pet: PetStatus?
    let status: String
    let ageSeconds: Double?
    let cachePercent: Double
    let loadVisualState: LoadVisualState
    var oplFleet: OPLFleetAgentStatus? = nil

    var id: String { machineId }
    var generatedDate: Date? { AmbientISO8601.date(from: generatedAt) }
}

struct OPLFleetAgentStatus: Codable, Hashable, Sendable {
    let schema: String
    let product: String
    let stableNodeID: String
    let agentVersion: String
    let modes: [String]
    let capabilities: [String]
    let authority: String
}

struct MachineTPSHistoryPoint: Codable, Hashable, Sendable, Identifiable {
    let at: String
    let tps: Double

    var id: String { at }
    var atDate: Date? { AmbientISO8601.date(from: at) }
}

struct TokenWindow: Codable, Hashable, Sendable {
    let tps: Double
    let inputTokens: Double?
    let outputTokens: Double?
    let cachedInputTokens: Double?
    let reasoningOutputTokens: Double?
    let requests: Double?
}

struct PetStatus: Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let spriteVersionNumber: Int
    let assetHash: String?
    let state: String
    let stateSince: String?
    let assetUrl: String?
}

struct LoadVisualState: Codable, Hashable, Sendable {
    let modelVersion: Int?
    let state: String
    let label: String
    let score: Double
    let constrained: Bool
    let activity: Double
    let parallel: Double
    let tempo: Double
    let travelMs: Double
    let clusterCount: Int
    let taskDensity: Double
    let pressure: Double
    let queueDepth: Double
    let heat: Double

    var normalizedScore: Double { score.clamped(to: 0...1) }

    init(
        modelVersion: Int? = 1,
        state: String,
        label: String,
        score: Double,
        constrained: Bool,
        activity: Double,
        parallel: Double,
        tempo: Double,
        travelMs: Double,
        clusterCount: Int,
        taskDensity: Double,
        pressure: Double,
        queueDepth: Double,
        heat: Double
    ) {
        self.modelVersion = modelVersion
        self.state = state
        self.label = label
        self.score = score
        self.constrained = constrained
        self.activity = activity
        self.parallel = parallel
        self.tempo = tempo
        self.travelMs = travelMs
        self.clusterCount = clusterCount
        self.taskDensity = taskDensity
        self.pressure = pressure
        self.queueDepth = queueDepth
        self.heat = heat
    }
}

enum LoadStatePalette {
    static func label(for state: String) -> String {
        switch state {
        case "quiet": "QUIET"
        case "active": "ACTIVE"
        case "heavy": "HEAVY"
        case "constrained": "CONSTRAINED"
        default: state.uppercased()
        }
    }

    static func compactLabel(for state: String) -> String {
        switch state {
        case "constrained": "LIMITED"
        default: label(for: state)
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

enum AmbientISO8601 {
    static func date(from value: String) -> Date? {
        formatter().date(from: value)
    }

    static func string(from date: Date) -> String {
        formatter().string(from: date)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
