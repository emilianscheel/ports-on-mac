import Foundation
import Network
import Security

enum LocalProxyError: LocalizedError {
    case bindFailed(Error)
    case timedOut(UInt16)
    case missingTLSIdentity

    var errorDescription: String? {
        switch self {
        case .bindFailed(let error):
            return "Could not start the local proxy: \(error.localizedDescription)"
        case .timedOut(let port):
            return "Timed out binding the local proxy on port \(port)."
        case .missingTLSIdentity:
            return "Could not create a local HTTPS identity."
        }
    }
}

final class LocalProxyServer: @unchecked Sendable {
    static let shared = LocalProxyServer()

    private let queue = DispatchQueue(label: "com.emilianscheel.ports-on-mac.proxy")
    private let lock = NSLock()
    private var httpListener: NWListener?
    private var tlsListener: NWListener?
    private var routes: [String: Int] = [:]
    private var lastHTTPSDomains: [String] = []

    func updateRoutes(_ routes: [String: Int], httpsDomains: [String] = []) throws {
        let normalized = Dictionary(uniqueKeysWithValues: routes.map { ($0.key.lowercased(), $0.value) })
        let https = Array(Set(httpsDomains.map { $0.lowercased() })).sorted()
        let shouldStart = queue.sync { () -> Bool in
            self.routes = normalized
            if normalized.isEmpty {
                self.stopLocked()
                self.lastHTTPSDomains = []
                return false
            }
            return true
        }

        guard shouldStart else { return }
        try startHTTP()
        try updateHTTPS(https)
    }

    private func startHTTP() throws {
        lock.lock()
        if httpListener != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let listener = try bindListener(
            parameters: loopbackTCP(),
            port: ProxyConstants.userProxyPort,
            proto: "http"
        )

        lock.lock()
        self.httpListener = listener
        lock.unlock()
    }

    private func updateHTTPS(_ domains: [String]) throws {
        lock.lock()
        let domainsChanged = domains != lastHTTPSDomains
        lastHTTPSDomains = domains
        let existing = tlsListener
        lock.unlock()

        if domains.isEmpty {
            existing?.cancel()
            lock.lock()
            tlsListener = nil
            lock.unlock()
            return
        }

        guard domainsChanged || existing == nil else { return }

        existing?.cancel()
        lock.lock()
        tlsListener = nil
        lock.unlock()

        let identity = try LocalCertificateAuthority.shared.identity(for: domains)
        guard let secIdentity = sec_identity_create(identity) else {
            throw LocalProxyError.missingTLSIdentity
        }

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)

        let tcp = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback

        let listener = try bindListener(
            parameters: parameters,
            port: ProxyConstants.userHTTPSProxyPort,
            proto: "https"
        )

