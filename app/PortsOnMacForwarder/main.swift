import Foundation
import Network
import Security

private let forwarderDelegate = ForwarderListenerDelegate()
private let xpcListener = NSXPCListener(machServiceName: ProxyConstants.machServiceName)
xpcListener.delegate = forwarderDelegate
xpcListener.resume()
RunLoop.main.run()

private final class ForwarderListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard ForwarderSecurity.isTrustedCaller(newConnection) else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: ProxyHelperXPCProtocol.self)
        newConnection.exportedObject = ForwarderService.shared
        newConnection.resume()
        return true
    }
}

private enum ForwarderSecurity {
    static func isTrustedCaller(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary

        var secCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &secCode) == errSecSuccess, let secCode else {
            NSLog("PortsOnMacForwarder rejected caller pid \(pid): could not copy code")
            return false
        }

        var secStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(secCode, [], &secStatic) == errSecSuccess, let secStatic else {
            NSLog("PortsOnMacForwarder rejected caller pid \(pid): could not copy static code")
            return false
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(secStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else {
            NSLog("PortsOnMacForwarder rejected caller pid \(pid): could not copy signing information")
            return false
        }

        if let identifier = info[kSecCodeInfoIdentifier as String] as? String, !identifier.isEmpty {
            if identifier == ProxyConstants.appBundleIdentifier {
                return true
            }
            NSLog("PortsOnMacForwarder rejected caller pid \(pid) identifier=\(identifier)")
            return false
        }

        if let plist = info[kSecCodeInfoPList as String] as? [String: Any] {
            let bundleID = plist[kCFBundleIdentifierKey as String] as? String
                ?? plist["CFBundleIdentifier"] as? String
            if bundleID == ProxyConstants.appBundleIdentifier {
                return true
            }
        }

        NSLog("PortsOnMacForwarder rejected caller pid \(pid) identifier=nil")
        return false
    }
}

private final class ForwarderService: NSObject, ProxyHelperXPCProtocol, @unchecked Sendable {
    static let shared = ForwarderService()

    private let httpForwarder = PortForwarder(
        listenPort: ProxyConstants.httpPort,
        backendPort: ProxyConstants.userProxyPort,
        sendsHTTPErrors: true
    )
    private let httpsForwarder = PortForwarder(
        listenPort: ProxyConstants.httpsPort,
        backendPort: ProxyConstants.userHTTPSProxyPort,
        sendsHTTPErrors: false
    )

    func setLiveDomains(_ domains: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        setLiveDomains(domains, enableHTTPS: false, withReply: reply)
    }

    func setLiveDomains(_ domains: [String], enableHTTPS: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        let unique = Array(Set(domains.map { $0.lowercased() })).sorted()
        do {
            if unique.isEmpty {
                try HostsFile.update(domains: [])
                try httpForwarder.setEnabled(false)
                try httpsForwarder.setEnabled(false)
            } else {
                try httpForwarder.setEnabled(true)
                try httpsForwarder.setEnabled(enableHTTPS)
                try HostsFile.update(domains: unique)
            }
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func installTrustedRoot(_ certificateDER: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try TrustedRoot.install(certificateDER)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}

private enum HostsFile {
    static func update(domains: [String]) throws {
        let original = try String(contentsOfFile: ProxyConstants.hostsPath, encoding: .utf8)
        let next = rewritten(original, domains: domains)
        guard next != original else { return }
        try next.write(toFile: ProxyConstants.hostsPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: ProxyConstants.hostsPath
        )
    }

    static func rewritten(_ original: String, domains: [String]) -> String {
        var lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if let begin = lines.firstIndex(of: ProxyConstants.hostsBeginMarker) {
            if let relativeEnd = lines[begin...].firstIndex(of: ProxyConstants.hostsEndMarker) {
                lines.removeSubrange(begin...relativeEnd)
            } else {
                lines.removeSubrange(begin...)
            }
        }

        while lines.last == "" {
            lines.removeLast()
        }

        if domains.isEmpty {
            return lines.joined(separator: "\n") + "\n"
        }

        var block = [ProxyConstants.hostsBeginMarker]
        for domain in domains {
            block.append("127.0.0.1 \(domain)")
            block.append("::1 \(domain)")
        }
        block.append(ProxyConstants.hostsEndMarker)

        return (lines + [""] + block).joined(separator: "\n") + "\n"
    }
}

private enum TrustedRoot {
    static func install(_ der: Data) throws {
        if isTrusted(der) {
            return
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ports-on-mac-ca-\(UUID().uuidString).cer")
        try der.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-trusted-cert",
            "-d",
            "-r", "trustRoot",
            "-p", "ssl",
            "-p", "basic",
            "-k", "/Library/Keychains/System.keychain",
            temp.path
        ]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 || isTrusted(der) {
            return
        }

        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw NSError(
            domain: "PortsOnMacForwarder",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: message?.isEmpty == false
                    ? message!
                    : "Could not trust the local HTTPS certificate."
            ]
        )
    }

    static func isTrusted(_ der: Data) -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return false
        }

        var settings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, .admin, &settings)
        return status == errSecSuccess
    }
}

