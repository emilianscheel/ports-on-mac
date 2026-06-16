import Foundation

struct PortGroup {
    let port: Int
    let entries: [PortEntry]

    var title: String {
        let commands = Array(Set(entries.map(\.command))).sorted().prefix(3).joined(separator: ", ")
        return ":\(port)  \(commands)"
    }
}

struct PortEntry {
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

    var processTitle: String {
        "\(command)  pid \(pid)"
    }

    var details: [String] {
        var values = [
            "Command: \(command)",
            "PID: \(pid)",
            "User: \(user)",
            "Protocol: \(protocolName)",
            "Local: \(localEndpoint)"
        ]

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
        guard protocolName == "TCP" || protocolName == "UDP" else { return nil }
        guard let host = localHostForBrowser(from: localEndpoint) else { return nil }
        return URL(string: "http://\(host):\(port)")
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

final class PortScanner {
    func scan() -> [PortGroup] {
        let output = runLsof()
        let entries = output
            .split(separator: "\n")
            .dropFirst()
            .compactMap(parseLine)

        let grouped = Dictionary(grouping: entries, by: \.port)
        return grouped
            .map { PortGroup(port: $0.key, entries: $0.value.sorted(by: sortEntries)) }
            .sorted { $0.port < $1.port }
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
        var name = String(columns[8])

        guard let protocolName = name.split(separator: " ", maxSplits: 1).first.map(String.init) else {
            return nil
        }

        name.removeFirst(protocolName.count)
        name = name.trimmingCharacters(in: CharacterSet.whitespaces)

        let state = extractState(from: name)
        let endpointText = removeState(from: name)
        let endpoints = endpointText.components(separatedBy: "->")
        let localEndpoint = endpoints[0].trimmingCharacters(in: CharacterSet.whitespaces)
        let remoteEndpoint = endpoints.count > 1 ? endpoints[1].trimmingCharacters(in: CharacterSet.whitespaces) : nil

        guard let port = extractPort(from: localEndpoint) else { return nil }

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
            port: port
        )
    }

    private func extractState(from text: String) -> String? {
        guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else { return nil }
        let start = text.index(after: open)
        let end = text.index(before: text.endIndex)
        return String(text[start..<end])
    }

    private func removeState(from text: String) -> String {
        guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else { return text }
        return text[..<open].trimmingCharacters(in: .whitespaces)
    }

    private func extractPort(from endpoint: String) -> Int? {
        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        let value = endpoint[endpoint.index(after: colon)...]
        guard value != "*" else { return nil }
        return Int(value)
    }

    private func sortEntries(_ lhs: PortEntry, _ rhs: PortEntry) -> Bool {
        if lhs.command != rhs.command { return lhs.command < rhs.command }
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        return lhs.localEndpoint < rhs.localEndpoint
    }

    private func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\x20", with: " ")
    }
}
