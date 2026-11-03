#if DEBUG
import AppKit
import RodiniaKit
import SwiftUI

/// `Rodinia -snapshots <dir>` renders every screen state to PNG and quits.
/// Used to review the design without a working tunnel, and for README images.
@MainActor
enum Snapshots {
    static var directory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-snapshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func render(to directory: URL) {
        RenderMode.snapshot = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        renderIcon(to: directory.appendingPathComponent("icon-1024.png"))
        renderDiskImageBackground(to: directory)
        let since = Date.now.addingTimeInterval(-(12 * 60 + 43))
        let states: [(String, VPNController.Phase?)] = [
            ("onboarding", nil),
            ("disconnected", .disconnected),
            ("connecting", .connecting),
            ("connected", .connected(since: since)),
            ("failed", .failed("The server didn't answer. Check your internet connection and try again.")),
            ("approval", .disconnected),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, phase) in states {
                let model = AppModel.preview(phase: phase)
                if name == "approval" { model.installer.debugSet(.needsApproval) }
                let view = ZStack {
                    Color(nsColor: scheme == .dark ? NSColor(hex: 0x1C2328) : NSColor(hex: 0xF3F5F6))
                    if phase == nil { OnboardingView() } else { MainView() }
                }
                .frame(width: 380, height: 620)
                .environment(model)
                .environment(\.colorScheme, scheme)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { continue }
                try? png.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}

extension Snapshots {
    /// The app icon: the joined continent on a dusk-blue tile, 1024 px.
    static func renderIcon(to url: URL) {
        let tile = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x2B3D4A)), Color(nsColor: NSColor(hex: 0x15212A))],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 3)
            PlatesView(assembly: 1, verdancy: 1, seam: 0, alarm: 0, breathing: false)
                .frame(width: 820, height: 820)
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        .frame(width: 824, height: 824)
        .padding(100)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 1
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}

extension Snapshots {
    /// Background of the disk image window (640×400 points): tells people to drag
    /// the app into Applications. Finder places the icons at x 170 and 470, y 205.
    static func renderDiskImageBackground(to directory: URL) {
        let canvas = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xF4F6F7)), Color(nsColor: NSColor(hex: 0xE4E9EC))],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Text("Drag Rodinia into Applications")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(Color(nsColor: NSColor(hex: 0x1E2A30)))
                Text("Then open it from your Applications folder.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(nsColor: NSColor(hex: 0x5B6B73)))
            }
            .padding(.top, 42)
            DragArrow()
                .stroke(Color(nsColor: NSColor(hex: 0x3D5A80)).opacity(0.75),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [0.1, 7]))
                .frame(width: 640, height: 400)
            DragArrowHead()
                .stroke(Color(nsColor: NSColor(hex: 0x3D5A80)).opacity(0.75),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 640, height: 400)
        }
        .frame(width: 640, height: 400)
        .environment(\.colorScheme, .light)

        for scale in [1.0, 2.0] {
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = scale
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: directory.appendingPathComponent(scale == 1 ? "dmg-background.png" : "dmg-background@2x.png"))
        }
    }
}

/// A gentle dotted arc from the app icon towards Applications.
private struct DragArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 252, y: 200))
        path.addQuadCurve(to: CGPoint(x: 384, y: 200), control: CGPoint(x: 318, y: 168))
        return path
    }
}

private struct DragArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        // Aligned with the arc's direction where it ends (control point → end point).
        let tip = CGPoint(x: 384, y: 200), control = CGPoint(x: 318, y: 168)
        let angle = atan2(tip.y - control.y, tip.x - control.x)
        let length: CGFloat = 12, spread: CGFloat = .pi / 5
        var path = Path()
        path.move(to: CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
        return path
    }
}

extension AppModel {
    static func preview(phase: VPNController.Phase?) -> AppModel {
        let model = AppModel(inMemory: true)
        let servers = [
            Server(name: "UK Server", address: "203.0.113.10", port: 80, uuid: "a", sni: "www.yahoo.com", publicKey: "k"),
            Server(name: "German Server", address: "203.0.113.20", port: 80, uuid: "a", sni: "www.yahoo.com", publicKey: "k"),
            Server(name: "US Server", address: "203.0.113.4", port: 80, uuid: "a", sni: "www.yahoo.com", publicKey: "k"),
        ]
        model.debugLoad(
            profile: Profile(url: URL(string: "https://example.com/sub/x"), title: "RodiniaVPN", servers: servers,
                             usage: Usage(total: 50_000_000_000, expires: .now.addingTimeInterval(86400 * 38))),
            latencies: [servers[0].id: .milliseconds(84), servers[1].id: .milliseconds(113), servers[2].id: .milliseconds(425)],
            throughput: Throughput(down: 2_430_000, up: 310_000)
        )
        if let phase { model.vpn.debugSet(phase, server: servers[0].id) }
        return model
    }
}
#endif
