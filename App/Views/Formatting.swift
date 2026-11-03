import Foundation

/// True while the debug snapshot renderer runs; ImageRenderer can't draw text fields.
@MainActor enum RenderMode {
    static var snapshot = false
}

enum Format {
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = Measurement(value: max(0, bytesPerSecond), unit: UnitInformationStorage.bytes)
        return value.formatted(.byteCount(style: .decimal, spellsOutZero: false)) + "/s"
    }

    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .decimal))
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
    }

    /// 4:07, 1:02:33
    static func elapsed(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
