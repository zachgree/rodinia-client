import AppKit
import SwiftUI

/// Shown over the main window while macOS waits for the user to allow the tunnel
/// extension. macOS only lets the user grant this in System Settings, so the panel
/// makes that one trip as short as possible and then gets out of the way: as soon
/// as the switch is on, the installer reports ready and Rodinia connects by itself.
struct ApprovalPanel: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 18) {
                PlatesView(assembly: 0.62, verdancy: 0, seam: 1, alarm: 0, breathing: true)
                    .frame(width: 96, height: 90)

                VStack(spacing: 8) {
                    Text("Allow Rodinia to connect")
                        .font(Typeface.headline(23))
                        .foregroundStyle(Palette.ink)
                    Text("macOS asks once before a VPN can run. Turn Rodinia on, then come back here. It connects by itself.")
                        .font(Typeface.body)
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsRowPreview()

                VStack(spacing: 10) {
                    Button {
                        ExtensionInstaller.openApprovalSettings()
                    } label: {
                        Text("Open System Settings")
                            .font(Typeface.bodyStrong)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.lapis)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for you to turn it on")
                    }
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSoft)

                    Button("Not now") { model.cancelApproval() }
                        .buttonStyle(.plain)
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(width: 330)
            .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// A miniature of the row people are looking for in System Settings, with the
/// switch flicking on, so they recognise it when they get there.
private struct SettingsRowPreview: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Rodinia").font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                Text("Network Extensions").font(Typeface.caption).foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            Capsule()
                .fill(on ? Palette.olivineDeep : Palette.ink.opacity(0.15))
                .frame(width: 34, height: 20)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).padding(2).shadow(radius: 0.5)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.ink.opacity(0.05), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { on = true; return }
            // A slow, repeating demonstration of the one action that's needed.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { on = true }
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeInOut(duration: 0.3)) { on = false }
            }
        }
    }
}
