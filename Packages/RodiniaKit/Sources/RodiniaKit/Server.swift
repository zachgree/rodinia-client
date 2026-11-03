import Foundation

/// One VLESS endpoint, as described by a `vless://` share link.
public struct Server: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var address: String
    public var port: Int
    public var uuid: String
    public var flow: String
    public var network: String
    public var security: String
    public var sni: String
    public var publicKey: String
    public var shortId: String
    public var fingerprint: String
    public var spiderX: String

    /// Stable across refreshes as long as the endpoint itself doesn't change,
    /// so a selection survives a subscription update.
    public var id: String { "\(uuid)@\(address):\(port)" }

    public init(
        name: String, address: String, port: Int, uuid: String,
        flow: String = "", network: String = "tcp", security: String = "reality",
        sni: String = "", publicKey: String = "", shortId: String = "",
        fingerprint: String = "chrome", spiderX: String = ""
    ) {
        self.name = name
        self.address = address
        self.port = port
        self.uuid = uuid
        self.flow = flow
        self.network = network
        self.security = security
        self.sni = sni
        self.publicKey = publicKey
        self.shortId = shortId
        self.fingerprint = fingerprint
        self.spiderX = spiderX
    }
}

// MARK: - vless:// parsing

extension Server {
    public enum LinkError: Error, Equatable {
        case notVLESS
        case malformed
        case unsupported(String)
    }

    /// Parses `vless://uuid@host:port?type=tcp&security=reality&sni=…&pbk=…&sid=…&fp=…#Name`.
    public init(link: String) throws {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("vless://") else { throw LinkError.notVLESS }
        guard let components = URLComponents(string: trimmed),
              let uuid = components.user, !uuid.isEmpty,
              var host = components.host, !host.isEmpty,
              let port = components.port, (1...65535).contains(port)
        else { throw LinkError.malformed }

        // URLComponents keeps the brackets on IPv6 literals; Xray wants the bare address.
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }

        let network = query["type"].flatMap { $0.isEmpty ? nil : $0 } ?? "tcp"
        let security = query["security"].flatMap { $0.isEmpty ? nil : $0 } ?? "none"
        guard network == "tcp" else { throw LinkError.unsupported("transport \(network)") }
        guard security == "reality" || security == "tls" || security == "none" else {
            throw LinkError.unsupported("security \(security)")
        }
        if security == "reality", (query["pbk"] ?? "").isEmpty {
            throw LinkError.malformed
        }

        let fragment = components.fragment?.removingPercentEncoding ?? components.fragment ?? ""
        self.init(
            name: fragment.isEmpty ? host : fragment,
            address: host,
            port: port,
            uuid: uuid.removingPercentEncoding ?? uuid,
            flow: query["flow"] ?? "",
            network: network,
            security: security,
            sni: query["sni"] ?? "",
            publicKey: query["pbk"] ?? "",
            shortId: query["sid"] ?? "",
            fingerprint: query["fp"].flatMap { $0.isEmpty ? nil : $0 } ?? "chrome",
            spiderX: query["spx"].map { $0.removingPercentEncoding ?? $0 } ?? ""
        )
    }
}

// MARK: - presentation

extension Server {
    /// ISO region guessed from an emoji flag or a country word in the name.
    public var regionCode: String? {
        if let flag = name.unicodeScalars.regionFromFlag { return flag }
        let words = name.uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        for word in words {
            if let code = Self.regionWords[word] { return code }
        }
        return nil
    }

    /// Regional indicator emoji for `regionCode`.
    public var flag: String? {
        guard let code = regionCode, code.count == 2 else { return nil }
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 - 65 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Localised country name when the region is known, else the name with any emoji flag removed.
    public var displayName: String {
        let stripped = String(String.UnicodeScalarView(name.unicodeScalars.filter { !(0x1F1E6...0x1F1FF).contains($0.value) }))
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? address : stripped
    }

    private static let regionWords: [String: String] = [
        "UK": "GB", "GB": "GB", "BRITAIN": "GB", "ENGLAND": "GB", "LONDON": "GB", "KINGDOM": "GB",
        "DE": "DE", "GERMANY": "DE", "GERMAN": "DE", "FRANKFURT": "DE", "BERLIN": "DE",
        "US": "US", "USA": "US", "AMERICA": "US", "STATES": "US",
        "NL": "NL", "NETHERLANDS": "NL", "AMSTERDAM": "NL",
        "FR": "FR", "FRANCE": "FR", "PARIS": "FR",
        "FI": "FI", "FINLAND": "FI", "HELSINKI": "FI",
        "SE": "SE", "SWEDEN": "SE", "STOCKHOLM": "SE",
        "CH": "CH", "SWITZERLAND": "CH", "ZURICH": "CH",
        "CA": "CA", "CANADA": "CA", "TORONTO": "CA",
        "JP": "JP", "JAPAN": "JP", "TOKYO": "JP",
        "SG": "SG", "SINGAPORE": "SG",
        "TR": "TR", "TURKEY": "TR", "ISTANBUL": "TR",
        "AE": "AE", "UAE": "AE", "DUBAI": "AE",
        "PL": "PL", "POLAND": "PL", "WARSAW": "PL",
        "ES": "ES", "SPAIN": "ES", "MADRID": "ES",
        "IT": "IT", "ITALY": "IT", "MILAN": "IT",
    ]
}

extension String.UnicodeScalarView {
    fileprivate var regionFromFlag: String? {
        let indicators = filter { (0x1F1E6...0x1F1FF).contains($0.value) }.map { $0.value }
        guard indicators.count >= 2 else { return nil }
        let letters = indicators.prefix(2).compactMap { UnicodeScalar($0 - 0x1F1E6 + 65) }
        return String(String.UnicodeScalarView(letters))
    }
}

extension Server {
    /// "United Kingdom" for a UK server, in the user's language.
    public var countryName: String? {
        regionCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
    }
}
