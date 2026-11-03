import SwiftUI

/// The connect control's artwork: a continent broken into tectonic plates.
///
/// Apart, the plates drift slowly on their own. While connecting they close in and
/// breathe, their seams lit in lapis. Connected, they fuse into one landmass that
/// turns olivine and shows faint contour lines, the moment the whole app is built around.
struct PlatesView: View, Animatable {
    /// 0 = drifted apart, 1 = fused.
    var assembly: Double
    /// 0 = bare stone, 1 = olivine.
    var verdancy: Double
    /// Glow of the seams between plates.
    var seam: Double
    /// Garnet edge after a failure.
    var alarm: Double
    var breathing: Bool

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { .init(.init(assembly, verdancy), .init(seam, alarm)) }
        set {
            assembly = newValue.first.first
            verdancy = newValue.first.second
            seam = newValue.second.first
            alarm = newValue.second.second
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Nothing moves once the plates are fused and still, so stop redrawing.
        let still = reduceMotion || (assembly > 0.995 && !breathing)
        TimelineView(.animation(minimumInterval: 1 / 60, paused: still)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: &context, size: size, time: t)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, time t: Double) {
        let radius = min(size.width, size.height) / 2 * 0.68
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let breath = breathing && !reduceMotion ? 0.07 * sin(t * 3.1) : 0
        let a = min(1, max(0, assembly + breath))
        let apart = 1 - a

        drawHalo(in: &context, center: center, radius: radius)

        let top = Palette.stoneLight.mix(with: Palette.olivineLight, by: verdancy)
        let deep = Palette.stoneDeep.mix(with: Palette.olivineDeep, by: verdancy)
        let fill = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [top, deep]),
            startPoint: CGPoint(x: -0.9, y: -1), endPoint: CGPoint(x: 0.8, y: 1)
        )

        var plates = context
        plates.translateBy(x: center.x, y: center.y)
        plates.scaleBy(x: radius, y: radius)
        plates.addFilter(.shadow(color: Palette.ink.opacity(0.16 + 0.06 * verdancy), radius: 14 / radius, y: 7 / radius))

        // Fused, a silhouette underneath hides the hairline gaps antialiasing leaves between plates.
        let solid = smoothstep(0.86, 1, a)
        if solid > 0 {
            var under = plates
            under.opacity = solid
            under.fill(Geometry.coast, with: fill)
        }

        for (index, plate) in Geometry.plates.enumerated() {
            var layer = plates
            let spread = apart * 0.17 * plate.mobility
            let drift = apart * 0.03
            let phase = Double(index) * 1.7
            let dx = cos(plate.heading) * spread + drift * sin(t * 0.37 + phase)
            let dy = sin(plate.heading) * spread + drift * cos(t * 0.29 + phase)
            layer.translateBy(x: dx, y: dy)
            layer.translateBy(x: plate.anchor.x, y: plate.anchor.y)
            layer.rotate(by: .radians(plate.twist * apart + apart * 0.02 * sin(t * 0.21 + phase)))
            layer.translateBy(x: -plate.anchor.x, y: -plate.anchor.y)

            layer.fill(plate.path, with: fill)
            // Vary the plates a touch so they read as separate rock even before they part.
            layer.fill(plate.path, with: .color(.white.opacity(plate.sheen * (1 - 0.6 * solid))))

            let edge = 1.3 / radius
            if seam > 0.01 {
                layer.stroke(plate.path, with: .color(Palette.lapis.opacity(seam * (0.55 + 0.45 * sin(t * 3.1)))), lineWidth: edge * 1.4)
            }
            if alarm > 0.01 {
                layer.stroke(plate.path, with: .color(Palette.garnet.opacity(alarm)), lineWidth: edge * 1.6)
            }
        }

        // Contour lines appear only on the joined continent.
        let contours = verdancy * pow(a, 10)
        if contours > 0.01 {
            var lines = context
            lines.translateBy(x: center.x, y: center.y)
            lines.scaleBy(x: radius, y: radius)
            for (step, scale) in [0.76, 0.54, 0.33].enumerated() {
                var ring = lines
                ring.scaleBy(x: scale, y: scale)
                ring.stroke(Geometry.coast, with: .color(.white.opacity(contours * (0.22 - Double(step) * 0.04))),
                            lineWidth: 1 / (radius * scale))
            }
        }
    }

    private func drawHalo(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let glow = max(verdancy * 0.32, seam * 0.18)
        guard glow > 0.01 else { return }
        let color = Palette.lapis.mix(with: Palette.olivineLight, by: verdancy)
        let extent = radius * 1.75
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - extent, y: center.y - extent, width: extent * 2, height: extent * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(glow), color.opacity(0)]),
                center: center, startRadius: radius * 0.4, endRadius: extent
            )
        )
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - geometry

