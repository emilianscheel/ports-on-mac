import Foundation

enum PortDirection: CaseIterable, Sendable {
    case inbound
    case outbound

    var title: String {
        switch self {
        case .inbound:
            return "Inbound"
        case .outbound:
            return "Outbound"
        }
    }

    var emptyTitle: String {
        switch self {
        case .inbound:
            return "No inbound ports"
        case .outbound:
            return "No outbound ports"
        }
    }
}

struct PortSection: Sendable {
    let direction: PortDirection
    let groups: [PortGroup]
}

struct PortGroup: Sendable {
    let direction: PortDirection
    let port: Int
    let entries: [PortEntry]

    var title: String {
        ":\(port)  \(headlineNames.joined(separator: ", "))"
    }

    var subtitle: String? {
        guard direction == .inbound else { return nil }
        let usedProjectFolder = entries.contains { $0.usefulProjectFolderName != nil }
        guard usedProjectFolder else { return nil }
        return Array(Self.uniqueNames(entries.map(\.displayCommand)).prefix(3)).joined(separator: ", ")
    }

    private var headlineNames: [String] {
        let names: [String]
        if direction == .inbound {
            names = entries.map { $0.usefulProjectFolderName ?? $0.displayCommand }
        } else {
            names = entries.map(\.displayCommand)
        }
        return Array(Self.uniqueNames(names).prefix(3))
    }

    private static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    var hasSingleProcess: Bool {
        Set(entries.map(\.processIdentity)).count == 1
    }
}

struct DockerContainer: Sendable {
    let id: String
    let name: String

    var title: String {
        "\(name) (\(id))"
    }
}

struct PortEntry: Sendable {
    let command: String
    let pid: Int32
    let user: String
    let fileDescriptor: String
    let socketType: String
    let protocolName: String
    let localEndpoint: String
    let remoteEndpoint: String?
    let state: String?
    let port: Int
    let direction: PortDirection
    let dockerContainers: [DockerContainer]
    let executablePath: String?
    let bundleIdentifier: String?
    let currentWorkingDirectory: String?

    var displayCommand: String {
        if isDockerDesktopProxy {
            return "Docker Desktop"
        }

        return command
    }

    var isDockerDesktopProxy: Bool {
        let normalized = command.lowercased()
        return normalized.hasPrefix("com.docke") || normalized.contains("docker")
    }

    var processTitle: String {
        "\(displayCommand)  pid \(pid)"
    }

    var processIdentity: String {
        "\(displayCommand)#\(pid)"
    }

    var details: [String] {
        var values = [
            "Command: \(displayCommand)",
            "PID: \(pid)",
            "User: \(user)",
            "Direction: \(direction.title)",
            "Protocol: \(protocolName)",
            "Local: \(localEndpoint)"
        ]

        if !dockerContainers.isEmpty {
            values.append("Container: \(dockerContainers.map(\.title).joined(separator: ", "))")
        }

        if let remoteEndpoint, !remoteEndpoint.isEmpty {
            values.append("Remote: \(remoteEndpoint)")
        }

        if let state, !state.isEmpty {
            values.append("State: \(state)")
        }

        values.append("FD: \(fileDescriptor)")
        values.append("Socket: \(socketType)")
        return values
    }

    var openURL: URL? {
        guard protocolName == "TCP" else { return nil }
        guard let host = localHostForBrowser(from: localEndpoint) else { return nil }
        return URL(string: "http://\(host):\(port)")
    }

    var canAssignDomain: Bool {
        direction == .inbound && openURL != nil
    }

    var suggestedDomain: String? {
        if let folderName = projectFolderName, let domain = DomainName.suggested(fromName: folderName) {
            return domain
        }
        return DomainName.suggested(fromName: command)
    }

    var usefulProjectFolderName: String? {
        guard let name = projectFolderName else { return nil }
        guard !Self.genericProjectFolderNames.contains(name.lowercased()) else { return nil }
        if let currentWorkingDirectory {
            let parent = URL(fileURLWithPath: currentWorkingDirectory).deletingLastPathComponent().lastPathComponent
            if parent.lowercased() == "users" {
                return nil
            }
        }
        return name
    }

    private var projectFolderName: String? {
        guard let currentWorkingDirectory, !currentWorkingDirectory.isEmpty else { return nil }
        let name = URL(fileURLWithPath: currentWorkingDirectory).lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else { return nil }
        return name
    }

    private static let genericProjectFolderNames: Set<String> = [
        "application support", "applications", "bin", "cellar", "contents",
        "cores", "developer", "etc", "frameworks", "helpers", "homebrew",
        "library", "macos", "opt", "plugins", "private", "public", "resources",
        "sbin", "sharedsupport", "system", "tmp", "usr", "users", "var",
        "volumes"
    ]

