import AppKit
import SwiftUI

/// The plates, wired to the connection phase. Clicking the continent connects.
struct ConnectHero: View {
    let phase: VPNController.Phase
    var size: CGFloat = 260
    let action: () -> Void

    @State private var look = Look.apart
    @State private var hovering = false
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            PlatesView(
                // Hovering pulls the plates a little closer: a hint of what a click does.
                assembly: min(1, look.assembly + (hovering && !phase.isActive ? 0.07 : 0)),
                verdancy: look.verdancy,
                seam: look.seam,
                alarm: look.alarm,
                breathing: phase == .connecting
            )
            .frame(width: size, height: size * 0.92)
            .contentShape(Circle().inset(by: size * 0.18))
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { hovering = inside }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: shakes) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-7, duration: 0.06)
                SpringKeyframe(6, duration: 0.1)
                SpringKeyframe(-4, duration: 0.1)
                SpringKeyframe(0, duration: 0.2)
            }
        }
        .onAppear { look = Look(phase) }
        .onChange(of: phase) { old, new in transition(from: old, to: new) }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private func transition(from old: VPNController.Phase, to new: VPNController.Phase) {
        let animation: Animation = switch new {
        case .connected: .spring(response: 1.0, dampingFraction: 0.68)   // the bloom: plates snap together, settle
        case .connecting: .spring(response: 0.9, dampingFraction: 0.85)
        case .disconnecting, .disconnected: .easeOut(duration: 1.6)          // drifting apart is slow
        case .failed: .easeOut(duration: 0.9)
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : animation) { look = Look(new) }

        if case .failed = new, !reduceMotion { shakes += 1 }
        if case .connected = new, old != new {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if case .failed = new {
            // The garnet edge is a flash, not a state.
            withAnimation(.easeOut(duration: 2.2).delay(0.6)) { look.alarm = 0 }
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .connected: "Disconnect"
        case .connecting: "Connecting. Click to cancel."
        default: "Connect"
        }
    }

    struct Look: Equatable {
        var assembly: Double
        var verdancy: Double
        var seam: Double
        var alarm: Double

        static let apart = Look(assembly: 0, verdancy: 0, seam: 0, alarm: 0)

        init(assembly: Double, verdancy: Double, seam: Double, alarm: Double) {
            self.assembly = assembly
            self.verdancy = verdancy
            self.seam = seam
            self.alarm = alarm
        }

        init(_ phase: VPNController.Phase) {
            switch phase {
            case .connected: self.init(assembly: 1, verdancy: 1, seam: 0, alarm: 0)
            case .connecting: self.init(assembly: 0.62, verdancy: 0, seam: 1, alarm: 0)
            case .disconnecting: self.init(assembly: 0.4, verdancy: 0.2, seam: 0.3, alarm: 0)
            case .disconnected: self = .apart
            case .failed: self.init(assembly: 0, verdancy: 0, seam: 0, alarm: 1)
            }
        }
    }
}

/// A small, springy press: the continent gives under the click.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
