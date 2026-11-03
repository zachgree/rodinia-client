import Foundation
import Observation
import RodiniaKit

/// Everything the UI shows: the subscription, the chosen server, and live numbers.
@MainActor @Observable
final class AppModel {
    let vpn = VPNController()
    let installer = ExtensionInstaller()

    private(set) var profile: Profile? { didSet { persist() } }
    var selectedServerID: String? {
        didSet { if !inMemory { UserDefaults.standard.set(selectedServerID, forKey: Keys.selected) } }
    }

    private(set) var latencies: [String: Duration] = [:]
    private(set) var measuring: Set<String> = []
    private(set) var throughput = Throughput()
    private(set) var exitIP: String?
    private(set) var isRefreshing = false
    var lastError: String?

    /// Stays true until the plates finish joining after the first link is added.
    private(set) var showsOnboarding: Bool
    private var started = false

    private let client = SubscriptionClient()
    private var sampler: Task<Void, Never>?

    /// In memory, nothing is read from or written to disk (previews and snapshots).
    private let inMemory: Bool

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let saved = inMemory ? nil : UserDefaults.standard.data(forKey: Keys.profile).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }
        showsOnboarding = saved == nil
        profile = saved
        selectedServerID = inMemory ? nil : UserDefaults.standard.string(forKey: Keys.selected)
    }

    func finishOnboarding() {
        showsOnboarding = profile == nil
    }

    var servers: [Server] { profile?.servers ?? [] }

    var selectedServer: Server? {
        servers.first { $0.id == selectedServerID } ?? servers.first
    }

    // MARK: lifecycle

    func start() async {
        guard !started else { return }
        started = true
        await vpn.load()
        if profile != nil { installer.activate() }
        if let id = vpn.connectedServerID, servers.contains(where: { $0.id == id }) { selectedServerID = id }
        startSampling()
        if profile?.isStale == true { await refresh() }
        await measureAll()
    }

    // MARK: subscription

    func addSubscription(_ input: String) async throws {
        guard let url = Subscription.normalise(input) else { throw SubscriptionError.invalidURL }
        let fetched = try await client.fetch(url)
        profile = fetched
        if selectedServer == nil || !fetched.servers.contains(where: { $0.id == selectedServerID }) {
            selectedServerID = fetched.servers.first?.id
        }
        installer.activate()
        await measureAll()
    }

    func refresh() async {
        guard let current = profile, let url = current.url, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            profile = try await client.fetch(url, into: current)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        vpn.disconnect()
        profile = nil
        selectedServerID = nil
        latencies = [:]
        showsOnboarding = true
    }

    // MARK: connection

    func toggle() async {
        if vpn.phase.isActive {
            vpn.disconnect()
        } else if let server = selectedServer {
            vpn.clearError()
            await vpn.connect(to: server)
        }
    }

    func select(_ server: Server) async {
        selectedServerID = server.id
        await vpn.switchServer(to: server)
    }

    // MARK: measurements

    func measureAll() async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                group.addTask { await self.measure(server) }
            }
        }
    }

    func measure(_ server: Server) async {
        measuring.insert(server.id)
        let result = await Latency.measure(server)
        measuring.remove(server.id)
        latencies[server.id] = result
    }

    private func startSampling() {
        sampler?.cancel()
        sampler = Task { [weak self] in
            var previous: (Traffic.Counters, ContinuousClock.Instant)?
            var lookedUpIP = false
            while !Task.isCancelled {
                guard let self else { return }
                if case .connected = self.vpn.phase, let now = Traffic.tunnelCounters() {
                    let instant = ContinuousClock.now
                    if let (last, then) = previous {
                        let seconds = (instant - then) / .seconds(1)
                        // 32-bit counters wrap; wrapping subtraction still yields the delta.
                        self.throughput = Throughput(
                            down: Double(now.received &- last.received) / seconds,
                            up: Double(now.sent &- last.sent) / seconds
                        )
                    }
                    previous = (now, instant)
                    if !lookedUpIP {
                        lookedUpIP = true
                        Task { self.exitIP = await ExitIP.lookup() }
                    }
                } else {
                    previous = nil
                    lookedUpIP = false
                    if self.throughput != Throughput() { self.throughput = Throughput() }
                    if self.exitIP != nil { self.exitIP = nil }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func persist() {
        guard !inMemory else { return }
        if let profile, let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Keys.profile)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.profile)
        }
    }

    #if DEBUG
    func debugLoad(profile: Profile, latencies: [String: Duration], throughput: Throughput) {
        self.profile = profile
        self.latencies = latencies
        self.throughput = throughput
        showsOnboarding = false
    }
    #endif

    private enum Keys {
        static let profile = "profile.v1"
        static let selected = "selectedServer.v1"
    }
}

struct Throughput: Equatable {
    /// Bytes per second.
    var down: Double = 0
    var up: Double = 0
}

enum ExitIP {
    /// The public address traffic leaves from, via Cloudflare's trace endpoint.
    static func lookup() async -> String? {
        var request = URLRequest(url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!, timeoutInterval: 6)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .first { $0.hasPrefix("ip=") }
            .map { String($0.dropFirst(3)) }
    }
}
