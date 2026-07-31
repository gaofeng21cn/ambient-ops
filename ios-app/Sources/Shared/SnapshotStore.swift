import Foundation

enum SharedSnapshotStore {
    static let appGroup = "group.cn.gaofeng.ambientops"
    private static let snapshotKey = "latest-status-v1"
    private static let selectedMachineKey = "focused-machine-v1"
    private static let sourceURLKey = "status-source-url-v1"

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

    static func saveSourceURL(_ sourceURL: URL?) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        guard let sourceURL else {
            defaults.removeObject(forKey: sourceURLKey)
            return
        }
        defaults.set(sourceURL.absoluteString, forKey: sourceURLKey)
    }

    static func sourceURL() -> URL? {
        guard let value = UserDefaults(suiteName: appGroup)?.string(forKey: sourceURLKey),
              let url = URL(string: value),
              url.scheme == "http" || url.scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }
}

struct SharedStatusClient: Sendable {
    func fetchStatus(from sourceURL: URL) async throws -> AmbientStatus {
        guard let endpoint = URL(string: "/api/v1/status", relativeTo: sourceURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let status = try JSONDecoder().decode(AmbientStatus.self, from: data)
        guard status.schemaVersion == 1 else {
            throw URLError(.cannotParseResponse)
        }
        return status
    }
}
