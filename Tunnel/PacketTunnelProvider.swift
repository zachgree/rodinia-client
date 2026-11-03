import Foundation
@preconcurrency import NetworkExtension
import os
import RodiniaKit
#if canImport(RodiniaCore)
import RodiniaCore
#endif

// Unchecked: the only stored state is a Logger, which is itself Sendable.
final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "rodinia.tunnel", category: "tunnel")

    // Completion-handler overrides: the async ones can't be overridden under Swift 6
    // because NetworkExtension's option dictionary isn't Sendable.
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let done = Handoff(completionHandler)
        Task {
            do {
                try await start()
                done.value(nil)
            } catch {
                log.error("start failed: \(error.localizedDescription, privacy: .public)")
                done.value(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stopping tunnel, reason \(reason.rawValue)")
        Core.stop()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // The only message so far: "what are you running?", for the About screen.
        completionHandler?(Data(Core.version.utf8))
    }

    private func start() async throws {
        let server = try loadServer()
        log.info("starting tunnel to \(server.displayName, privacy: .public)")

        // Resolve before the tunnel exists: once the default route points into it,
        // a lookup would have to go through a VPN that isn't running yet.
        let ip = try await Resolver.firstAddress(of: server.address)

        try await setTunnelNetworkSettings(networkSettings(serverIP: ip))

        guard let fd = tunnelFileDescriptor else {
            throw TunnelError.noFileDescriptor
        }
        let config = try XrayConfig.make(for: server, resolvedAddress: ip)
        try Core.start(config: config, fd: fd)
        log.info("tunnel up, Xray \(Core.version, privacy: .public)")
    }

    // MARK: -

    private func loadServer() throws -> Server {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let data = proto.providerConfiguration?[Tunnel.Key.server] as? Data
        else { throw TunnelError.missingConfiguration }
        return try JSONDecoder().decode(Server.self, from: data)
    }

    private func networkSettings(serverIP: String) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverIP)
        let serverIsV6 = serverIP.contains(":")

        let v4 = NEIPv4Settings(addresses: [Tunnel.ipv4Address], subnetMasks: [Tunnel.ipv4Mask])
        v4.includedRoutes = [NEIPv4Route.default()]
        if !serverIsV6 {
            v4.excludedRoutes = [NEIPv4Route(destinationAddress: serverIP, subnetMask: "255.255.255.255")]
        }
        settings.ipv4Settings = v4

        let v6 = NEIPv6Settings(addresses: [Tunnel.ipv6Address], networkPrefixLengths: [NSNumber(value: Tunnel.ipv6Prefix)])
        v6.includedRoutes = [NEIPv6Route.default()]
        if serverIsV6 {
            v6.excludedRoutes = [NEIPv6Route(destinationAddress: serverIP, networkPrefixLength: 128)]
        }
        settings.ipv6Settings = v6

        let dns = NEDNSSettings(servers: Tunnel.dnsServers)
        dns.matchDomains = [""] // every lookup, so none escape to the ISP's resolver
        settings.dnsSettings = dns
        settings.mtu = NSNumber(value: Tunnel.mtu)
        return settings
    }

    /// The utun fd NetworkExtension created. There is no public accessor, so find the
    /// socket whose control name is a utun interface (as the Xray README describes).
    private var tunnelFileDescriptor: Int32? {
        var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        let prefix = Array("utun".utf8CString.dropLast())
        for fd: Int32 in 0...1024 {
            var length = socklen_t(buffer.count)
            if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &buffer, &length) == 0,
               buffer.starts(with: prefix) {
                return fd
            }
        }
        return nil
    }
}

/// Carries a non-Sendable completion handler into a Task; it is called exactly once.
private final class Handoff<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

enum TunnelError: LocalizedError {
    case missingConfiguration
    case noFileDescriptor
    case resolveFailed(String)
    case coreMissing
    case core(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "No server is configured."
        case .noFileDescriptor: "The system didn't hand over a tunnel interface."
        case .resolveFailed(let host): "Couldn't look up \(host)."
        case .coreMissing: "This build has no VPN core. Run scripts/build-core.sh and rebuild."
        case .core(let message): message
        }
    }
}

/// Thin Swift face on the gomobile functions.
enum Core {
    static func start(config: String, fd: Int32) throws {
        #if canImport(RodiniaCore)
        var error: NSError?
        if !RodiniacoreStart(config, Int(fd), &error) {
            throw TunnelError.core(error?.localizedDescription ?? "The VPN core failed to start.")
        }
        #else
        throw TunnelError.coreMissing
        #endif
    }

    static func stop() {
        #if canImport(RodiniaCore)
        var error: NSError?
        _ = RodiniacoreStop(&error)
        #endif
    }

    static var version: String {
        #if canImport(RodiniaCore)
        RodiniacoreVersion()
        #else
        "none"
        #endif
    }
}

enum Resolver {
    /// The first address of `host`, preferring IPv4. Literal IPs come straight back.
    static func firstAddress(of host: String) async throws -> String {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1 { return host }

        return try await Task.detached {
            var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                                 ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
                throw TunnelError.resolveFailed(host)
            }
            defer { freeaddrinfo(result) }

            let entries = sequence(first: first) { $0.pointee.ai_next }
            let preferred = entries.first { $0.pointee.ai_family == AF_INET } ?? first
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(preferred.pointee.ai_addr, preferred.pointee.ai_addrlen, &name, socklen_t(name.count),
                              nil, 0, NI_NUMERICHOST) == 0
            else { throw TunnelError.resolveFailed(host) }
            return String(cchars: name)
        }.value
    }
}
