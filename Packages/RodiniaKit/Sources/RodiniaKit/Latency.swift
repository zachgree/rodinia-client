import Foundation
import Network

/// Measures how long a TCP handshake to a server takes, the closest cheap proxy
/// for how the VPN will feel.
public enum Latency {
    public static func measure(_ server: Server, timeout: TimeInterval = 3) async -> Duration? {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: server.port)) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(server.address), port: port, using: .tcp)
        let clock = ContinuousClock()
        let start = clock.now
        let queue = DispatchQueue(label: "rodinia.latency")

        return await withCheckedContinuation { continuation in
            let finish = Once { (result: Duration?) in
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(clock.now - start)
                case .failed, .cancelled: finish(nil)
                case .waiting: finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

/// Runs its body at most once, whichever caller gets there first.
final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var body: ((T) -> Void)?

    init(_ body: @escaping (T) -> Void) { self.body = body }

    func callAsFunction(_ value: T) {
        lock.lock()
        let run = body
        body = nil
        lock.unlock()
        run?(value)
    }
}
