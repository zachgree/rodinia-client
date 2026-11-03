import AppKit
import RodiniaKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlatesView(
                    assembly: model.displayPhase.isActive ? (model.displayPhase == .connecting ? 0.62 : 1) : 0,
                    verdancy: model.vpn.phase == .connecting ? 0 : (model.vpn.phase.isActive ? 1 : 0),
                    seam: model.vpn.phase == .connecting ? 1 : 0,
                    alarm: 0,
                    breathing: model.vpn.phase == .connecting
                )
                .frame(width: 44, height: 44)
                .animation(.spring(response: 0.9, dampingFraction: 0.75), value: model.vpn.phase)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typeface.headline(17)).foregroundStyle(Palette.ink)
                    Text(model.selectedServer?.label ?? "No location")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.vpn.phase.isActive },
                    set: { _ in Task { await model.toggle() } }
                ))
                .toggleStyle(.switch)
                .tint(Palette.olivineDeep)
                .labelsHidden()
                .disabled(model.profile == nil)
            }

            if !model.servers.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(model.servers) { server in
                        Button {
                            Task { await model.select(server) }
                        } label: {
                            HStack {
                                Text(server.flag ?? "🌐")
                                Text(server.label).foregroundStyle(Palette.ink)
                                Spacer()
                                if let latency = model.latencies[server.id] {
                                    Text("\(Format.milliseconds(latency)) ms")
                                        .font(Typeface.figures)
                                        .foregroundStyle(Palette.inkSoft)
                                }
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .opacity(server.id == model.selectedServer?.id ? 1 : 0)
                            }
                            .font(Typeface.body)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
            HStack {
                Button("Open Rodinia") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(Typeface.caption)
            .foregroundStyle(Palette.inkSoft)
        }
        .padding(14)
        .frame(width: 290)
    }

    private var title: String {
        switch model.vpn.phase {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnecting: "Disconnecting"
        case .failed: "Couldn't connect"
        case .disconnected: "Not connected"
        }
    }
}
