import RodiniaKit
import SwiftUI

struct ServerList: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Location")
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkSoft)
                .padding(.leading, 12)
                .padding(.bottom, 2)

            VStack(spacing: 1) {
                ForEach(Array(model.servers.enumerated()), id: \.element.id) { index, server in
                    ServerRow(
                        server: server,
                        shortcut: index < 9 ? index + 1 : nil,
                        isSelected: server.id == model.selectedServer?.id,
                        isLive: server.id == model.vpn.connectedServerID && model.vpn.phase.isActive,
                        latency: model.latencies[server.id],
                        measuring: model.measuring.contains(server.id),
                        selection: selection
                    ) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            model.selectedServerID = server.id
                        }
                        Task { await model.select(server) }
                    }
                }
            }
        }
    }
}

private struct ServerRow: View {
    let server: Server
    let shortcut: Int?
    let isSelected: Bool
    let isLive: Bool
    let latency: Duration?
    let measuring: Bool
    let selection: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(server.flag ?? "🌐")
                    .font(.system(size: 20))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(server.label)
                        .font(Typeface.bodyStrong)
                        .foregroundStyle(Palette.ink)
                    if server.label != server.displayName {
                        Text(server.displayName)
                            .font(Typeface.caption)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }

                Spacer(minLength: 8)

                LatencyReading(latency: latency, measuring: measuring)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isLive ? Palette.olivineDeep : Palette.ink)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.5)
                    .frame(width: 14)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(.rect(cornerRadius: 10))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.ink.opacity(0.07))
                        .matchedGeometryEffect(id: "selection", in: selection)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.ink.opacity(0.035))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(OptionalShortcut(number: shortcut))
        .accessibilityLabel("\(server.label)\(latency.map { ", \(Format.milliseconds($0)) milliseconds" } ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LatencyReading: View {
    let latency: Duration?
    let measuring: Bool

    var body: some View {
        Group {
            if let latency {
                let ms = Format.milliseconds(latency)
                HStack(spacing: 5) {
                    Circle().fill(color(ms)).frame(width: 6, height: 6)
                    Text("\(ms) ms")
                        .contentTransition(.numericText(value: Double(ms)))
                }
            } else if measuring {
                ProgressView().controlSize(.mini)
            } else {
                Text("No reply").foregroundStyle(Palette.inkSoft.opacity(0.7))
            }
        }
        .font(Typeface.figures)
        .foregroundStyle(Palette.inkSoft)
        .animation(.smooth, value: latency)
    }

    private func color(_ ms: Int) -> Color {
        switch ms {
        case ..<120: Palette.olivineLight
        case ..<260: Palette.stoneDeep
        default: Palette.garnet
        }
    }
}

private struct OptionalShortcut: ViewModifier {
    let number: Int?

    func body(content: Content) -> some View {
        if let number {
            content.keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
        } else {
            content
        }
    }
}

struct UsageStrip: View {
    let usage: Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let fraction = usage.fraction, usage.used > 0 {
                Capsule()
                    .fill(Palette.ink.opacity(0.08))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(fraction > 0.9 ? Palette.garnet : Palette.olivineLight)
                                .frame(width: max(4, proxy.size.width * fraction))
                        }
                    }
            }
            HStack {
                if let left = leftText { Text(left) }
                Spacer()
                if let expires = usage.expires {
                    Text(expires < .now ? "Expired" : "Renews \(expires.formatted(.dateTime.day().month(.abbreviated)))")
                        .foregroundStyle(expires < .now ? Palette.garnet : Palette.inkSoft)
                }
            }
            .font(Typeface.caption)
            .foregroundStyle(Palette.inkSoft)
        }
    }

    private var leftText: String? {
        switch (usage.used, usage.total) {
        case (0, let total?): "\(Format.bytes(total)) plan"
        case (let used, let total?): "\(Format.bytes(used)) of \(Format.bytes(total)) used"
        case (let used, nil) where used > 0: "\(Format.bytes(used)) used"
        default: nil
        }
    }
}
