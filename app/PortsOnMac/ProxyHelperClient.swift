import Foundation
import ServiceManagement

enum ProxyHelperError: LocalizedError {
    case requiresApproval
    case notEnabled
    case unreachable
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Allow Ports on Mac in System Settings → General → Login Items & Extensions → App Background Activity so local domains can use port 80 and HTTPS on port 443."
        case .notEnabled:
            return "The Ports on Mac helper is not enabled."
        case .unreachable:
            return "The Ports on Mac helper is installed but isn’t responding. If it appears under App Background Activity, toggle it off and on, or reinstall the app."
        case .remote(let message):
            return message
        }
    }
}

final class ProxyHelperClient: @unchecked Sendable {
    static let shared = ProxyHelperClient()

    private var daemon: SMAppService {
        SMAppService.daemon(plistName: ProxyConstants.launchDaemonPlistName)
    }

    var status: SMAppService.Status {
        daemon.status
    }

    static func replaceHelperFromCommandLine() -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var exitCode: Int32 = 1
        Task.detached {
            do {
                try await ProxyHelperClient.shared.replaceHelperAndWait()
                print("Replaced the Ports on Mac helper.")
                exitCode = 0
            } catch {
                fputs("Could not replace the Ports on Mac helper: \(error.localizedDescription)\n", stderr)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 45)
        return exitCode
    }

    func prepareForAssignment() throws {
        switch daemon.status {
        case .enabled:
            return
        case .notRegistered, .notFound:
            try daemon.register()
            switch daemon.status {
            case .enabled:
                return
            case .requiresApproval:
                throw ProxyHelperError.requiresApproval
            default:
                throw ProxyHelperError.notEnabled
            }
        case .requiresApproval:
            throw ProxyHelperError.requiresApproval
        default:
            throw ProxyHelperError.notEnabled
        }
    }

    func ensureCurrentHelper() async throws {
        if await helperSupportsCurrentProtocol() {
            return
        }
        try await replaceHelperAndWait()
    }

    func syncLiveDomains(_ domains: [String], enableHTTPS: Bool) async throws {
        try await performHelperCall(allowRepair: enableHTTPS) {
            try await self.setLiveDomains(domains, enableHTTPS: enableHTTPS)
        }
    }

    func installTrustedRoot(_ certificateDER: Data) async throws {
        try await performHelperCall(allowRepair: true) {
            try await self.installTrustedRootOnce(certificateDER)
        }
    }

