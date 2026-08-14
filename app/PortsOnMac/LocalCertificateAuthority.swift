import Crypto
import Foundation
import Security
import X509

enum LocalCertificateError: LocalizedError {
    case encoding
    case secKey
    case identity

    var errorDescription: String? {
        switch self {
        case .encoding:
            return "Could not encode the local HTTPS certificate."
        case .secKey:
            return "Could not import the local HTTPS key."
        case .identity:
            return "Could not create a local HTTPS identity."
        }
    }
}

final class LocalCertificateAuthority: @unchecked Sendable {
    static let shared = LocalCertificateAuthority()

    private let lock = NSLock()
    private let directory: URL
    private var caKey: P256.Signing.PrivateKey?
    private var caCertificate: Certificate?
    private var cachedDomains: [String] = []
    private var cachedIdentity: SecIdentity?

    init(directory: URL? = nil) {
        self.directory = directory ?? ProxyConstants.applicationSupportDirectory.appendingPathComponent("certs", isDirectory: true)
    }

    var certificateDER: Data {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            try prepareCALocked()
            let secCertificate = try SecCertificate.makeWithCertificate(caCertificate!)
            return SecCertificateCopyData(secCertificate) as Data
        }
    }

    func prepareCA() throws {
        lock.lock()
        defer { lock.unlock() }
        try prepareCALocked()
    }

    func hasUserTrust() throws -> Bool {
        let der = try certificateDER
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw LocalCertificateError.encoding
        }
        return Self.isTrusted(certificate)
    }

    func installUserTrust() throws {
        let der = try certificateDER
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw LocalCertificateError.encoding
        }
        if Self.isTrusted(certificate) {
            return
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: "Ports on Mac Local CA"
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(addStatus),
                userInfo: [NSLocalizedDescriptionKey: "Could not store the local HTTPS certificate."]
            )
        }

        let status = SecTrustSettingsSetTrustSettings(certificate, .user, nil)
        if status == errSecSuccess || Self.isTrusted(certificate) {
            return
        }

        try Self.addTrustedCertWithSecurityTool(der)
        if Self.isTrusted(certificate) {
            return
        }

        let message = SecCopyErrorMessageString(status, nil) as String?
            ?? "Could not trust the local HTTPS certificate."
        throw NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func isTrusted(_ certificate: SecCertificate) -> Bool {
        var settings: CFArray?
        if SecTrustSettingsCopyTrustSettings(certificate, .user, &settings) == errSecSuccess {
            return true
        }
        if SecTrustSettingsCopyTrustSettings(certificate, .admin, &settings) == errSecSuccess {
            return true
        }
        return false
    }

    private static func addTrustedCertWithSecurityTool(_ der: Data) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ports-on-mac-ca-\(UUID().uuidString).cer")
        try der.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-trusted-cert",
            "-r", "trustRoot",
            "-p", "ssl",
            "-p", "basic",
            temp.path
        ]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return
        }

        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw NSError(
            domain: "PortsOnMac",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: message?.isEmpty == false
                    ? message!
                    : "Could not trust the local HTTPS certificate."
            ]
        )
    }

    func identity(for domains: [String]) throws -> SecIdentity {
        let normalized = Array(Set(domains.map { $0.lowercased() })).sorted()
        lock.lock()
        defer { lock.unlock() }

        if normalized == cachedDomains, let cachedIdentity {
            return cachedIdentity
        }

        try prepareCALocked()
        let identity = try issueLeafLocked(for: normalized)
        cachedDomains = normalized
        cachedIdentity = identity
        return identity
    }

    private func prepareCALocked() throws {
        if caKey != nil, caCertificate != nil {
            return
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let keyURL = directory.appendingPathComponent("ca.key.pem")
        let certURL = directory.appendingPathComponent("ca.crt.pem")

        if let keyPEM = try? String(contentsOf: keyURL, encoding: .utf8),
           let certPEM = try? String(contentsOf: certURL, encoding: .utf8),
           let key = try? P256.Signing.PrivateKey(pemRepresentation: keyPEM),
           let certificate = try? Certificate(pemEncoded: certPEM) {
            caKey = key
            caCertificate = certificate
            return
        }

        let key = P256.Signing.PrivateKey()
        let issuerKey = Certificate.PrivateKey(key)
        let name = try DistinguishedName {
            CommonName("Ports on Mac Local CA")
            OrganizationName("Ports on Mac")
        }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: issuerKey.publicKey,
            notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(10 * 365 * 24 * 60 * 60),
            issuer: name,
            subject: name,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                SubjectKeyIdentifier(hash: issuerKey.publicKey)
            },
            issuerPrivateKey: issuerKey
        )

        try write(key.pemRepresentation, to: keyURL)
        try write(certificate.serializeAsPEM().pemString, to: certURL)
        caKey = key
        caCertificate = certificate
    }

    private func issueLeafLocked(for domains: [String]) throws -> SecIdentity {
        guard let caKey, let caCertificate else {
            throw LocalCertificateError.encoding
        }

        let leafKey = P256.Signing.PrivateKey()
        let leafPrivateKey = Certificate.PrivateKey(leafKey)
        let caPrivateKey = Certificate.PrivateKey(caKey)
        let commonName = domains.first ?? "localhost"
        let subject = try DistinguishedName {
            CommonName(commonName)
        }
        let now = Date()
        let leaf = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: leafPrivateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(397 * 24 * 60 * 60),
            issuer: caCertificate.subject,
            subject: subject,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames(domains.map { .dnsName($0) })
                SubjectKeyIdentifier(hash: leafPrivateKey.publicKey)
                AuthorityKeyIdentifier(keyIdentifier: SubjectKeyIdentifier(hash: caPrivateKey.publicKey).keyIdentifier)
            },
            issuerPrivateKey: caPrivateKey
        )

        let secCertificate = try SecCertificate.makeWithCertificate(leaf)
        let secKey = try Self.secKey(from: leafKey)
        guard let identity = SecIdentityCreate(nil, secCertificate, secKey) else {
            throw LocalCertificateError.identity
        }
        return identity
    }

    private func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func secKey(from key: P256.Signing.PrivateKey) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(key.x963Representation as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() as Error? ?? LocalCertificateError.secKey
        }
        return secKey
    }
}
