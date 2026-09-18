import SwiftUI

struct SwishLoadingView: View {
    var duration: TimeInterval = 1.8
    var onFinished: (() -> Void)?

    @State private var animateIn = false
    @State private var ballProgress: CGFloat = 0 // 0 -> 1 along the path
    @State private var netWiggle: CGFloat = 0
    @State private var fadeOut = false
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GeometryReader { geo in
                let size = Swift.min(geo.size.width, geo.size.height)
                let hoopWidth = size * 0.36
                let hoopY = geo.size.height * 0.35

                // Hoop + net
                VStack(spacing: 0) {
                    // Rim
                    Capsule()
                        .stroke(lineWidth: 6)
                        .foregroundColor(.black)
                        .frame(width: hoopWidth, height: hoopWidth * 0.18)
                        .shadow(color: .black.opacity(0.2), radius: 4)
                        .offset(y: 0)

                    // Net (wiggles slightly after ball goes through)
                    SwishNetShape(wiggle: netWiggle)
                        .stroke(Color.black.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: hoopWidth * 0.85, height: hoopWidth * 0.55)
                        .offset(y: -6)
                }
                .position(x: geo.size.width * 0.62, y: hoopY)

                // Ball following a bezier path
                let start = CGPoint(x: geo.size.width * 0.25, y: geo.size.height * 0.75)
                let control1 = CGPoint(x: geo.size.width * 0.42, y: geo.size.height * 0.25)
                let control2 = CGPoint(x: geo.size.width * 0.58, y: geo.size.height * 0.35)
                let end = CGPoint(x: geo.size.width * 0.62, y: hoopY - hoopWidth * 0.02)

                BasketballShape()
                    .fill(Color.white)
                    .overlay(BasketballLines().stroke(Color.black, lineWidth: 3))
                    .frame(width: size * 0.09, height: size * 0.09)
                    .position(pointOnCubicBezier(t: ballProgress, p0: start, p1: control1, p2: control2, p3: end))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .opacity(animateIn ? 1 : 0)
            }

            VStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("SWISH")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.black)
                }
                LoadingBar(progress: progress)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)
            }
        }
        .opacity(fadeOut ? 0 : 1)
        .onAppear { runAnimation() }
        .animation(.easeInOut(duration: 0.35), value: fadeOut)
    }

    private func runAnimation() {
        // Fade in
        withAnimation(.easeIn(duration: 0.3)) { animateIn = true }

        let travel = max(0.8, duration - 0.6)
        withAnimation(.timingCurve(0.2, 0.9, 0.2, 1.0, duration: travel)) {
            ballProgress = 1
        }
        withAnimation(.linear(duration: travel)) {
            progress = 1
        }

        // Wiggle the net after the ball reaches the rim
        DispatchQueue.main.asyncAfter(deadline: .now() + travel * 0.9) {
            withAnimation(.interpolatingSpring(stiffness: 180, damping: 9)) {
                netWiggle = 1
            }
            // Return to rest
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.25)) { netWiggle = 0 }
            }
        }

        // Fade out and finish
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: 0.35)) { fadeOut = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                onFinished?()
            }
        }
    }

    // MARK: - Helpers
    private func pointOnCubicBezier(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        let x = uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x
        let y = uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y
        return CGPoint(x: x, y: y)
    }
}

// Simple basketball circle with fill
private struct BasketballShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }
}

private struct BasketballLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = rect.width * 0.08
        let r = rect.insetBy(dx: inset, dy: inset)
        p.addEllipse(in: r)
        // Curved seams
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.midY), control1: CGPoint(x: r.minX, y: r.minY), control2: CGPoint(x: r.maxX, y: r.maxY))
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY), control2: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

private struct SwishNetShape: Shape {
    var wiggle: CGFloat // 0..1
    var animatableData: CGFloat {
        get { wiggle }
        set { wiggle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cols = 5
        let rows = 5
        let dx = rect.width / CGFloat(cols)
        let dy = rect.height / CGFloat(rows)
        let skew = wiggle * 8

        // Vertical strands
        for c in 0...cols {
            p.move(to: CGPoint(x: CGFloat(c) * dx, y: 0))
            for r in 0...rows {
                let x = CGFloat(c) * dx + sin(CGFloat(r) * 0.9) * skew
                let y = CGFloat(r) * dy
                if r == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        // Diagonals
        for r in 0...rows {
            p.move(to: CGPoint(x: 0, y: CGFloat(r) * dy))
            p.addLine(to: CGPoint(x: rect.width, y: CGFloat(r) * dy))
        }
        return p
    }
}

private struct LoadingBar: View {
    var progress: CGFloat // 0...1
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.black.opacity(0.08))
                .frame(height: 8)
            Capsule()
                .fill(Color.black)
                .frame(width: Swift.max(8, progress.clamped(to: 0...1) * 260), height: 8)
        }
        .frame(width: 260)
        .animation(.linear(duration: 0.0), value: progress)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

#Preview {
    SwishLoadingView() {}
}
