import Sparkle
import SwiftUI

/// Sparkle, for SwiftUI. Once a day it looks for a new release, downloads it in
/// the background and installs it when Rodinia quits, so a connection is never
/// cut mid-use (after a while it offers to install and relaunch instead).
/// `check()` is "Check for Updates…", which asks before installing.
@MainActor @Observable
final class Updater {
    private(set) var canCheck = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(starting: Bool = true) {
        controller = SPUStandardUpdaterController(startingUpdater: starting, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in self?.canCheck = canCheck }
        }
    }

    func check() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        Button("Check for Updates…") { updater.check() }
            .disabled(!updater.canCheck)
    }
}
