import Foundation

/// Builds the Xray JSON the tunnel runs.
///
/// Everything enters through the TUN inbound (fed by the NetworkExtension's utun
/// fd) and leaves through the VLESS outbound, UDP and DNS included, so nothing
/// leaks around the tunnel. Private ranges go direct for LAN printers, NAS etc.
///
/// DNS is answered IPv4-only. Many nodes have IPv6, and geolocation databases
/// often place a host's IPv6 range somewhere other than its IPv4 address (an
/// UpCloud London node's v6 shows up as Doha to M-Lab, so speed tests and
/// region-locked sites pick the wrong country). With no AAAA answers, apps
/// connect over IPv4 and exit from the node's well-known address. IPv6 is still
/// routed into the tunnel, so a literal v6 address can't leak around it.
public enum XrayConfig {
    public static let privateRanges = [
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16",
        "100.64.0.0/10", "fc00::/7", "fe80::/10",
    ]

    /// - Parameter resolvedAddress: the server's IP, resolved before the tunnel
    ///   comes up. Xray would otherwise resolve a hostname through its own
    ///   tunnel, which isn't up yet.
    public static func make(for server: Server, resolvedAddress: String? = nil, logLevel: String = "warning") throws -> String {
        var user: [String: Any] = ["id": server.uuid, "encryption": "none"]
        if !server.flow.isEmpty { user["flow"] = server.flow }

        var stream: [String: Any] = ["network": server.network, "security": server.security]
        switch server.security {
        case "reality":
            stream["realitySettings"] = [
                "serverName": server.sni,
                "fingerprint": server.fingerprint,
                "publicKey": server.publicKey,
                "shortId": server.shortId,
                "spiderX": server.spiderX,
            ]
        case "tls":
            stream["tlsSettings"] = [
                "serverName": server.sni.isEmpty ? server.address : server.sni,
                "fingerprint": server.fingerprint,
            ]
        default:
            break
        }

        let config: [String: Any] = [
            "log": ["loglevel": logLevel],
            "inbounds": [[
                "tag": "tun",
                "protocol": "tun",
                "port": 0,
                "settings": ["name": "utun", "mtu": Tunnel.mtu],
            ]],
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": ["vnext": [[
                        "address": resolvedAddress ?? server.address,
                        "port": server.port,
                        "users": [user],
                    ]]],
                    "streamSettings": stream,
                ],
                [
                    "tag": "dns-out",
                    "protocol": "dns",
                    "settings": ["rules": [
                        // AAAA and HTTPS (which carries ipv6hint): empty success.
                        ["action": "return", "qType": "28,65", "rCode": 0],
                        ["action": "hijack", "qType": 1],
                        // MX, TXT, SRV… go to the upstream resolver, through the proxy.
                        ["action": "direct"],
                    ]],
                    "streamSettings": ["sockopt": ["dialerProxy": "proxy"]],
                ],
                ["tag": "direct", "protocol": "freedom"],
                ["tag": "block", "protocol": "blackhole"],
            ],
            "dns": [
                "tag": "dns-internal",
                "servers": Tunnel.upstreamDNS,
                "queryStrategy": "UseIPv4",
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [
                    ["type": "field", "inboundTag": ["dns-internal"], "outboundTag": "proxy"],
                    // Before the private-range rule: the tunnel's resolver is 172.19.0.2.
                    ["type": "field", "inboundTag": ["tun"], "port": "53", "outboundTag": "dns-out"],
                    ["type": "field", "ip": privateRanges, "outboundTag": "direct"],
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

/// Values the app and the tunnel extension must agree on.
public enum Tunnel {
    public static let mtu = 1500
    public static let ipv4Address = "172.19.0.1"
    public static let ipv4Mask = "255.255.255.252"
    public static let ipv6Address = "fdfe:dcba:9876::1"
    public static let ipv6Prefix = 126
    /// The resolver the system is told to use: the far end of the tunnel's /30,
    /// answered by Xray. A private address also stops Chrome auto-upgrading to
    /// its own DNS-over-HTTPS, which it does for well-known resolvers like
    /// 1.1.1.1 and which would bypass the IPv4-only answers.
    public static let dnsServers = ["172.19.0.2"]
    /// Where Xray sends those lookups, through the proxy.
    public static let upstreamDNS = ["1.1.1.1", "1.0.0.1"]

    /// Keys of `NETunnelProviderProtocol.providerConfiguration`.
    public enum Key {
        public static let server = "server"
    }
}
