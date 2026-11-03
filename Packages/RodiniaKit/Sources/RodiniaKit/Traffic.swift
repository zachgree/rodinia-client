import Foundation

/// Byte counters of the tunnel's utun interface, read with getifaddrs.
/// The app samples these to draw live throughput without asking the extension.
public enum Traffic {
    public struct Counters: Equatable, Sendable {
        public var received: UInt32
        public var sent: UInt32
    }

    /// Counters of the interface that carries `Tunnel.ipv4Address`, or nil when the tunnel is down.
    public static func tunnelCounters() -> Counters? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        // First pass: which utun owns our address.
        var tunnelName: String?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            if String(cchars: host) == Tunnel.ipv4Address {
                tunnelName = String(cString: entry.pointee.ifa_name)
                break
            }
        }
        guard let tunnelName else { return nil }

        // Second pass: the AF_LINK entry of that interface holds the counters.
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: entry.pointee.ifa_name) == tunnelName,
                  let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            return Counters(received: data.pointee.ifi_ibytes, sent: data.pointee.ifi_obytes)
        }
        return nil
    }
}

extension String {
    /// A NUL-terminated C buffer as a String.
    public init(cchars: [CChar]) {
        self.init(decoding: cchars.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
