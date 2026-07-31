import AppIntents
import Foundation

struct OpenLoadDisplayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Load Display"
    static let description = IntentDescription("Opens the focused Codex load display.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedSnapshotStore.appGroup)?
            .set("load", forKey: "pending-route")
        return .result()
    }
}
