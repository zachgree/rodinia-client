import Foundation
import NetworkExtension
import Observation
import RodiniaKit

/// Owns the system VPN configuration and mirrors its status.
@MainActor @Observable
final class VPNController {
    enum Phase: Equatable {
        case disconnected
        case connecting
        case connected(since: Date)
        case disconnecting
        case failed(String)

        var isActive: Bool {
            switch self {
            case .connecting, .connected: true
            default: false
            }
        }
    }

    private(set) var phase: Phase = .disconnected
    private(set) var connectedServerID: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: (any NSObjectProtocol)?
    private let tunnelBundleID: String
    /// Set while a connect is in flight, so a quick failure shows its reason.
    private var pendingConnect = false

    init(tunnelBundleID: String = Bundle.main.object(forInfoDictionaryKey: "RodiniaTunnelBundleID") as? String ?? "") {
        self.tunnelBundleID = tunnelBundleID
    }

    func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleID }
        if let data = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?[Tunnel.Key.server] as? Data,
           let server = try? JSONDecoder().decode(Server.self, from: data) {
            connectedServerID = server.id
        }
        observeStatus()
        sync()
    }

    func connect(to server: Server) async {
        phase = .connecting
        pendingConnect = true
        do {
            let manager = try await configuredManager(for: server)
            connectedServerID = server.id
            try manager.connection.startVPNTunnel()
        } catch {
            pendingConnect = false
            phase = .failed(Self.describe(error))
        }
    }

    func disconnect() {
        pendingConnect = false
        manager?.connection.stopVPNTunnel()
    }

    /// Reconnects to another server only if the VPN is up; otherwise just remembers it.
    func switchServer(to server: Server) async {
        guard phase.isActive, server.id != connectedServerID else { return }
        manager?.connection.stopVPNTunnel()
        // Wait for the old tunnel to go down before bringing the new one up.
        for _ in 0..<40 where manager?.connection.status != .disconnected {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await connect(to: server)
    }

    func clearError() {
        if case .failed = phase { phase = .disconnected }
    }

    #if DEBUG
    func debugSet(_ phase: Phase, server: String?) {
        self.phase = phase
        connectedServerID = server
    }
    #endif

    // MARK: -

    private func configuredManager(for server: Server) async throws -> NETunnelProviderManager {
        let manager = self.manager ?? NETunnelProviderManager()
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = server.address
        proto.providerConfiguration = [Tunnel.Key.server: try JSONEncoder().encode(server)]
        proto.excludeLocalNetworks = true
        proto.includeAllNetworks = false

        manager.protocolConfiguration = proto
        manager.localizedDescription = "Rodinia"
        manager.isEnabled = true

        // The first save shows macOS's "Allow VPN configuration" prompt.
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        if self.manager == nil {
            self.manager = manager
            observeStatus()
        }
        return manager
    }

    private func observeStatus() {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        guard let connection = manager?.connection else { return }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    private func sync() {
        guard let connection = manager?.connection else {
            phase = .disconnected
            return
        }
        switch connection.status {
        case .connected:
            pendingConnect = false
            phase = .connected(since: connection.connectedDate ?? .now)
        case .connecting, .reasserting:
            phase = .connecting
        case .disconnecting:
            phase = .disconnecting
        case .disconnected, .invalid:
            if pendingConnect {
                pendingConnect = false
                Task { await self.reportLastError(connection) }
            } else if case .failed = phase {
                // keep showing the error until dismissed
            } else {
                phase = .disconnected
            }
        @unknown default:
            phase = .disconnected
        }
    }

    private func reportLastError(_ connection: NEVPNConnection) async {
        do {
            try await connection.fetchLastDisconnectError()
            phase = .disconnected
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        if ns.domain == NEVPNErrorDomain, ns.code == NEVPNError.configurationReadWriteFailed.rawValue {
            return "macOS didn't allow the VPN configuration. Try connecting again and choose Allow."
        }
        return ns.localizedDescription
    }
}
