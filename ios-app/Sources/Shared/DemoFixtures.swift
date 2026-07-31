import Foundation

enum DemoFixtures {
    static func status(now: Date = .now) -> AmbientStatus {
        let machines = [
            machine(
                id: "studio",
                name: "Studio",
                platform: "macOS",
                tps: 56_840,
                fiveMinuteTps: 48_120,
                sessions: 11,
                cpu: 94,
                memory: 68,
                cache: 87,
                state: .constrained,
                now: now,
                pet: PetStatus(
                    id: "ledger-owl",
                    displayName: "Ledger Owl",
                    spriteVersionNumber: 1,
                    assetHash: nil,
                    state: "running",
                    stateSince: timestamp(now.addingTimeInterval(-76)),
                    assetUrl: "/pets/ledger-owl/spritesheet.webp"
                )
            ),
            machine(
                id: "workstation",
                name: "Workstation",
                platform: "Windows",
                tps: 34_760,
                fiveMinuteTps: 29_400,
                sessions: 7,
                cpu: 71,
                memory: 54,
                cache: 81,
                state: .heavy,
                now: now
            ),
            machine(
                id: "notebook",
                name: "Notebook",
                platform: "macOS",
                tps: 9_240,
                fiveMinuteTps: 7_980,
                sessions: 3,
                cpu: nil,
                memory: nil,
                cache: 74,
                state: .active,
                now: now.addingTimeInterval(-18)
            ),
            machine(
                id: "lab-mini",
                name: "Lab Mini",
                platform: "Linux",
                tps: 0,
                fiveMinuteTps: 820,
                sessions: 0,
                cpu: 19,
                memory: 31,
                cache: 68,
                state: .quiet,
                status: "stale",
                now: now.addingTimeInterval(-124)
            ),
        ]

        return AmbientStatus(
            schemaVersion: 1,
            serverVersion: "demo",
            instanceId: "ambient-ops-demo",
            generatedAt: timestamp(now),
            demo: true,
            site: SiteStatus(name: "Ambient Ops Demo", timeZone: "Asia/Shanghai"),
            overallStatus: "live",
            provider: StatusProvider(
                kind: "gateway",
                scope: "fleet",
                id: "ambient-ops-demo",
                name: "Ambient Ops Demo"
            ),
            capabilities: ServerCapabilities(
                loadVisualState: true,
                networkHistory: true,
                machineHistory: true,
                pets: true,
                liveActivityPush: false,
                network: true,
                persistentHistory: true,
                webDisplay: true
            ),
            network: NetworkStatus(
                status: "live",
                source: "demo",
                downloadMbps: 842.6,
                uploadMbps: 126.4,
                clients: 63,
                latencyMs: 8,
                updatedAt: timestamp(now),
                error: nil,
                ageSeconds: 0,
                history: networkHistory(now: now)
            ),
            codex: CodexStatus(
                status: "live",
                oneMinuteTps: 100_840,
                fiveMinuteTps: 86_320,
                cachePercent: 83,
                activeSessions: 21,
                cpuPercent: 83,
                cpuReportedMachineCount: 3,
                memoryPercent: 51,
                memoryReportedMachineCount: 3,
                machineCount: 4,
                liveMachineCount: 3,
                staleMachineCount: 1
            ),
            machines: machines
        )
    }

    private enum DemoLoadState {
        case quiet
        case active
        case heavy
        case constrained

        var visual: LoadVisualState {
            switch self {
            case .quiet:
                LoadVisualState(
                    state: "quiet", label: "QUIET", score: 0.04, constrained: false,
                    activity: 0, parallel: 0, tempo: 0.2, travelMs: 4_800,
                    clusterCount: 0, taskDensity: 0, pressure: 0, queueDepth: 0, heat: 0
                )
            case .active:
                LoadVisualState(
                    state: "active", label: "ACTIVE", score: 0.34, constrained: false,
                    activity: 0.42, parallel: 0.38, tempo: 1.02, travelMs: 2_120,
                    clusterCount: 2, taskDensity: 0.51, pressure: 0, queueDepth: 0, heat: 0.05
                )
            case .heavy:
                LoadVisualState(
                    state: "heavy", label: "HEAVY", score: 0.72, constrained: false,
                    activity: 0.78, parallel: 0.64, tempo: 1.82, travelMs: 1_280,
                    clusterCount: 3, taskDensity: 0.82, pressure: 0.09, queueDepth: 0.08, heat: 0.18
                )
            case .constrained:
                LoadVisualState(
                    state: "constrained", label: "CONSTRAINED", score: 0.91, constrained: true,
                    activity: 0.93, parallel: 0.82, tempo: 2.32, travelMs: 860,
                    clusterCount: 4, taskDensity: 0.97, pressure: 0.81, queueDepth: 0.86, heat: 0.91
                )
            }
        }
    }

    private static func machine(
        id: String,
        name: String,
        platform: String,
        tps: Double,
        fiveMinuteTps: Double,
        sessions: Double,
        cpu: Double?,
        memory: Double?,
        cache: Double,
        state: DemoLoadState,
        status: String = "live",
        now: Date,
        pet: PetStatus? = nil
    ) -> MachineStatus {
        MachineStatus(
            machineId: id,
            machineName: name,
            platform: platform,
            generatedAt: timestamp(now),
            receivedAt: timestamp(now),
            reportedStatus: "live",
            error: nil,
            oneMinute: TokenWindow(
                tps: tps,
                inputTokens: tps * 9.6,
                outputTokens: tps * 1.8,
                cachedInputTokens: tps * 7.2,
                reasoningOutputTokens: tps * 0.42,
                requests: max(0, sessions * 2)
            ),
            fiveMinutes: TokenWindow(
                tps: fiveMinuteTps,
                inputTokens: nil,
                outputTokens: nil,
                cachedInputTokens: nil,
                reasoningOutputTokens: nil,
                requests: nil
            ),
            tpsHistory: nil,
            activeSessions: sessions,
            cpuPercent: cpu,
            memoryPercent: memory,
            pet: pet,
            status: status,
            ageSeconds: status == "stale" ? 124 : 0,
            cachePercent: cache,
            loadVisualState: state.visual
        )
    }

    private static func networkHistory(now: Date) -> [NetworkHistoryPoint] {
        (0..<60).map { index in
            let elapsed = Double(59 - index)
            let phase = Double(index) / 5.8
            return NetworkHistoryPoint(
                at: timestamp(now.addingTimeInterval(-elapsed * 30)),
                downloadMbps: 690 + sin(phase) * 145 + sin(phase * 2.31) * 52,
                uploadMbps: 108 + cos(phase * 0.82) * 22 + sin(phase * 1.77) * 9
            )
        }
    }

    private static func timestamp(_ date: Date) -> String {
        AmbientISO8601.string(from: date)
    }
}
