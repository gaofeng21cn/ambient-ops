import Foundation

struct AmbientStatus: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let serverVersion: String
    let instanceId: String
    let generatedAt: String
    let demo: Bool
    let site: SiteStatus
    let overallStatus: String
    let capabilities: ServerCapabilities
    let network: NetworkStatus
    let codex: CodexStatus
    let machines: [MachineStatus]

    var generatedDate: Date? {
        AmbientISO8601.date(from: generatedAt)
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
}

struct SiteStatus: Codable, Hashable, Sendable {
    let name: String
    let timeZone: String
}

struct ServerCapabilities: Codable, Hashable, Sendable {
    let loadVisualState: Bool
    let networkHistory: Bool
    let pets: Bool
    let liveActivityPush: Bool
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
    let activeSessions: Double
    let cpuPercent: Double?
    let memoryPercent: Double?
    let pet: PetStatus?
    let status: String
    let ageSeconds: Double?
    let cachePercent: Double
    let loadVisualState: LoadVisualState

    var id: String { machineId }
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
