@preconcurrency import Foundation

struct DiscoveredServer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let version: String?
}

@MainActor
final class DiscoveryService: NSObject,
    @preconcurrency NetServiceBrowserDelegate,
    @preconcurrency NetServiceDelegate {
    var onChange: (([DiscoveredServer]) -> Void)?
    var onError: ((String) -> Void)?

    private let browser = NetServiceBrowser()
    private var resolving: [NetService] = []
    private var servers: [String: DiscoveredServer] = [:]

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard resolving.isEmpty else { return }
        servers.removeAll()
        onChange?([])
        browser.searchForServices(ofType: "_ambient-ops._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        resolving.forEach { $0.stop() }
        resolving.removeAll()
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        resolving.removeAll { $0 == service }
        if let key = servers.first(where: { $0.value.name == service.name })?.key {
            servers.removeValue(forKey: key)
            publish()
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        onError?(String(localized: "Local discovery could not start."))
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer { resolving.removeAll { $0 == sender } }
        guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              sender.port > 0,
              let url = URL(string: "http://\(host):\(sender.port)") else {
            return
        }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let instanceID = txt["id"].flatMap { String(data: $0, encoding: .utf8) } ?? url.absoluteString
        let displayName = txt["name"].flatMap { String(data: $0, encoding: .utf8) } ?? sender.name
        let version = txt["version"].flatMap { String(data: $0, encoding: .utf8) }
        servers[instanceID] = DiscoveredServer(
            id: instanceID,
            name: displayName,
            url: url,
            version: version
        )
        publish()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.removeAll { $0 == sender }
    }

    private func publish() {
        onChange?(servers.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
}
