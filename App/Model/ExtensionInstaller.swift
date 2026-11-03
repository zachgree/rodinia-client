import AppKit
import Observation
import SystemExtensions

/// Activates the bundled packet-tunnel system extension.
///
/// macOS asks the user to approve it once in System Settings → General →
/// Login Items & Extensions; until then the request sits in `.needsApproval`.
@MainActor @Observable
final class ExtensionInstaller: NSObject {
    enum State: Equatable {
        case unknown
        case activating
        case needsApproval
        case ready
        case failed(String)
    }

    private(set) var state: State = .unknown
    let identifier: String

    init(identifier: String = Bundle.main.object(forInfoDictionaryKey: "RodiniaTunnelBundleID") as? String ?? "") {
        self.identifier = identifier
    }

    /// Safe to call on every launch: an already-active extension of the same
    /// version comes back as `.ready` without bothering the user.
    func activate() {
        guard state != .activating, state != .ready else { return }
        state = .activating
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    static func openApprovalSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}

extension ExtensionInstaller: OSSystemExtensionRequestDelegate {
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated { state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        MainActor.assumeIsolated { state = .ready }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            let code = (error as NSError).code
            state = switch OSSystemExtensionError.Code(rawValue: code) {
            case .unsupportedParentBundleLocation:
                .failed("Move Rodinia to the Applications folder, then open it again.")
            case .requestCanceled:
                .unknown
            default:
                .failed(error.localizedDescription)
            }
        }
    }
}