private final class BindState: @unchecked Sendable {
    let lock = NSLock()
    let group = DispatchGroup()
    var finished = false
    var error: Error?
}

private final class PortForwarder: @unchecked Sendable {
    private let listenPort: UInt16
    private let backendPort: UInt16
    private let sendsHTTPErrors: Bool
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var listener: NWListener?

    init(listenPort: UInt16, backendPort: UInt16, sendsHTTPErrors: Bool) {
        self.listenPort = listenPort
        self.backendPort = backendPort
        self.sendsHTTPErrors = sendsHTTPErrors
        self.queue = DispatchQueue(label: "com.emilianscheel.ports-on-mac.forwarder.\(listenPort)")
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try start()
        } else {
            stop()
        }
    }

    private func start() throws {
        lock.lock()
        if listener != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: listenPort)!)

        let bindState = BindState()
        bindState.group.enter()
        listener.stateUpdateHandler = { state in
            bindState.lock.lock()
            defer { bindState.lock.unlock() }
            guard !bindState.finished else { return }

            switch state {
            case .ready:
                bindState.finished = true
                bindState.group.leave()
            case .failed(let error):
                bindState.finished = true
                bindState.error = error
                bindState.group.leave()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.forward(connection)
        }
        listener.start(queue: queue)

        let waitResult = bindState.group.wait(timeout: .now() + 2)
        if let startError = bindState.error {
            listener.cancel()
            throw startError
        }
        if waitResult == .timedOut {
            listener.cancel()
            throw NSError(
                domain: "PortsOnMacForwarder",
                code: Int(listenPort),
                userInfo: [NSLocalizedDescriptionKey: "Timed out binding port \(listenPort). Another process may already be using it."]
            )
        }

        lock.lock()
        self.listener = listener
        lock.unlock()
    }

    private func stop() {
        lock.lock()
        listener?.cancel()
        listener = nil
        lock.unlock()
    }

    private func forward(_ client: NWConnection) {
        client.start(queue: queue)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 1
        let parameters = NWParameters(tls: nil, tcp: tcp)
        let backend = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: backendPort)!,
            using: parameters
        )

        backend.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.splice(client, backend)
                self?.splice(backend, client)
            case .failed:
                if self?.sendsHTTPErrors == true {
                    self?.sendBadGateway(client)
                } else {
                    client.cancel()
                }
                backend.cancel()
            case .cancelled:
                client.cancel()
                backend.cancel()
            default:
                break
            }
        }

        backend.start(queue: queue)
    }

    private func sendBadGateway(_ connection: NWConnection) {
        let body = Data("Upstream unavailable\n".utf8)
        let response = Data(
            """
            HTTP/1.1 502 Bad Gateway\r
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

    private func splice(_ from: NWConnection, _ to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                from.cancel()
                to.cancel()
                return
            }

            if let data, !data.isEmpty {
                to.send(content: data, isComplete: isComplete, completion: .contentProcessed { sendError in
                    if sendError != nil || isComplete {
                        from.cancel()
                        to.cancel()
                        return
                    }
                    self.splice(from, to)
                })
                return
            }

            if isComplete {
                to.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                    from.cancel()
                    to.cancel()
                })
                return
            }

            self.splice(from, to)
        }
    }
}
