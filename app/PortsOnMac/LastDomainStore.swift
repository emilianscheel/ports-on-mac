import Foundation

final class LastDomainStore: @unchecked Sendable {
    static let shared = LastDomainStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.emilianscheel.ports-on-mac.last-domains")
    private var domains: [String: String]

    init(fileURL: URL? = nil) {
        let resolved = fileURL ?? ProxyConstants.applicationSupportDirectory.appendingPathComponent("last-domains.json")
        self.fileURL = resolved
        self.domains = Self.load(from: resolved)
    }

    func domain(for entry: PortEntry) -> String? {
        queue.sync { domains[Self.key(for: entry)] }
    }

    func remember(_ domain: String, for entry: PortEntry) {
        queue.sync {
            domains[Self.key(for: entry)] = domain
            try? persistLocked()
        }
    }

    static func key(for entry: PortEntry) -> String {
        if let bundleIdentifier = entry.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier.lowercased())#\(entry.port)"
        }

        let containers = entry.dockerContainers.map(\.name).filter { !$0.isEmpty }.sorted()
        if !containers.isEmpty {
            return "docker:\(containers.joined(separator: ",").lowercased())#\(entry.port)"
        }

        if let executablePath = entry.executablePath, !executablePath.isEmpty {
            return "exec:\(executablePath)#\(entry.port)"
        }

        return "cmd:\(entry.command)#\(entry.port)"
    }

    private func persistLocked() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(domains)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}
