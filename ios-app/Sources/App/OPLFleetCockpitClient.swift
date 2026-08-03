import Foundation

enum OPLFleetCockpitClientError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case unsupportedSchema(Int)
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "Enter a valid Gateway address.")
        case .invalidResponse:
            String(localized: "The server returned an invalid response.")
        case .unsupportedSchema(let version):
            String(
                localized: "This app does not support status schema \(version).",
                comment: "Error shown when the server status API is newer than the app."
            )
        case .server(let status):
            String(
                localized: "The Gateway returned HTTP \(status).",
                comment: "HTTP error returned by the user's self-hosted server."
            )
        }
    }
}

struct OPLFleetCockpitClient: Sendable {
    func fetchStatus(from serverURL: URL) async throws -> AmbientStatus {
        guard let endpoint = URL(string: "/api/v1/status", relativeTo: serverURL)?.absoluteURL else {
            throw OPLFleetCockpitClientError.invalidServerURL
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OPLFleetCockpitClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OPLFleetCockpitClientError.server(http.statusCode)
        }
        let snapshot = try JSONDecoder().decode(AmbientStatus.self, from: data)
        guard snapshot.schemaVersion == 1 else {
            throw OPLFleetCockpitClientError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }

    static func normalizedServerURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
