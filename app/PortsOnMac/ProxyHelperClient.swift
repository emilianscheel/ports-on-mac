import Foundation
import ServiceManagement

enum ProxyHelperError: LocalizedError {
    case requiresApproval
    case notEnabled
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Enable the Ports on Mac helper in System Settings → General → Login Items & Extensions so local domains can use port 80."
        case .notEnabled:
            return "The Ports on Mac helper is not enabled."
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

    func syncLiveDomains(_ domains: [String]) async throws {
        var lastError: Error = ProxyHelperError.notEnabled
        for attempt in 0..<8 {
            do {
                try await setLiveDomains(domains)
                return
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
            }
        }
        throw lastError
    }

    func clearLiveDomainsBlocking() {
        guard daemon.status == .enabled else { return }

        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            try? await self.setLiveDomains([])
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    private func setLiveDomains(_ domains: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NSXPCConnection(
                machServiceName: ProxyConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: ProxyHelperXPCProtocol.self)
            connection.resume()

            let resumeOnce = ResumeOnce(continuation)
            connection.invalidationHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.notEnabled)
            }
            connection.interruptionHandler = {
                resumeOnce.resume(throwing: ProxyHelperError.notEnabled)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                resumeOnce.resume(throwing: error)
                connection.invalidate()
            }

            guard let helper = proxy as? ProxyHelperXPCProtocol else {
                resumeOnce.resume(throwing: ProxyHelperError.notEnabled)
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