    /// Inbound listeners that a person might open or kill: user apps, Docker, and
    /// non-Apple binaries. Apple daemons under /System and /usr/libexec are hidden.
    var isUsefulInbound: Bool {
        guard direction == .inbound else { return true }

        if !dockerContainers.isEmpty || isDockerDesktopProxy {
            return true
        }

        if let bundleIdentifier {
            return !bundleIdentifier.hasPrefix("com.apple.")
        }

        if let executablePath, Self.systemExecutableRoots.contains(where: { executablePath.hasPrefix($0) }) {
            return false
        }

        return !Self.noisySystemCommands.contains(command)
    }

    private static let systemExecutableRoots = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/sbin/",
        "/Library/Apple/"
    ]

    private static let noisySystemCommands: Set<String> = [
        "AirPlayXP", "ControlCe", "ControlCenter", "WindowServ", "apsd", "bluetoothd",
        "cfprefsd", "cloudd", "coreaudiod", "corespeechd", "distnoted", "homed",
        "identitys", "imagent", "launchd", "lsd", "mDNSResp", "mDNSResponder",
        "nearbyd", "nsurlsess", "rapportd", "remotepai", "replayd", "securityd",
        "sharingd", "suggestd", "symptomsd", "syslogd", "timed", "trustd",
        "UserEvent", "wifip2pd", "containermanagerd"
    ]

    func openURL(domain: String?, usesHTTPS: Bool = false) -> URL? {
        if let domain, !domain.isEmpty {
            let scheme = usesHTTPS ? "https" : "http"
            return URL(string: "\(scheme)://\(domain)")
        }
        return openURL
    }

    func enriched(with containers: [DockerContainer]) -> PortEntry {
        copy(
            dockerContainers: containers,
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier,
            currentWorkingDirectory: currentWorkingDirectory
        )
    }

    func withProcessMetadata() -> PortEntry {
        let metadata = ProcessMetadata.cached(for: pid)
        return copy(
            dockerContainers: dockerContainers,
            executablePath: metadata.executablePath,
            bundleIdentifier: metadata.bundleIdentifier,
            currentWorkingDirectory: metadata.currentWorkingDirectory
        )
    }

    private func copy(
        dockerContainers: [DockerContainer],
        executablePath: String?,
        bundleIdentifier: String?,
        currentWorkingDirectory: String?
    ) -> PortEntry {
        PortEntry(
            command: command,
            pid: pid,
            user: user,
            fileDescriptor: fileDescriptor,
            socketType: socketType,
            protocolName: protocolName,
            localEndpoint: localEndpoint,
            remoteEndpoint: remoteEndpoint,
            state: state,
            port: port,
            direction: direction,
            dockerContainers: dockerContainers,
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier,
            currentWorkingDirectory: currentWorkingDirectory
        )
    }

    private func localHostForBrowser(from endpoint: String) -> String? {
        let host = endpointHost(endpoint)
        guard !host.isEmpty else { return nil }

        if host == "*" || host == "0.0.0.0" || host == "::" || host == "[::]" {
            return "localhost"
        }

        if host == "127.0.0.1" || host == "::1" || host == "[::1]" || host.lowercased() == "localhost" {
            return "localhost"
        }

        if host.contains(":") && !host.hasPrefix("[") {
            return "[\(host)]"
        }

        return host
    }

    private func endpointHost(_ endpoint: String) -> String {
        if endpoint.hasPrefix("[") {
            guard let closeBracket = endpoint.firstIndex(of: "]") else { return endpoint }
            return String(endpoint[...closeBracket])
        }

        guard let colon = endpoint.lastIndex(of: ":") else { return endpoint }
        return String(endpoint[..<colon])
    }
}

final class PortScanner: @unchecked Sendable {
    private let dockerMetadataProvider = DockerMetadataProvider()

    func scan() -> [PortSection] {
        let outputBox = ScanBox("")
        let dockerBox = ScanBox<[Int: [DockerContainer]]>([:])
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.value = self.runLsof()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            dockerBox.value = self.dockerMetadataProvider.containersByPublishedPort()
            group.leave()
        }

        group.wait()
        let output = outputBox.value
        let dockerContainersByPort = dockerBox.value
        let parsedEntries = output
            .split(separator: "\n")
            .dropFirst()
            .compactMap(parseLine)

        let listeningPorts = Set(
            parsedEntries
                .filter { $0.protocolName == "TCP" && $0.state == "LISTEN" }
                .map(\.port)
        )

        let entries = parsedEntries
            .filter { entry in
                !(entry.protocolName == "TCP" && entry.state != "LISTEN" && listeningPorts.contains(entry.port))
            }
            .map { entry in
                entry
                    .withProcessMetadata()
                    .enriched(with: dockerContainersByPort[entry.port] ?? [])
            }

        ProcessMetadata.retainPids(Set(entries.map(\.pid)))

