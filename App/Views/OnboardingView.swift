import AppKit
import RodiniaKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var link = ""
    @State private var adding = false
    @State private var error: String?
    @State private var joined = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ConnectHero(phase: joined ? .connected(since: .now) : (adding ? .connecting : .disconnected), size: 230) {
                fieldFocused = true
            }
            .allowsHitTesting(!adding)

            VStack(spacing: 8) {
                Text("Add your VPN")
                    .font(Typeface.headline(28))
                    .foregroundStyle(Palette.ink)
                Text("Paste the subscription link your provider gave you. It starts with https://")
                    .font(Typeface.body)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)
            .padding(.top, 6)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    if RenderMode.snapshot {
                        Text("https://").font(Typeface.body).foregroundStyle(Palette.inkSoft.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("https://", text: $link)
                            .textFieldStyle(.plain)
                            .font(Typeface.body)
                            .focused($fieldFocused)
                            .onSubmit(add)
                            .disabled(adding)
                    }
                    if link.isEmpty, clipboardLink != nil {
                        Button("Paste") { link = clipboardLink ?? "" }
                            .buttonStyle(.plain)
                            .font(Typeface.caption.weight(.medium))
                            .foregroundStyle(Palette.lapis)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.ink.opacity(0.05), in: .rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(error == nil ? Palette.hairline : Palette.garnet.opacity(0.6))
                }

                if let error {
                    Text(error)
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.garnet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                Button(action: add) {
                    Text(adding ? "Adding…" : "Add subscription")
                        .font(Typeface.bodyStrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.lapis)
                .controlSize(.large)
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || adding)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .modifier(LinkDrop(enabled: !RenderMode.snapshot) { text in
            link = text
            add()
        })
        .onAppear { fieldFocused = true }
    }

    private var clipboardLink: String? {
        guard let text = NSPasteboard.general.string(forType: .string), Subscription.normalise(text) != nil else { return nil }
        return text
    }

    private func add() {
        let input = link
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty, !adding else { return }
        withAnimation(.smooth) { error = nil }
        adding = true
        Task {
            do {
                try await model.addSubscription(input)
                // Let the plates join before the screen changes underneath them.
                joined = true
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.smooth(duration: 0.5)) { model.finishOnboarding() }
            } catch {
                withAnimation(.smooth) { self.error = error.localizedDescription }
            }
            adding = false
        }
    }
}

/// Accepts a dragged link anywhere on the screen.
private struct LinkDrop: ViewModifier {
    let enabled: Bool
    let onDrop: (String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { items, _ in
                guard let first = items.first else { return false }
                onDrop(first)
                return true
            }
        } else {
            content
        }
    }
}
