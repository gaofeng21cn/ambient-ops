import XCTest
@testable import AmbientOps

final class AmbientOpsTests: XCTestCase {
    func testTPSFormattingMatchesTheWebDisplay() {
        XCTAssertEqual(MetricFormat.tps(56_840), "56,840")
        XCTAssertEqual(MetricFormat.tps(2_329.4), "2,329")
        XCTAssertEqual(MetricFormat.tps(98.75), "98.8")
        XCTAssertEqual(MetricFormat.tps(0), "0")
    }

    func testPetPlaybackUsesOnlyPopulatedFrames() {
        let idle = PetAnimationPlayback.forState("idle")
        XCTAssertEqual(idle.row, 0)
        XCTAssertEqual(idle.frames.map(\.column), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(idle.durationMilliseconds, 6_600)

        let running = PetAnimationPlayback.forState("running")
        XCTAssertEqual(running.row, 7)
        XCTAssertEqual(running.frames.map(\.column), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(running.durationMilliseconds, 820)

        let failed = PetAnimationPlayback.forState("failed")
        XCTAssertEqual(failed.row, 5)
        XCTAssertEqual(failed.frames.map(\.column), Array(0..<8))
    }

    func testPetPlaybackUsesAbsoluteElapsedTime() {
        let running = PetAnimationPlayback.forState("running")
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: -1), 0)
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: 119), 0)
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: 120), 1)
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: 599), 4)
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: 600), 5)
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: 819), 5)
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: 820), 0)
        XCTAssertEqual(running.frameIndex(atElapsedMilliseconds: (820 * 12) + 360), 3)
    }

    func testPetAtlasLayoutUsesNonSquareCodexCells() {
        let v2 = PetAtlasLayout(
            spriteVersionNumber: 2,
            imageSize: CGSize(width: 1_536, height: 2_288)
        )
        XCTAssertEqual(v2.rowCount, 11)
        XCTAssertEqual(
            v2.textureRect(row: 7, column: 5),
            CGRect(x: 0.625, y: 3.0 / 11.0, width: 0.125, height: 1.0 / 11.0)
        )

        let v1 = PetAtlasLayout(
            spriteVersionNumber: 1,
            imageSize: CGSize(width: 1_536, height: 1_872)
        )
        XCTAssertEqual(v1.rowCount, 9)
    }

    func testPetAtlasLayoutFallsBackToDeclaredVersion() {
        XCTAssertEqual(
            PetAtlasLayout(
                spriteVersionNumber: 2,
                imageSize: CGSize(width: 400, height: 400)
            ).rowCount,
            11
        )
        XCTAssertEqual(
            PetAtlasLayout(spriteVersionNumber: 1, imageSize: nil).rowCount,
            9
        )
    }

    func testAppIncludesEnglishAndSimplifiedChineseLocalizations() throws {
        let bundle = Bundle(for: AmbientOpsStore.self)

        XCTAssertEqual(bundle.developmentLocalization, "en")
        XCTAssertTrue(bundle.localizations.contains("zh-Hans"))

        let englishInfoPath = try XCTUnwrap(
            bundle.path(
                forResource: "InfoPlist",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "en"
            )
        )
        let chineseInfoPath = try XCTUnwrap(
            bundle.path(
                forResource: "InfoPlist",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "zh-Hans"
            )
        )
        let englishInfo = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: URL(fileURLWithPath: englishInfoPath)),
                format: nil
            ) as? [String: String]
        )
        let chineseInfo = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: URL(fileURLWithPath: chineseInfoPath)),
                format: nil
            ) as? [String: String]
        )

        XCTAssertTrue(
            try XCTUnwrap(englishInfo["NSLocalNetworkUsageDescription"])
                .contains("Codex TPS")
        )
        XCTAssertTrue(
            try XCTUnwrap(chineseInfo["NSLocalNetworkUsageDescription"])
                .contains("Codex TPS")
        )

        let chineseStringsPath = try XCTUnwrap(
            bundle.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "zh-Hans"
            )
        )
        let chineseStrings = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: URL(fileURLWithPath: chineseStringsPath)),
                format: nil
            ) as? [String: String]
        )
        let requiredInteractions = [
            "Home",
            "Machines",
            "Machine",
            "Display",
            "Settings",
            "Demo Mode",
            "Connect",
            "Done",
            "Find on Local Network",
            "Nearby sources",
            "Start Load Live Activity",
            "Start Full-Screen StandBy",
            "Restart Full-Screen StandBy",
            "End Live Activity",
            "StandBy & Lock Screen",
            "Privacy",
            "Connection",
            "Current source",
            "Search Again",
            "Manual Connection",
            "Preview",
        ]

        for key in requiredInteractions {
            XCTAssertNotEqual(chineseStrings[key], nil, "Missing zh-Hans translation for \(key)")
            XCTAssertNotEqual(chineseStrings[key], key, "Untranslated zh-Hans value for \(key)")
        }

        let widgetURL = try XCTUnwrap(
            bundle.builtInPlugInsURL?.appendingPathComponent("Ambient Ops Widgets.appex")
        )
        let widgetBundle = try XCTUnwrap(Bundle(url: widgetURL))
        XCTAssertEqual(widgetBundle.developmentLocalization, "en")
        XCTAssertTrue(widgetBundle.localizations.contains("zh-Hans"))
        XCTAssertNotNil(
            widgetBundle.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "zh-Hans"
            )
        )
    }

    func testDemoCoversEveryLoadStateAndUnknownCPU() {
        let status = DemoFixtures.status(now: Date(timeIntervalSince1970: 1_800_000_000))
        let states = Set(status.machines.map(\.loadVisualState.state))

        XCTAssertEqual(states, Set(["quiet", "active", "heavy", "constrained"]))
        XCTAssertNil(status.machines.first(where: { $0.machineId == "notebook" })?.cpuPercent)
        XCTAssertEqual(status.network.history.count, 60)
    }

    func testLiveActivityCarriesTheProviderVisualStateIntoStandBy() throws {
        let machine = try XCTUnwrap(DemoFixtures.status().machines.first)
        let content = LoadActivityAttributes.ContentState(machine: machine)

        XCTAssertEqual(content.visual, machine.loadVisualState)
        XCTAssertEqual(content.visual?.modelVersion, 1)
        XCTAssertEqual(content.visual?.clusterCount, machine.loadVisualState.clusterCount)
        XCTAssertEqual(content.visual?.travelMs, machine.loadVisualState.travelMs)
    }

    func testCompactLoadStateLabelsStayWithinSmallSurfaceBudget() {
        XCTAssertEqual(LoadStatePalette.compactLabel(for: "quiet"), "QUIET")
        XCTAssertEqual(LoadStatePalette.compactLabel(for: "active"), "ACTIVE")
        XCTAssertEqual(LoadStatePalette.compactLabel(for: "heavy"), "HEAVY")
        XCTAssertEqual(LoadStatePalette.compactLabel(for: "constrained"), "LIMITED")

        for state in ["quiet", "active", "heavy", "constrained"] {
            XCTAssertLessThanOrEqual(LoadStatePalette.compactLabel(for: state).count, 7)
        }
    }

    func testServerHistoryMergesWithLocalCoverageAndReportsItsRealWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let local = [
            LoadHistoryPoint(at: start.addingTimeInterval(-1_200), tps: 999),
            LoadHistoryPoint(at: start.addingTimeInterval(-900), tps: 999),
        ]
        let server = [
            MachineTPSHistoryPoint(at: AmbientISO8601.string(from: start.addingTimeInterval(-1_800)), tps: 12_000),
            MachineTPSHistoryPoint(at: AmbientISO8601.string(from: start.addingTimeInterval(-900)), tps: 24_000),
            MachineTPSHistoryPoint(at: AmbientISO8601.string(from: start), tps: 36_000),
        ]

        let merged = LoadHistorySeries.merged(
            existing: local,
            server: server,
            sampleAt: start,
            tps: 36_000
        )

        XCTAssertEqual(merged.map(\.tps), [12_000, 999, 24_000, 36_000])
        XCTAssertEqual(LoadHistorySeries.coveredMinutes(merged), 30)
    }

    func testTrendDomainMakesHighLoadVariationVisibleWithoutAddingSamples() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [46_212.0, 59_717.0, 51_628.0].enumerated().map { index, tps in
            LoadHistoryPoint(at: now.addingTimeInterval(Double(index) * 5), tps: tps)
        }
        let domain = LoadHistorySeries.trendDomain(points)

        XCTAssertGreaterThan(domain.lowerBound, 0)
        XCTAssertLessThan(domain.lowerBound, 46_212)
        XCTAssertGreaterThan(domain.upperBound, 59_717)
        XCTAssertGreaterThan(13_505 / (domain.upperBound - domain.lowerBound), 0.7)
    }

    func testLocalHistoryReportsPartialWindowWhileCollecting() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [
            LoadHistoryPoint(at: now.addingTimeInterval(-390), tps: 10),
            LoadHistoryPoint(at: now, tps: 20),
        ]

        XCTAssertEqual(LoadHistorySeries.coveredMinutes(points), 7)
    }

    @MainActor
    func testLiveModeCanDisableDemoAndClearsDemoSnapshot() {
        let suiteName = "AmbientOpsTests.demo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let demoKey = "ambient-ops.demo-mode"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: demoKey)
        let store = AmbientOpsStore(defaults: defaults)
        XCTAssertTrue(store.isDemoMode)
        XCTAssertTrue(store.status.demo)

        store.useLiveMode()

        XCTAssertFalse(store.isDemoMode)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertFalse(store.status.demo)
        XCTAssertTrue(store.status.machines.isEmpty)
        XCTAssertEqual(defaults.object(forKey: demoKey) as? Bool, false)
    }

    @MainActor
    func testFirstLaunchUsesAutomaticDiscoveryInsteadOfDemo() {
        let suiteName = "AmbientOpsTests.first-launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AmbientOpsStore(defaults: defaults)

        XCTAssertFalse(store.isDemoMode)
        XCTAssertFalse(store.status.demo)
        XCTAssertTrue(store.isDiscovering)
        XCTAssertEqual(store.connectionState, .loading)
        XCTAssertEqual(defaults.object(forKey: "ambient-ops.demo-mode") as? Bool, false)

        store.useLiveMode()
    }

    func testUnknownCPUDecodesAsNil() throws {
        let json = """
        {
          "schemaVersion": 1,
          "serverVersion": "1.0.0",
          "instanceId": "home",
          "generatedAt": "2026-07-31T00:00:00.000Z",
          "demo": false,
          "site": {"name": "Home", "timeZone": "Asia/Shanghai"},
          "overallStatus": "live",
          "capabilities": {
            "loadVisualState": true,
            "networkHistory": true,
            "pets": true,
            "liveActivityPush": false
          },
          "network": {"status": "live", "history": []},
          "codex": {
            "status": "live",
            "oneMinuteTps": 1000,
            "fiveMinuteTps": 900,
            "cachePercent": 80,
            "activeSessions": 2,
            "cpuPercent": null,
            "cpuReportedMachineCount": 0,
            "memoryPercent": null,
            "memoryReportedMachineCount": 0,
            "machineCount": 1,
            "liveMachineCount": 1,
            "staleMachineCount": 0
          },
          "machines": [{
            "machineId": "mac",
            "machineName": "Mac",
            "platform": "macOS",
            "generatedAt": "2026-07-31T00:00:00.000Z",
            "oneMinute": {"tps": 1000},
            "fiveMinutes": {"tps": 900},
            "activeSessions": 2,
            "cpuPercent": null,
            "memoryPercent": null,
            "pet": null,
            "status": "live",
            "ageSeconds": 0,
            "cachePercent": 80,
            "loadVisualState": {
              "state": "active",
              "label": "ACTIVE",
              "score": 0.3,
              "constrained": false,
              "activity": 0.35,
              "parallel": 0.25,
              "tempo": 1,
              "travelMs": 2000,
              "clusterCount": 2,
              "taskDensity": 0.45,
              "pressure": 0,
              "queueDepth": 0,
              "heat": 0.04
            }
          }]
        }
        """

        let status = try JSONDecoder().decode(AmbientStatus.self, from: Data(json.utf8))
        XCTAssertNil(status.codex.cpuPercent)
        XCTAssertNil(status.machines[0].cpuPercent)
        XCTAssertNil(status.machines[0].loadVisualState.modelVersion)
        XCTAssertEqual(MetricFormat.percent(status.machines[0].cpuPercent), "N/A")
    }

    func testServerURLNormalization() {
        XCTAssertEqual(
            AmbientOpsClient.normalizedServerURL("ambient-ops.local:8787")?.absoluteString,
            "http://ambient-ops.local:8787"
        )
        XCTAssertNil(AmbientOpsClient.normalizedServerURL("not a host"))
    }

    func testSourceSelectionPrefersSavedThenGatewayThenUniqueDirect() throws {
        let gateway = DiscoveredServer(
            id: "gateway:home",
            instanceID: "home",
            name: "Home",
            url: try XCTUnwrap(URL(string: "http://home.local:8787")),
            version: "1.0",
            kind: .gateway
        )
        let studio = DiscoveredServer(
            id: "codexTPS:studio",
            instanceID: "studio",
            name: "Studio",
            url: try XCTUnwrap(URL(string: "http://studio.local:7419")),
            version: "1.0",
            kind: .codexTPS
        )
        let notebook = DiscoveredServer(
            id: "codexTPS:notebook",
            instanceID: "notebook",
            name: "Notebook",
            url: try XCTUnwrap(URL(string: "http://notebook.local:7419")),
            version: "1.0",
            kind: .codexTPS
        )

        XCTAssertEqual(
            SourceSelectionPolicy.automaticSource(
                from: [gateway, studio],
                preferredID: studio.id
            ),
            studio
        )
        XCTAssertEqual(
            SourceSelectionPolicy.automaticSource(
                from: [studio, gateway],
                preferredID: nil
            ),
            gateway
        )
        XCTAssertEqual(
            SourceSelectionPolicy.automaticSource(
                from: [studio],
                preferredID: nil
            ),
            studio
        )
        XCTAssertNil(
            SourceSelectionPolicy.automaticSource(
                from: [studio, notebook],
                preferredID: nil
            )
        )
    }

    @MainActor
    func testDirectProviderShowsHostNetworkWithoutMakingTheStatusFail() throws {
        let encoded = try JSONEncoder().encode(DemoFixtures.status())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["provider"] = [
            "kind": "codex-tps",
            "scope": "machine",
            "id": "studio",
            "name": "Studio",
        ]
        object["demo"] = false
        var capabilities = try XCTUnwrap(object["capabilities"] as? [String: Any])
        capabilities["network"] = true
        capabilities["networkHistory"] = false
        capabilities["persistentHistory"] = false
        capabilities["webDisplay"] = false
        object["capabilities"] = capabilities
        var network = try XCTUnwrap(object["network"] as? [String: Any])
        network["status"] = "unavailable"
        network["history"] = []
        object["network"] = network
        object["machines"] = Array(
            try XCTUnwrap(object["machines"] as? [[String: Any]]).prefix(1)
        )

        let direct = try JSONDecoder().decode(
            AmbientStatus.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let store = AmbientOpsStore(automaticallyConnect: false)
        store.useLiveMode()
        store.status = direct

        XCTAssertEqual(direct.effectiveProvider.scope, "machine")
        XCTAssertEqual(direct.overallStatus, "live")
        XCTAssertTrue(direct.capabilities.supportsNetwork)
        XCTAssertTrue(store.availableDisplayModes.contains(.network))
        XCTAssertEqual(store.providerLabel, "DIRECT · Studio")
    }
}
