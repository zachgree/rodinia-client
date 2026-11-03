import Foundation

/// Traffic and expiry from the `Subscription-Userinfo` header.
public struct Usage: Codable, Hashable, Sendable {
    public var upload: Int64
    public var download: Int64
    /// Total allowance in bytes; nil means unlimited.
    public var total: Int64?
    public var expires: Date?

    public var used: Int64 { upload + download }

    /// 0...1 when there is a limit.
    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(total)))
    }

    public init(upload: Int64 = 0, download: Int64 = 0, total: Int64? = nil, expires: Date? = nil) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expires = expires
    }

    /// `upload=0; download=123; total=10737418240; expire=1704067200`
    public init?(header: String) {
        var values: [String: Int64] = [:]
        for part in header.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let number = Int64(pair[1]) else { continue }
            values[pair[0].lowercased()] = number
        }
        guard !values.isEmpty else { return nil }
        self.init(
            upload: values["upload"] ?? 0,
            download: values["download"] ?? 0,
            total: values["total"].flatMap { $0 > 0 ? $0 : nil },
            expires: values["expire"].flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        )
    }
}

/// A subscription URL and what it last returned.
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL?
    public var title: String
    public var servers: [Server]
    public var usage: Usage?
    public var refreshInterval: TimeInterval
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), url: URL?, title: String, servers: [Server],
        usage: Usage? = nil, refreshInterval: TimeInterval = 6 * 3600, updatedAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.servers = servers
        self.usage = usage
        self.refreshInterval = refreshInterval
        self.updatedAt = updatedAt
    }

    public var isStale: Bool { url != nil && Date.now.timeIntervalSince(updatedAt) > refreshInterval }
}

public enum SubscriptionError: LocalizedError, Equatable {
    case invalidURL
    case http(Int, String)
    case empty
    case noUsableServers(skipped: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a subscription link."
        case .http(403, let body) where !body.isEmpty: body
        case .http(404, _): "This subscription link isn't valid any more."
        case .http(let code, _): "The server answered with error \(code)."
        case .empty: "The subscription is empty."
        case .noUsableServers(let skipped):
            skipped > 0
                ? "None of the \(skipped) servers use a protocol this app supports yet (VLESS over TCP)."
                : "The subscription has no servers."
        }
    }
}

public enum Subscription {
    /// Parses a subscription body: base64 (standard or URL-safe, padded or not)
    /// or plain text, one share link per line.
    public static func parse(body: String) throws -> [Server] {
        let text = decodeBase64(body) ?? body
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw SubscriptionError.empty }

        var servers: [Server] = []
        var skipped = 0
        for line in lines {
            if let server = try? Server(link: line) {
                if !servers.contains(where: { $0.id == server.id }) { servers.append(server) }
            } else {
                skipped += 1
            }
        }
        guard !servers.isEmpty else { throw SubscriptionError.noUsableServers(skipped: skipped) }
        return tidyNames(servers)
    }

    /// Panels often name entries "<server>-<user>". When every name shares the
    /// same "-suffix", it carries no information, so drop it.
    static func tidyNames(_ servers: [Server]) -> [Server] {
        guard servers.count > 1 else { return servers }
        let suffixes = servers.map { server -> Substring? in
            guard let dash = server.name.lastIndex(of: "-") else { return nil }
            return server.name[dash...]
        }
        guard let first = suffixes.first, let suffix = first, suffix.count > 1,
              suffixes.allSatisfy({ $0 == suffix })
        else { return servers }
        return servers.map { server in
            var copy = server
            copy.name = String(server.name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            return copy
        }
    }

    static func decodeBase64(_ string: String) -> String? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !s.isEmpty, !s.contains("://") else { return nil }
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s), let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// `Profile-Title` may be plain or `base64:…`.
    static func decodeTitle(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("base64:") { return decodeBase64(String(raw.dropFirst(7))) }
        return raw
    }

    /// Accepts anything a user might paste: a subscription URL, a bare `vless://` link,
    /// or a `rodinia://add?url=…` deep link.
    public static func normalise(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "https", "http":
            return url.host() == nil ? nil : url
        case "rodinia":
            let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "url" }?.value
            return inner.flatMap(normalise)
        default:
            return nil
        }
    }
}

/// Fetches and refreshes profiles.
public struct SubscriptionClient: Sendable {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ url: URL, into existing: Profile? = nil) async throws -> Profile {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Rodinia/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let body = String(decoding: data, as: UTF8.self)

        if let code = http?.statusCode, !(200..<300).contains(code) {
            throw SubscriptionError.http(code, body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200).description)
        }

        let servers = try Subscription.parse(body: body)
        let header = { (name: String) in http?.value(forHTTPHeaderField: name) }
        let hours = header("Profile-Update-Interval").flatMap(Double.init) ?? 6

        return Profile(
            id: existing?.id ?? UUID(),
            url: url,
            title: Subscription.decodeTitle(header("Profile-Title")) ?? existing?.title ?? url.host() ?? "VPN",
            servers: servers,
            usage: header("Subscription-Userinfo").flatMap(Usage.init(header:)),
            refreshInterval: max(900, hours * 3600),
            updatedAt: .now
        )
    }
}
