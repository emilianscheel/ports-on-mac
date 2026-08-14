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
            return "Enable the Ports on Mac helper in System Settings → General → Login Items & Extensions so local domains can use port 80 and HTTPS on port 443."
        case .notEnabled:
            return "The Ports on Mac helper is not enabled."
        case .unreachable:
            return "The Ports on Mac helper is installed but isn’t responding. If it appears in Login Items, toggle it off and on, or reinstall the app."
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

    func syncLiveDomains(_ domains: [String], enableHTTPS: Bool) async throws {
        try await performHelperCall {
            try await self.setLiveDomains(domains, enableHTTPS: enableHTTPS)
        }
    }

    func installTrustedRoot(_ certificateDER: Data) async throws {
        try await performHelperCall {
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

    private func performHelperCall(_ work: @escaping () async throws -> Void) async throws {
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

            if !repaired, daemon.status == .enabled {
                repaired = true
                do {
                    try repairHelper()
                } catch let error as ProxyHelperError {
                    switch error {
                    case .requiresApproval, .notEnabled:
                        throw error
                    default:
                        break
                    }
                } catch {
                    lastError = error
                }
                try await Task.sleep(for: .seconds(1))
                continue
            }

            try await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
        }

        throw lastError
    }

    private func repairHelper() throws {
        try daemon.register()
        switch daemon.status {
        case .enabled:
            return
        case .requiresApproval:
            throw ProxyHelperError.requiresApproval
        default:
            throw ProxyHelperError.notEnabled
        }
    }

    private func setLiveDomains(_ domains: [String], enableHTTPS: Bool) async throws {
        try await withHelper { helper, resumeOnce, connection in
            let reply: (Bool, String?) -> Void = { ok, message in
                if ok {
                    resumeOnce.resume()
                } else {
                    resumeOnce.resume(throwing: ProxyHelperError.remote(message ?? "The helper could not update local domains."))
                }
                connection.invalidate()
            }

            if enableHTTPS {
                helper.setLiveDomains(domains, enableHTTPS: true, withReply: reply)
            } else {
                helper.setLiveDomains(domains, withReply: reply)
            }
        }
    }

    private func installTrustedRootOnce(_ certificateDER: Data) async throws {
        try await withHelper { helper, resumeOnce, connection in
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

    private func withHelper(
        _ body: @escaping (ProxyHelperXPCProtocol, ResumeOnce, NSXPCConnection) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NSXPCConnection(
                machServiceName: ProxyConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: ProxyHelperXPCProtocol.self)
            connection.resume()

            let resumeOnce = ResumeOnce(continuation)
            connection.invalidationHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
            }
            connection.interruptionHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                resumeOnce.resume(throwing: Self.mappedXPCError(error))
                connection.invalidate()
            }

            guard let helper = proxy as? ProxyHelperXPCProtocol else {
                resumeOnce.resume(throwing: ProxyHelperError.unreachable)
                connection.invalidate()
                return
            }

            body(helper, resumeOnce, connection)
        }
    }

    private static func mappedXPCError(_ error: Error) -> Error {
        if error is ProxyHelperError {
            return error
        }
        return ProxyHelperError.unreachable
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
