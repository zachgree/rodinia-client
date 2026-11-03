import AppKit
import RodiniaKit
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ConnectHero(phase: model.displayPhase) {
                Task { await model.toggle() }
            }
            .padding(.top, 2)
            StatusBlock()
                .padding(.horizontal, 28)
                .padding(.top, 4)
            Spacer(minLength: 12)
            ServerList()
                .padding(.horizontal, 14)
            if let usage = model.profile?.usage {
                UsageStrip(usage: usage)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }
        }
        .padding(.bottom, 20)
        .overlay {
            if model.showsApproval {
                ApprovalPanel()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: model.showsApproval)
    }
}

// MARK: - top bar

private struct TopBar: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingRemoval = false

    var body: some View {
        HStack {
            Spacer()
            Text(model.profile?.title ?? "Rodinia")
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkSoft)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Menu {
                Button("Refresh servers") { Task { await model.refresh(); await model.measureAll() } }
                    .keyboardShortcut("r")
                Button("Test speeds again") { Task { await model.measureAll() } }
                if let ip = model.exitIP {
                    Button("Copy IP address \(ip)") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ip, forType: .string)
                    }
                }
                Divider()
                Button("Remove subscription…", role: .destructive) { confirmingRemoval = true }
            } label: {
                Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "ellipsis")
                    .symbolEffect(.rotate, isActive: model.isRefreshing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 14)
            .accessibilityLabel("More")
        }
        .frame(height: 30)
        .confirmationDialog("Remove this subscription?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { model.signOut() }
        } message: {
            Text("You'll disconnect, and you'll need the link again to add it back.")
        }
    }
}

// MARK: - status

private struct StatusBlock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Text(headline)
                .font(Typeface.headline())
                .foregroundStyle(Palette.ink)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: headline)

            detail
                .font(Typeface.body)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)

            setupNotice
        }
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        switch model.displayPhase {
        case .disconnected: "Not connected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting"
        case .failed: "Couldn't connect"
        }
    }

    @ViewBuilder private var detail: some View {
        let server = model.selectedServer
        switch model.displayPhase {
        case .connected(let since):
            VStack(spacing: 4) {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    HStack(spacing: 6) {
                        Text(server.map(\.label) ?? "")
                        Text(Format.elapsed(since: since, now: context.date))
                            .font(Typeface.figures)
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.snappy, value: context.date)
                    }
                }
                ThroughputLine(throughput: model.throughput)
            }
        case .connecting:
            Text(server.map { "Joining \($0.label)" } ?? "")
        case .failed(let reason):
            Text(reason)
                .foregroundStyle(Palette.garnet)
                .lineLimit(3)
        default:
            Text(server.map { "Click the map to connect to \($0.label)" } ?? "Choose a location below")
        }
    }

    @ViewBuilder private var setupNotice: some View {
        switch model.installer.state {
        case .failed(let message):
            Notice(text: message, button: "Try again") { model.installer.activate() }
        default:
            EmptyView()
        }
    }
}

private struct ThroughputLine: View {
    let throughput: Throughput

    var body: some View {
        HStack(spacing: 14) {
            Label(Format.rate(throughput.down), systemImage: "arrow.down")
            Label(Format.rate(throughput.up), systemImage: "arrow.up")
        }
        .labelStyle(CompactLabel())
        .font(Typeface.figures)
        .foregroundStyle(Palette.inkSoft)
        .contentTransition(.numericText())
        .animation(.smooth(duration: 0.4), value: throughput)
        .accessibilityElement(children: .combine)
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9, weight: .bold)).opacity(0.7)
            configuration.title
        }
    }
}

private struct Notice: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(Typeface.caption)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .controlSize(.small)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Palette.lapis.opacity(0.09), in: .rect(cornerRadius: 10))
        .padding(.top, 6)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

extension Server {
    /// "United Kingdom", or the server's own name when the country isn't known.
    var label: String { countryName ?? displayName }
}
