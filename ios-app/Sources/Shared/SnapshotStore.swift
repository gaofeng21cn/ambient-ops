import Foundation

enum SharedSnapshotStore {
    static let appGroup = "group.cn.gaofeng.ambientops"
    private static let snapshotKey = "latest-status-v1"
    private static let selectedMachineKey = "focused-machine-v1"

    static func save(_ snapshot: AmbientStatus, focusedMachineID: String?) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: snapshotKey)
        defaults.set(focusedMachineID, forKey: selectedMachineKey)
    }

    static func load() -> (status: AmbientStatus, focusedMachineID: String?)? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey),
              let status = try? JSONDecoder().decode(AmbientStatus.self, from: data) else {
            return nil
        }
        return (status, defaults.string(forKey: selectedMachineKey))
    }
}
