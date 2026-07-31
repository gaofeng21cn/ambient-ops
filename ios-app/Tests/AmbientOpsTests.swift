import XCTest
@testable import AmbientOps

final class AmbientOpsTests: XCTestCase {
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
                .contains("self-hosted server")
        )
        XCTAssertTrue(
            try XCTUnwrap(chineseInfo["NSLocalNetworkUsageDescription"])
                .contains("自托管服务器")
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
            "Display",
            "Settings",
            "Demo Mode",
            "Connect",
            "Find on Local Network",
            "Allow Local Network Access?",
            "Start Load Live Activity",
            "End Live Activity",
            "Privacy",
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
        XCTAssertEqual(MetricFormat.percent(status.machines[0].cpuPercent), "N/A")
    }

    func testServerURLNormalization() {
        XCTAssertEqual(
            AmbientOpsClient.normalizedServerURL("ambient-ops.local:8787")?.absoluteString,
            "http://ambient-ops.local:8787"
        )
        XCTAssertNil(AmbientOpsClient.normalizedServerURL("not a host"))
    }
}
