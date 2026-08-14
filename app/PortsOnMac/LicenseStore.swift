import Foundation
import Security

final class LicenseStore: @unchecked Sendable {
    static let shared = LicenseStore()

    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    private let queue = DispatchQueue(label: "com.emilianscheel.ports-on-mac.license")
    private var state: LicenseState

    private init() {
        state = LicenseState.load() ?? LicenseState(trialStartedAt: Date())
        state.save()
    }

    func ensureTrialStarted() {
        queue.sync {
            if LicenseState.load() == nil {
                state.save()
            }
        }
    }

    var needsLicenseMenu: Bool {
        queue.sync { state.key == nil }
    }

    var isLicensed: Bool {
        queue.sync { state.isLicensed }
    }

    var hasDomainAccess: Bool {
        queue.sync { state.isLicensed || state.trialRemaining > 0 }
    }

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PolarLicenseError.message("Enter a license key.")
        }

        let activation = try await PolarLicenseClient.shared.activate(key: trimmed)
        _ = try await PolarLicenseClient.shared.validate(
            key: trimmed,
            activationId: activation.id
        )

        queue.sync {
            state.key = trimmed
            state.activationId = activation.id
            state.save()
        }
    }

    func refreshValidation() async {
        let snapshot = queue.sync { (state.key, state.activationId) }
        guard let key = snapshot.0, let activationId = snapshot.1 else { return }

        do {
            let validated = try await PolarLicenseClient.shared.validate(
                key: key,
                activationId: activationId
            )
            if validated.status != "granted" {
                clearLicense()
            }
        } catch PolarLicenseError.network {
            return
        } catch PolarLicenseError.rejected {
            clearLicense()
        } catch {
            return
        }
    }

    private func clearLicense() {
        queue.sync {
            state.key = nil
            state.activationId = nil
            state.save()
        }
    }
}

private struct LicenseState: Codable {
    var trialStartedAt: Date
    var key: String?
    var activationId: String?

    var isLicensed: Bool {
        key != nil && activationId != nil
    }

    var trialRemaining: TimeInterval {
        max(0, trialStartedAt.addingTimeInterval(LicenseStore.trialDuration).timeIntervalSinceNow)
    }

    private static let service = "com.emilianscheel.ports-on-mac.license"
    private static let account = "state"

    static func load() -> LicenseState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicenseState.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
