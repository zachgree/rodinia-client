import Foundation
import Testing
@testable import RodiniaKit

// Shaped exactly like RodiniaVPN's /api/sub output (generateVlessLink in server/services/xui.js),
// with made-up keys and ids.
let uk = "vless://3f1c2a9e-0b7d-4e55-9a10-6c2f8d1e4b77@203.0.113.10:80?type=tcp&security=reality&sni=www.yahoo.com&pbk=Zx0p8bQyJ3vL5tWm1nR2sK7dF9gH4jC6aE0uI8oP2lM&sid=a1b2c3d4e5f60718&fp=chrome&headerType=none&flow=#UK%20Server-alex"
let de = "vless://3f1c2a9e-0b7d-4e55-9a10-6c2f8d1e4b77@203.0.113.20:80?type=tcp&security=reality&sni=www.yahoo.com&pbk=Qw3e4r5t6y7u8i9o0pAaSsDdFfGgHhJjKkLlZzXxCcV&sid=0f&fp=chrome&headerType=none&flow=#German%20Server-alex"
let us = "vless://3f1c2a9e-0b7d-4e55-9a10-6c2f8d1e4b77@[2001:db8::7]:80?type=tcp&security=reality&sni=www.yahoo.com&pbk=Mn8b7v6c5x4z3l2k1j0hGgFfDdSsAaPpOoIiUuYyTtR&sid=&fp=firefox&flow=xtls-rprx-vision#US%20Server-alex"

@Suite struct ServerLinks {
    @Test func parsesRealityLink() throws {
        let server = try Server(link: uk)
        #expect(server.address == "203.0.113.10")
        #expect(server.port == 80)
        #expect(server.uuid == "3f1c2a9e-0b7d-4e55-9a10-6c2f8d1e4b77")
        #expect(server.security == "reality")
        #expect(server.sni == "www.yahoo.com")
        #expect(server.shortId == "a1b2c3d4e5f60718")
        #expect(server.flow == "")
        #expect(server.name == "UK Server-alex")
        #expect(server.regionCode == "GB")
        #expect(server.flag == "🇬🇧")
    }

    @Test func stripsIPv6Brackets() throws {
        let server = try Server(link: us)
        #expect(server.address == "2001:db8::7")
        #expect(server.flow == "xtls-rprx-vision")
        #expect(server.fingerprint == "firefox")
        #expect(server.regionCode == "US")
    }

    @Test func rejectsOtherSchemesAndTransports() {
        #expect(throws: Server.LinkError.notVLESS) { try Server(link: "vmess://abc") }
        #expect(throws: Server.LinkError.unsupported("transport ws")) {
            try Server(link: "vless://id@1.2.3.4:443?type=ws&security=tls#x")
        }
        #expect(throws: Server.LinkError.malformed) {
            try Server(link: "vless://id@1.2.3.4:443?type=tcp&security=reality#no-key")
        }
    }

    @Test func emojiFlagWins() throws {
        let server = try Server(link: "vless://id@1.2.3.4:443?security=none#%F0%9F%87%AF%F0%9F%87%B5%20Edge")
        #expect(server.regionCode == "JP")
        #expect(server.displayName == "Edge")
    }
}

@Suite struct Subscriptions {
    @Test func decodesBase64BodyAndTidiesNames() throws {
        let body = Data([uk, de, us].joined(separator: "\n").utf8).base64EncodedString()
        let servers = try Subscription.parse(body: body)
        #expect(servers.map(\.name) == ["UK Server", "German Server", "US Server"])
        #expect(servers.map(\.regionCode) == ["GB", "DE", "US"])
    }

    @Test func acceptsUnpaddedURLSafeBase64() throws {
        let b64 = Data(uk.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        #expect(try Subscription.parse(body: b64).count == 1)
    }

    @Test func acceptsPlainTextAndSkipsUnknown() throws {
        let servers = try Subscription.parse(body: "vmess://nope\n\(uk)\n\n\(uk)\n")
        #expect(servers.count == 1)
    }

    @Test func reportsWhenNothingIsUsable() {
        #expect(throws: SubscriptionError.noUsableServers(skipped: 2)) {
            try Subscription.parse(body: "vmess://a\ntrojan://b")
        }
    }

    @Test func parsesUserinfoHeader() throws {
        let usage = try #require(Usage(header: "upload=0; download=5368709120; total=10737418240; expire=1798761600"))
        #expect(usage.fraction == 0.5)
        #expect(usage.expires == Date(timeIntervalSince1970: 1_798_761_600))
        #expect(Usage(header: "upload=0; download=0")?.total == nil)
    }

    @Test func normalisesPastedInput() {
        #expect(Subscription.normalise("  https://vpn.example.com/api/sub/abc \n")?.host() == "vpn.example.com")
        #expect(Subscription.normalise("rodinia://add?url=https%3A%2F%2Fx.io%2Fsub%2F1")?.absoluteString == "https://x.io/sub/1")
        #expect(Subscription.normalise("not a url") == nil)
        #expect(Subscription.decodeTitle("base64:Um9kaW5pYQ==") == "Rodinia")
    }
}

@Suite struct Config {
    @Test func buildsTunToRealityConfig() throws {
        let json = try XrayConfig.make(for: Server(link: uk))
        let root = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

        let inbound = try #require((root["inbounds"] as? [[String: Any]])?.first)
        #expect(inbound["protocol"] as? String == "tun")

        let outbounds = try #require(root["outbounds"] as? [[String: Any]])
        let proxy = try #require(outbounds.first)
        #expect(proxy["tag"] as? String == "proxy")
        let stream = try #require(proxy["streamSettings"] as? [String: Any])
        let reality = try #require(stream["realitySettings"] as? [String: Any])
        #expect(reality["publicKey"] as? String == "Zx0p8bQyJ3vL5tWm1nR2sK7dF9gH4jC6aE0uI8oP2lM")
        #expect(reality["serverName"] as? String == "www.yahoo.com")

        let vnext = try #require(((proxy["settings"] as? [String: Any])?["vnext"] as? [[String: Any]])?.first)
        let user = try #require((vnext["users"] as? [[String: Any]])?.first)
        #expect(user["flow"] == nil, "an empty flow must be omitted, not sent as \"\"")
    }

    @Test func usesResolvedAddress() throws {
        let server = Server(name: "x", address: "vpn.example.com", port: 443, uuid: "u", publicKey: "k")
        let json = try XrayConfig.make(for: server, resolvedAddress: "203.0.113.9")
        #expect(json.contains("203.0.113.9"))
        #expect(!json.contains("vpn.example.com"))
    }
}