/// The continent and its plates, computed once in unit space (radius ≈ 1).
private enum Geometry {
    struct Plate {
        let path: Path
        /// Direction the plate drifts in when apart.
        let heading: Double
        /// Point it turns around.
        let anchor: CGPoint
        /// Rotation when fully apart.
        let twist: Double
        let sheen: Double
        /// How far it travels when apart; the core barely moves.
        var mobility: Double = 1
    }

    /// Irregular coastline: a circle bent by a few low harmonics.
    static func coastRadius(_ theta: Double) -> Double {
        (1 + 0.10 * sin(3 * theta + 0.6) + 0.06 * sin(5 * theta + 2.1)
            + 0.035 * sin(8 * theta + 4.0) + 0.018 * sin(13 * theta + 1.3)) / 1.15
    }

    static func innerRadius(_ theta: Double) -> Double {
        0.4 * (1 + 0.13 * sin(2 * theta + 1) + 0.07 * sin(4 * theta + 3))
    }

    static func point(_ theta: Double, _ r: Double) -> CGPoint {
        CGPoint(x: cos(theta) * r, y: sin(theta) * r)
    }

    static let coast: Path = {
        var path = Path()
        let steps = 160
        for i in 0...steps {
            let theta = Double(i) / Double(steps) * 2 * .pi
            let p = point(theta, coastRadius(theta))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }()

    /// Where the outer ring is cut into plates, deliberately uneven.
    static let cuts: [Double] = [0.35, 1.3, 2.2, 3.1, 4.1, 4.95, 5.7]

    /// A cut from the inner ring to the coast, kinked so it reads as a fault line, not a pie slice.
    static func faultLine(at theta: Double, seed: Int) -> [CGPoint] {
        let r0 = innerRadius(theta), r1 = coastRadius(theta)
        let kinks: [(Double, Double)] = [(0.3, 0.05), (0.55, -0.04), (0.8, 0.03)]
        var points = [point(theta, r0)]
        for (k, (t, offset)) in kinks.enumerated() {
            let wobble = offset * (seed + k).isMultiple(of: 2).sign
            points.append(point(theta + wobble, r0 + (r1 - r0) * t))
        }
        points.append(point(theta, r1))
        return points
    }

    static let plates: [Plate] = {
        var plates: [Plate] = []
        let n = cuts.count
        let twists: [Double] = [0.06, -0.04, 0.05, -0.07, 0.035, -0.05, 0.045]

        for i in 0..<n {
            let a0 = cuts[i]
            let a1 = i + 1 < n ? cuts[i + 1] : cuts[0] + 2 * .pi
            var path = Path()
            let samples = max(6, Int((a1 - a0) / 0.04))

            path.move(to: point(a0, coastRadius(a0)))
            for s in 1...samples {
                let theta = a0 + (a1 - a0) * Double(s) / Double(samples)
                path.addLine(to: point(theta, coastRadius(theta)))
            }
            for p in faultLine(at: a1, seed: (i + 1) % n).reversed() { path.addLine(to: p) }
            for s in stride(from: samples, through: 0, by: -1) {
                let theta = a0 + (a1 - a0) * Double(s) / Double(samples)
                path.addLine(to: point(theta, innerRadius(theta)))
            }
            for p in faultLine(at: a0, seed: i) { path.addLine(to: p) }
            path.closeSubpath()

            let mid = (a0 + a1) / 2
            plates.append(Plate(
                path: path,
                heading: mid,
                anchor: point(mid, 0.7),
                twist: twists[i % twists.count],
                sheen: [0.0, 0.05, 0.02, 0.07, 0.03, 0.06, 0.01][i % 7]
            ))
        }

        // The craton: the old core everything else gathers around. It barely moves.
        var core = Path()
        for s in 0...120 {
            let theta = Double(s) / 120 * 2 * .pi
            let p = point(theta, innerRadius(theta))
            s == 0 ? core.move(to: p) : core.addLine(to: p)
        }
        core.closeSubpath()
        plates.append(Plate(path: core, heading: -.pi / 2, anchor: .zero, twist: 0.04, sheen: 0.09, mobility: 0.12))
        return plates
    }()
}

private extension Bool {
    var sign: Double { self ? 1 : -1 }
}
