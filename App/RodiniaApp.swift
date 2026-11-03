import RodiniaKit
import SwiftUI

@main
struct RodiniaApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        if let directory = Snapshots.directory {
            Snapshots.render(to: directory)
            exit(0)
        }
        #endif
    }

    var body: some Scene {
        Window("Rodinia", id: "main") {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onOpenURL { url in
                    Task {
                        try? await model.addSubscription(url.absoluteString)
                        model.finishOnboarding()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Connection") {
                Button(model.vpn.phase.isActive ? "Disconnect" : "Connect") {
                    Task { await model.toggle() }
                }
                .keyboardShortcut("k")
                .disabled(model.profile == nil)
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .task { await model.start() }
        } label: {
            Image(systemName: model.vpn.phase.isActive ? "globe.europe.africa.fill" : "globe.europe.africa")
                .accessibilityLabel(model.vpn.phase.isActive ? "Rodinia, connected" : "Rodinia, not connected")
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.showsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainView()
                    .transition(.opacity)
            }
        }
        .frame(width: 380, height: 620)
        .background(alignment: .top) { StateWash(phase: model.vpn.phase) }
        .containerBackground(.regularMaterial, for: .window)
    }
}

/// A faint wash of the plates' colour across the window, so the state is legible at a glance.
private struct StateWash: View {
    let phase: VPNController.Phase

    var body: some View {
        LinearGradient(colors: [color.opacity(0.13), color.opacity(0)], startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: phase)
    }

    private var color: Color {
        switch phase {
        case .connected: Palette.olivineLight
        case .connecting, .disconnecting: Palette.lapis
        case .failed: Palette.garnet
        case .disconnected: .clear
        }
    }
}
