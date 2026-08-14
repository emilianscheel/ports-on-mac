import Foundation
import IOKit

enum PolarLicenseError: LocalizedError {
    case message(String)
    case network
    case rejected

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        case .network:
            return "Couldn’t reach Polar. Check your connection and try again."
        case .rejected:
            return "This license key isn’t valid on this Mac."
        }
    }
}

struct PolarLicenseActivation: Sendable {
    let id: String
}

struct PolarLicenseValidation: Sendable {
    let status: String
}

final class PolarLicenseClient: Sendable {
    static let shared = PolarLicenseClient()

    private init() {}

    private var organizationID: String {
        Bundle.main.object(forInfoDictionaryKey: "PolarOrganizationID") as? String
            ?? "865b2f78-d4cd-4364-8e78-c1c92a07288f"
    }

    func activate(key: String) async throws -> PolarLicenseActivation {
        var body: [String: Any] = [
            "key": key,
            "organization_id": organizationID,
            "label": Host.current().localizedName ?? "Mac",
        ]
        if let uuid = Self.platformUUID() {
            body["conditions"] = ["platform_uuid": uuid]
        }

        let json = try await post(
            path: "/v1/customer-portal/license-keys/activate",
            body: body
        )
        guard let id = json["id"] as? String else {
            throw PolarLicenseError.message("Polar did not return an activation id.")
        }
        return PolarLicenseActivation(id: id)
    }

    func validate(key: String, activationId: String) async throws -> PolarLicenseValidation {
        var body: [String: Any] = [
            "key": key,
            "organization_id": organizationID,
            "activation_id": activationId,
        ]
        if let uuid = Self.platformUUID() {
            body["conditions"] = ["platform_uuid": uuid]
        }

        let json = try await post(
            path: "/v1/customer-portal/license-keys/validate",
            body: body
        )
        let status = json["status"] as? String ?? ""
        if status != "granted" {
            throw PolarLicenseError.rejected
        }
        return PolarLicenseValidation(status: status)
    }

    private func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.polar.sh\(path)") else {
            throw PolarLicenseError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PolarLicenseError.network
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if (200..<300).contains(statusCode) {
            return json
        }

        if statusCode == 404 || statusCode == 403 {
            throw PolarLicenseError.rejected
        }

        throw PolarLicenseError.message(Self.errorMessage(from: json, fallbackStatus: statusCode))
    }

    private static func errorMessage(from json: [String: Any], fallbackStatus: Int) -> String {
        if let detail = json["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        if let details = json["detail"] as? [[String: Any]] {
            let messages = details.compactMap { $0["msg"] as? String }
            if !messages.isEmpty {
                return messages.joined(separator: " ")
            }
        }
        return "Polar returned HTTP \(fallbackStatus)."
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let cf = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return cf as? String
    }
}