    func clearLiveDomainsBlocking() {
        guard daemon.status == .enabled else { return }

        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            try? await self.setLiveDomains([], enableHTTPS: false)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    func replaceHelperAndWait() async throws {
        NSLog("Ports on Mac replacing helper (\(Self.statusName(daemon.status)))")
        if await helperSupportsCurrentProtocol() {
            NSLog("Ports on Mac helper is already current")
            return
        }

        var restartedWithAdmin = false
        if daemon.status == .enabled {
            do {
                try await daemon.unregister()
                let deadline = Date().addingTimeInterval(10)
                while daemon.status == .enabled, Date() < deadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                NSLog("Ports on Mac helper unregister failed: \(error.localizedDescription)")
                try kickstartHelperWithAdministrator()
                restartedWithAdmin = true
            }
        }

        if !restartedWithAdmin {
            switch daemon.status {
            case .enabled:
                do {
                    try daemon.register()
                } catch {
                    NSLog("Ports on Mac helper register while enabled: \(error.localizedDescription)")
                }
            case .notRegistered, .notFound:
                try daemon.register()
            case .requiresApproval:
                throw ProxyHelperError.requiresApproval
            default:
                throw ProxyHelperError.notEnabled
            }
        }

        if await waitForCurrentHelper(seconds: 10) {
            return
        }

        if !restartedWithAdmin {
            try kickstartHelperWithAdministrator()
        }

        if await waitForCurrentHelper(seconds: 20) {
            return
        }

        throw ProxyHelperError.unreachable
    }

    private func waitForCurrentHelper(seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await helperSupportsCurrentProtocol() {
                NSLog("Ports on Mac helper is current")
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func kickstartHelperWithAdministrator() throws {
        let command = "launchctl kickstart -k system/\(ProxyConstants.machServiceName)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(command)\" with administrator privileges"
        ]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProxyHelperError.remote(
                message?.isEmpty == false
                    ? message!
                    : "Could not restart the Ports on Mac helper. Enter your administrator password when asked."
            )
        }
    }

    private func helperSupportsCurrentProtocol() async -> Bool {
        do {
            let version = try await fetchHelperVersion()
            return version == ProxyConstants.helperProtocolVersion
        } catch {
            return false
        }
    }

    private func performHelperCall(allowRepair: Bool, _ work: @escaping () async throws -> Void) async throws {
        var repaired = false
        var lastError: Error = ProxyHelperError.unreachable

        for attempt in 0..<8 {
            do {
                try await work()
                return
            } catch let error as ProxyHelperError {
                switch error {
                case .requiresApproval, .notEnabled:
                    throw error
                default:
                    lastError = error
                }
            } catch {
                lastError = Self.mappedXPCError(error)
            }

            if allowRepair, !repaired, daemon.status == .enabled {
                repaired = true
                do {
                    try await replaceHelperAndWait()
                } catch let error as ProxyHelperError {
                    switch error {
                    case .requiresApproval, .notEnabled:
                        throw error
                    default:
                        lastError = error
                    }
                } catch {
                    NSLog("Ports on Mac helper repair failed: \(error.localizedDescription)")
                    lastError = error
                }
                continue
            }

            try await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
        }

        throw lastError
    }

    private func setLiveDomains(_ domains: [String], enableHTTPS: Bool) async throws {
        if enableHTTPS {
            try await withHelper(interface: NSXPCInterface(with: ProxyHelperHTTPSXPCProtocol.self)) { proxy, resumeOnce, connection in
                guard let helper = proxy as? ProxyHelperHTTPSXPCProtocol else {
                    resumeOnce.resume(throwing: ProxyHelperError.unreachable)
                    connection.invalidate()
                    return
                }
                helper.setLiveDomains(domains, enableHTTPS: true) { ok, message in
                    if ok {
                        resumeOnce.resume()
                    } else {
                        resumeOnce.resume(throwing: ProxyHelperError.remote(message ?? "The helper could not update local domains."))
                    }
                    connection.invalidate()
                }
            }
            return
        }

        try await withHelper(interface: NSXPCInterface(with: ProxyHelperHTTPXPCProtocol.self)) { proxy, resumeOnce, connection in
            guard let helper = proxy as? ProxyHelperHTTPXPCProtocol else {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
                connection.invalidate()
                return
            }
            helper.setLiveDomains(domains) { ok, message in
                if ok {
                    resumeOnce.resume()
                } else {
                    resumeOnce.resume(throwing: ProxyHelperError.remote(message ?? "The helper could not update local domains."))
                }
                connection.invalidate()
            }
        }
    }

    private func installTrustedRootOnce(_ certificateDER: Data) async throws {
        try await withHelper(interface: NSXPCInterface(with: ProxyHelperTrustXPCProtocol.self)) { proxy, resumeOnce, connection in
            guard let helper = proxy as? ProxyHelperTrustXPCProtocol else {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
                connection.invalidate()
                return
            }
            helper.installTrustedRoot(certificateDER) { ok, message in
                if ok {
                    resumeOnce.resume()
                } else {
                    resumeOnce.resume(throwing: ProxyHelperError.remote(message ?? "The helper could not trust the local HTTPS certificate."))
                }
                connection.invalidate()
            }
        }
    }

    private func fetchHelperVersion() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let connection = NSXPCConnection(
                machServiceName: ProxyConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: ProxyHelperVersionXPCProtocol.self)
            let resumeOnce = ResumeOnceValue<String>(continuation)
            connection.invalidationHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
            }
            connection.interruptionHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                resumeOnce.resume(throwing: Self.mappedXPCError(error))
                connection.invalidate()
            }

            guard let helper = proxy as? ProxyHelperVersionXPCProtocol else {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
                connection.invalidate()
                return
            }

            helper.helperVersion { version in
                resumeOnce.resume(returning: version)
                connection.invalidate()
            }
        }
    }

    private func withHelper(
        interface: NSXPCInterface,
        _ body: @escaping (Any, ResumeOnce, NSXPCConnection) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NSXPCConnection(
                machServiceName: ProxyConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = interface
            let resumeOnce = ResumeOnce(continuation)
            connection.invalidationHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
            }
            connection.interruptionHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                NSLog("Ports on Mac helper XPC error: \(error.localizedDescription)")
                resumeOnce.resume(throwing: Self.mappedXPCError(error))
                connection.invalidate()
            }

            body(proxy, resumeOnce, connection)
        }
    }

    private static func mappedXPCError(_ error: Error) -> Error {
        if error is ProxyHelperError {
            return error
        }
        return ProxyHelperError.unreachable
    }

    private static func statusName(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requiresApproval"
        case .notRegistered:
            return "notRegistered"
        case .notFound:
            return "notFound"
        @unknown default:
            return "unknown"
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

private final class ResumeOnceValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
