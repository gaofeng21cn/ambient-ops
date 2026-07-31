#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct LoadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let machineName: String
        let state: String
        let score: Double
        let tps: Double
        let activeSessions: Double
        let cpuPercent: Double?
        let visual: LoadVisualState?
        let updatedAt: Date

        init(machine: MachineStatus, updatedAt: Date = .now) {
            machineName = machine.machineName
            state = machine.loadVisualState.state
            score = machine.loadVisualState.normalizedScore
            tps = machine.oneMinute.tps
            activeSessions = machine.activeSessions
            cpuPercent = machine.cpuPercent
            visual = machine.loadVisualState
            self.updatedAt = updatedAt
        }
    }

    let instanceId: String
    let siteName: String
    let machineId: String
}
#endif