        return PortDirection.allCases.map { direction in
            let directionEntries = entries.filter { $0.direction == direction }
            let grouped = Dictionary(grouping: directionEntries, by: \.port)
            let groups = grouped
                .map { PortGroup(direction: direction, port: $0.key, entries: $0.value.sorted(by: sortEntries)) }
                .sorted { $0.port < $1.port }

            return PortSection(direction: direction, groups: groups)
        }
    }

    func debugRawLsofOutput() -> String {
        runLsof()
    }

    private func runLsof() -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-iUDP"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseLine(_ line: Substring) -> PortEntry? {
        let columns = line.split(maxSplits: 8, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard columns.count >= 9 else { return nil }

        let command = unescape(String(columns[0]))
        guard let pid = Int32(columns[1]) else { return nil }

        let user = String(columns[2])
        let fileDescriptor = String(columns[3])
        let socketType = String(columns[4])
        let protocolName = String(columns[7])
        let name = String(columns[8]).trimmingCharacters(in: CharacterSet.whitespaces)

        let state = extractState(from: name)
        let endpointText = removeState(from: name)
        let endpoints = endpointText.components(separatedBy: "->")
        let localEndpoint = endpoints[0].trimmingCharacters(in: CharacterSet.whitespaces)
        let remoteEndpoint = endpoints.count > 1 ? endpoints[1].trimmingCharacters(in: CharacterSet.whitespaces) : nil

        guard let port = extractPort(from: localEndpoint) else { return nil }
        guard let direction = classify(protocolName: protocolName, state: state, remoteEndpoint: remoteEndpoint) else {
            return nil
        }

        return PortEntry(
            command: command,
            pid: pid,
            user: user,
            fileDescriptor: fileDescriptor,
            socketType: socketType,
            protocolName: protocolName,
            localEndpoint: localEndpoint,
            remoteEndpoint: remoteEndpoint,
            state: state,
            port: port,
            direction: direction,
            dockerContainers: [],
            executablePath: nil,
            bundleIdentifier: nil,
            currentWorkingDirectory: nil
        )
    }

    private func classify(protocolName: String, state: String?, remoteEndpoint: String?) -> PortDirection? {
        if protocolName == "TCP", state == "LISTEN" {
            return .inbound
        }

        if protocolName == "UDP", remoteEndpoint == nil {
            return .inbound
        }

        if remoteEndpoint != nil {
            return .outbound
        }

        return nil
    }

    private func extractState(from text: String) -> String? {
        guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else { return nil }
        let start = text.index(after: open)
        let end = text.index(before: text.endIndex)
        return String(text[start..<end])
    }

    private func removeState(from text: String) -> String {
        guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else { return text }
        return text[..<open].trimmingCharacters(in: CharacterSet.whitespaces)
    }

    private func extractPort(from endpoint: String) -> Int? {
        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        let value = endpoint[endpoint.index(after: colon)...]
        guard value != "*" else { return nil }
        return Int(value)
    }

    private func sortEntries(_ lhs: PortEntry, _ rhs: PortEntry) -> Bool {
        if lhs.displayCommand != rhs.displayCommand { return lhs.displayCommand < rhs.displayCommand }
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        return lhs.localEndpoint < rhs.localEndpoint
    }

    private func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\x20", with: " ")
    }
}

private final class ScanBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class DockerMetadataProvider: @unchecked Sendable {
    private static let queryTimeout: TimeInterval = 0.3

    func containersByPublishedPort() -> [Int: [DockerContainer]] {
        guard dockerSocketExists() else { return [:] }
        guard let output = runDockerPS(), !output.isEmpty else { return [:] }

        var containersByPort: [Int: [DockerContainer]] = [:]
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }

            let id = String(columns[0])
            let name = String(columns[1])
            let ports = String(columns[2])
            let container = DockerContainer(id: id, name: name)

            for port in publishedHostPorts(from: ports) {
                containersByPort[port, default: []].append(container)
            }
        }

        return containersByPort
    }

    private func runDockerPS() -> String? {
        guard let dockerPath = dockerExecutablePath() else { return nil }

        let process = Process()
        let output = Pipe()
        let finished = DispatchGroup()

        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Ports}}"]
        process.standardOutput = output
        process.standardError = Pipe()
        finished.enter()
        process.terminationHandler = { _ in finished.leave() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + Self.queryTimeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 0.1)
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func dockerSocketExists() -> Bool {
        let sockets = [
            "/var/run/docker.sock",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".docker/run/docker.sock").path
        ]
        return sockets.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func dockerExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/usr/bin/docker"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func publishedHostPorts(from ports: String) -> [Int] {
        ports
            .components(separatedBy: ",")
            .compactMap { publishedHostPort(from: $0.trimmingCharacters(in: CharacterSet.whitespaces)) }
    }

    private func publishedHostPort(from mapping: String) -> Int? {
        guard let arrowRange = mapping.range(of: "->") else { return nil }

        let hostSide = String(mapping[..<arrowRange.lowerBound])
        let portText: String

        if let colon = hostSide.lastIndex(of: ":") {
            portText = String(hostSide[hostSide.index(after: colon)...])
        } else {
            portText = hostSide
        }

        guard !portText.contains("-") else { return nil }
        return Int(portText)
    }
}