        lock.lock()
        self.tlsListener = listener
        lock.unlock()
    }

    private func loopbackTCP() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        return parameters
    }

    private func bindListener(parameters: NWParameters, port: UInt16, proto: String) throws -> NWListener {
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

        let bindState = BindWait()
        bindState.group.enter()
        listener.stateUpdateHandler = { [weak self] state in
            bindState.lock.lock()
            defer { bindState.lock.unlock() }

            switch state {
            case .ready:
                guard !bindState.finished else { return }
                bindState.finished = true
                bindState.group.leave()
            case .failed(let error):
                if !bindState.finished {
                    bindState.finished = true
                    bindState.error = error
                    bindState.group.leave()
                }
                NSLog("Ports on Mac proxy failed on \(port): \(error.localizedDescription)")
                self?.queue.async {
                    self?.stopLocked()
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection, proto: proto)
        }
        listener.start(queue: queue)

        let waitResult = bindState.group.wait(timeout: .now() + 2)
        if let startError = bindState.error {
            listener.cancel()
            throw LocalProxyError.bindFailed(startError)
        }
        if waitResult == .timedOut {
            listener.cancel()
            throw LocalProxyError.timedOut(port)
        }

        return listener
    }

    private func stopLocked() {
        lock.lock()
        httpListener?.cancel()
        tlsListener?.cancel()
        httpListener = nil
        tlsListener = nil
        lock.unlock()
    }

    private func handle(_ connection: NWConnection, proto: String) {
        connection.start(queue: queue)
        receiveHeaders(from: connection, buffer: Data(), proto: proto)
    }

    private func receiveHeaders(from connection: NWConnection, buffer: Data, proto: String) {
        if let headerRange = buffer.range(of: Data([13, 10, 13, 10])) {
            let headerBlock = buffer[buffer.startIndex..<headerRange.upperBound]
            let leftover = buffer[headerRange.upperBound...]
            proxy(connection: connection, headerBlock: Data(headerBlock), leftover: Data(leftover), proto: proto)
            return
        }

        if buffer.count > 65_536 {
            sendError(connection, status: 400, message: "Header too large")
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                NSLog("Ports on Mac proxy read failed: \(error.localizedDescription)")
                return
            }

            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }

            if next.isEmpty, isComplete {
                connection.cancel()
                return
            }

            self.receiveHeaders(from: connection, buffer: next, proto: proto)
        }
    }

    private func proxy(connection client: NWConnection, headerBlock: Data, leftover: Data, proto: String) {
        guard let host = Self.host(fromHeaderBlock: headerBlock) else {
            sendError(client, status: 400, message: "Missing Host header")
            return
        }

        guard let port = routes[host] else {
            sendError(client, status: 502, message: "Unknown host")
            return
        }

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 1
        let parameters = NWParameters(tls: nil, tcp: tcp)
        let backend = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: parameters
        )

        backend.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let rewritten = Self.rewrittenHeaders(headerBlock, host: host, proto: proto)
                backend.send(content: rewritten + leftover, completion: .contentProcessed { error in
                    if let error {
                        NSLog("Ports on Mac proxy write failed: \(error.localizedDescription)")
                        client.cancel()
                        backend.cancel()
                        return
                    }
                    self?.splice(client, backend)
                    self?.splice(backend, client)
                })
            case .failed(let error):
                NSLog("Ports on Mac backend connect failed: \(error.localizedDescription)")
                self?.sendError(client, status: 502, message: "Upstream unavailable")
                backend.cancel()
            case .cancelled:
                client.cancel()
            default:
                break
            }
        }

        backend.start(queue: queue)
    }

    private func splice(_ from: NWConnection, _ to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if let error {
                to.cancel()
                from.cancel()
                return
            }

            if let data, !data.isEmpty {
                to.send(content: data, isComplete: isComplete, completion: .contentProcessed { sendError in
                    if sendError != nil || isComplete {
                        from.cancel()
                        to.cancel()
                        return
                    }
                    self?.splice(from, to)
                })
                return
            }

            if isComplete {
                to.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                    to.cancel()
                    from.cancel()
                })
                return
            }

            self?.splice(from, to)
        }
    }

    private func sendError(_ connection: NWConnection, status: Int, message: String) {
        let reason = status == 400 ? "Bad Request" : "Bad Gateway"
        let body = Data(message.utf8)
        let response = Data(
            """
            HTTP/1.1 \(status) \(reason)\r
            Connection: close\r
            Content-Type: text/plain; charset=utf-8\r
            Content-Length: \(body.count)\r
            \r
            """.utf8
        ) + body

        connection.send(content: response, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func host(fromHeaderBlock data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.lowercased().hasPrefix("host:") else { continue }

            var value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("["), let close = value.firstIndex(of: "]") {
                return String(value[...close]).lowercased()
            }
            if let colon = value.lastIndex(of: ":"), Int(value[value.index(after: colon)...]) != nil {
                value = String(value[..<colon])
            }
            return value.lowercased()
        }

        return nil
    }

    static func rewrittenHeaders(_ headerBlock: Data, host: String, proto: String = "http") -> Data {
        guard var text = String(data: headerBlock, encoding: .utf8) ?? String(data: headerBlock, encoding: .isoLatin1) else {
            return headerBlock
        }

        if text.hasSuffix("\r\n\r\n") {
            text.removeLast(4)
        } else if text.hasSuffix("\n\n") {
            text.removeLast(2)
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var value = String(line)
            if value.hasSuffix("\r") {
                value.removeLast()
            }
            return value
        }

        lines.removeAll { line in
            let lowered = line.lowercased()
            return lowered.hasPrefix("x-forwarded-for:")
                || lowered.hasPrefix("x-forwarded-proto:")
                || lowered.hasPrefix("x-forwarded-host:")
        }

        let insertAt = lines.firstIndex { $0.lowercased().hasPrefix("host:") }.map { $0 + 1 } ?? lines.count
        let forwarded = [
            "X-Forwarded-For: 127.0.0.1",
            "X-Forwarded-Proto: \(proto)",
            "X-Forwarded-Host: \(host)"
        ]
        for header in forwarded.reversed() {
            lines.insert(header, at: insertAt)
        }

        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }
}

private final class BindWait: @unchecked Sendable {
    let lock = NSLock()
    let group = DispatchGroup()
    var finished = false
    var error: Error?
}
