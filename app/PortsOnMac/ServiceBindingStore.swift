import Foundation

enum DomainName {
    enum ValidationError: LocalizedError {
        case empty
        case localhost
        case invalid
        case duplicate(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Enter a hostname like all-in-agi.com."
            case .localhost:
                return "localhost cannot be assigned as a custom domain."
            case .invalid:
                return "Use a hostname like all-in-agi.com, without a port or path."
            case .duplicate(let domain):
                return "\(domain) is already assigned to another process."
            }
        }
    }

    static func normalize(_ raw: String) throws -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash])
        }
        if let query = value.firstIndex(of: "?") {
            value = String(value[..<query])
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if value.hasPrefix("[") {
            throw ValidationError.invalid
        }

        if let colon = value.firstIndex(of: ":") {
            value = String(value[..<colon])
        }

        guard !value.isEmpty else { throw ValidationError.empty }
        guard value != "localhost" else { throw ValidationError.localhost }
        guard isHostname(value) else { throw ValidationError.invalid }
        return value
    }

    private static func isHostname(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        let pattern = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/
        return labels.allSatisfy { label in
            guard label.count <= 63 else { return false }
            return label.wholeMatch(of: pattern) != nil
        }
    }
}

struct ServiceBinding: Codable, Equatable, Sendable {
    var domain: String
    var port: Int
    var command: String
    var executablePath: String?
    var bundleIdentifier: String?
    var dockerContainerNames: [String]
    var currentWorkingDirectory: String?
    var assignedAt: Date

    init(
        domain: String,
        port: Int,
        command: String,
        executablePath: String?,
        bundleIdentifier: String?,
        dockerContainerNames: [String],
        currentWorkingDirectory: String?,
        assignedAt: Date = Date()
    ) {
        self.domain = domain
        self.port = port
        self.command = command
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.dockerContainerNames = dockerContainerNames
        self.currentWorkingDirectory = currentWorkingDirectory
        self.assignedAt = assignedAt
    }

    init(domain: String, entry: PortEntry) {
        self.init(
            domain: domain,
            port: entry.port,
            command: entry.command,
            executablePath: entry.executablePath,
            bundleIdentifier: entry.bundleIdentifier,
            dockerContainerNames: entry.dockerContainers.map(\.name),
            currentWorkingDirectory: entry.currentWorkingDirectory
        )
    }

    func matchRank(against entry: PortEntry) -> Int? {
        guard port == entry.port else { return nil }

        if let bundleIdentifier, let liveBundle = entry.bundleIdentifier, bundleIdentifier == liveBundle {
            return 1
        }

        let savedContainers = Set(dockerContainerNames)
        let liveContainers = Set(entry.dockerContainers.map(\.name))
        if !savedContainers.isEmpty, !savedContainers.isDisjoint(with: liveContainers) {
            return 2
        }

        let commandMatches = command == entry.command || command == entry.displayCommand
        guard commandMatches else { return nil }

        if let executablePath, let livePath = entry.executablePath, executablePath == livePath {
            return 3
        }

        return 4
    }
}

final class ServiceBindingStore: @unchecked Sendable {
    static let shared = ServiceBindingStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.emilianscheel.ports-on-mac.bindings")
    private var bindings: [ServiceBinding]

    init(fileURL: URL? = nil) {
        let resolved = fileURL ?? Self.defaultFileURL()
        self.fileURL = resolved
        self.bindings = Self.load(from: resolved)
    }

    func all() -> [ServiceBinding] {
        queue.sync { bindings }
    }

    func binding(matching entry: PortEntry) -> ServiceBinding? {
        liveMatches(from: [entry]).first?.binding
    }

    func binding(domain: String) -> ServiceBinding? {
        let normalized = domain.lowercased()
        return queue.sync {
            bindings.first { $0.domain.lowercased() == normalized }
        }
    }

    func liveMatches(from entries: [PortEntry]) -> [(entry: PortEntry, binding: ServiceBinding)] {
        queue.sync {
            var usedDomains = Set<String>()
            var seenProcesses = Set<String>()
            var result: [(PortEntry, ServiceBinding)] = []

            for entry in entries {
                let processKey = "\(entry.processIdentity)#\(entry.port)"
                if seenProcesses.contains(processKey) {
                    continue
                }

                let candidates = bindings.compactMap { binding -> (ServiceBinding, Int)? in
                    let domainKey = binding.domain.lowercased()
                    guard !usedDomains.contains(domainKey) else { return nil }
                    guard let rank = binding.matchRank(against: entry) else { return nil }
                    return (binding, rank)
                }.sorted { $0.1 < $1.1 }

                guard let best = candidates.first else { continue }

                seenProcesses.insert(processKey)
                usedDomains.insert(best.0.domain.lowercased())
                result.append((entry, best.0))
            }

            return result
        }
    }

    func assign(domain rawDomain: String, to entry: PortEntry) throws {
        let domain = try DomainName.normalize(rawDomain)

        try queue.sync {
            if let existing = bindings.first(where: { $0.domain.lowercased() == domain }),
               existing.matchRank(against: entry) == nil {
                throw DomainName.ValidationError.duplicate(domain)
            }

            bindings.removeAll { $0.matchRank(against: entry) != nil || $0.domain.lowercased() == domain }
            bindings.append(ServiceBinding(domain: domain, entry: entry))
            try persistLocked()
        }
    }

    func unassign(entry: PortEntry) throws {
        try queue.sync {
            bindings.removeAll { $0.matchRank(against: entry) != nil }
            try persistLocked()
        }
    }

    func unassign(domain: String) throws {
        let normalized = domain.lowercased()
        try queue.sync {
            bindings.removeAll { $0.domain.lowercased() == normalized }
            try persistLocked()
        }
    }

    private func persistLocked() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(bindings)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("com.emilianscheel.ports-on-mac", isDirectory: true)
            .appendingPathComponent("bindings.json")
    }

    private static func load(from url: URL) -> [ServiceBinding] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ServiceBinding].self, from: data)) ?? []
    }
}
