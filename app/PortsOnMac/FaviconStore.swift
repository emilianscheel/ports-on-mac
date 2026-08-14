import AppKit
import Foundation

final class FaviconStore: @unchecked Sendable {
    static let shared = FaviconStore()

    private let queue = DispatchQueue(label: "com.emilianscheel.ports-on-mac.favicon")
    private var images: [String: NSImage] = [:]
    private var missing: Set<String> = []
    private var inflight: Set<String> = []
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    func cachedImage(for entry: PortEntry, domain: String?, usesHTTPS: Bool = false) -> NSImage? {
        queue.sync {
            for key in cacheKeys(for: entry, domain: domain, usesHTTPS: usesHTTPS) {
                if let image = images[key] {
                    return image
                }
            }
            return nil
        }
    }

    func prefetch(for entry: PortEntry, domain: String?, usesHTTPS: Bool = false) {
        let keys = cacheKeys(for: entry, domain: domain, usesHTTPS: usesHTTPS)
        let origins = iconOrigins(for: entry, domain: domain, usesHTTPS: usesHTTPS)
        guard !keys.isEmpty, !origins.isEmpty else { return }

        queue.async { [weak self] in
            guard let self else { return }
            if keys.contains(where: { self.images[$0] != nil }) {
                return
            }
            if keys.allSatisfy({ self.missing.contains($0) }) {
                return
            }
            if keys.contains(where: { self.inflight.contains($0) }) {
                return
            }
            for key in keys {
                self.inflight.insert(key)
            }
            self.fetchFirstImage(from: origins, keys: keys)
        }
    }

    private func fetchFirstImage(from origins: [URL], keys: [String]) {
        tryOrigins(origins) { data, mime in
            self.queue.async {
                let image = data.flatMap { Self.image(from: $0, mimeType: mime) }
                for key in keys {
                    self.inflight.remove(key)
                    if let image {
                        self.images[key] = image
                        self.missing.remove(key)
                    } else {
                        self.missing.insert(key)
                    }
                }
            }
        }
    }

    private func tryOrigins(_ origins: [URL], completion: @escaping @Sendable (Data?, String?) -> Void) {
        guard let origin = origins.first else {
            completion(nil, nil)
            return
        }

        fetchImage(from: origin) { [weak self] data, mime in
            if let data {
                completion(data, mime)
                return
            }
            self?.tryOrigins(Array(origins.dropFirst()), completion: completion)
        }
    }

    private func fetchImage(from origin: URL, completion: @escaping @Sendable (Data?, String?) -> Void) {
        let faviconURL = origin.appendingPathComponent("favicon.ico")
        fetchData(from: faviconURL) { [weak self] data, mime in
            if let data, Self.image(from: data, mimeType: mime) != nil {
                completion(data, mime)
                return
            }

            guard let self else {
                completion(nil, nil)
                return
            }

            self.fetchData(from: origin) { data, mime in
                guard let data, Self.looksLikeHTML(data, mimeType: mime),
                      let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                      let href = Self.iconHREF(from: html, base: origin) else {
                    completion(nil, nil)
                    return
                }

                self.fetchData(from: href) { iconData, iconMime in
                    guard let iconData, Self.image(from: iconData, mimeType: iconMime) != nil else {
                        completion(nil, nil)
                        return
                    }
                    completion(iconData, iconMime)
                }
            }
        }
    }

    private func fetchData(from url: URL, completion: @escaping @Sendable (Data?, String?) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            guard let data, !data.isEmpty, let http, (200..<300).contains(http.statusCode), data.count <= 512 * 1024 else {
                completion(nil, nil)
                return
            }
            completion(data, http.value(forHTTPHeaderField: "Content-Type"))
        }.resume()
    }

    private func cacheKeys(for entry: PortEntry, domain: String?, usesHTTPS: Bool) -> [String] {
        iconOrigins(for: entry, domain: domain, usesHTTPS: usesHTTPS).map(\.absoluteString)
    }

    private func iconOrigins(for entry: PortEntry, domain: String?, usesHTTPS: Bool) -> [URL] {
        var origins: [URL] = []
        if let domain {
            let scheme = usesHTTPS ? "https" : "http"
            if let url = URL(string: "\(scheme)://\(domain)") {
                origins.append(url)
            }
        }
        if let openURL = entry.openURL {
            origins.append(openURL)
        }
        return origins
    }

    private static func image(from data: Data, mimeType: String?) -> NSImage? {
        let mime = mimeType?.lowercased() ?? ""
        if mime.contains("svg") || mime.contains("html") || mime.contains("json") || mime.contains("text/plain") {
            return nil
        }
        if looksLikeHTML(data, mimeType: mimeType) {
            return nil
        }
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
    }

    private static func looksLikeHTML(_ data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("html") == true {
            return true
        }
        guard let prefix = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html")
    }

    private static func iconHREF(from html: String, base: URL) -> URL? {
        let pattern = /<link\s+[^>]*rel=["'][^"']*icon[^"']*["'][^>]*>/
        let lowered = html.lowercased()
        guard let match = lowered.firstMatch(of: pattern) else {
            return nil
        }

        let tag = String(match.0)
        let hrefPattern = /href=["']([^"']+)["']/
        guard let hrefMatch = tag.firstMatch(of: hrefPattern) else {
            return nil
        }

        let href = String(hrefMatch.1)
        if href.contains(".svg") {
            return nil
        }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }
}
