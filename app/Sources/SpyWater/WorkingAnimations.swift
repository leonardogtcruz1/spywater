import SwiftUI

struct SessionStatusDot: View {
    let state: SessionState

    var body: some View {
        switch state {
        case .working:
            WorkingOrbitDot()
        case .needsYou, .error:
            AttentionBeaconDot(color: state.color, urgent: true)
        case .waitingTerminal, .yourTurn:
            AttentionBeaconDot(color: state.color, urgent: false)
        case .idle, .ended:
            ZStack {
                Circle()
                    .fill(state.color)
                    .frame(width: 9, height: 9)
                    .shadow(color: state.color.opacity(0.45), radius: 3)
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct WorkingOrbitDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let radius: CGFloat = 6.2

                let trackRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                ctx.stroke(Path(ellipseIn: trackRect), with: .color(Theme.aqua.opacity(0.20)), lineWidth: 1.4)

                let startRad = t * 4.2
                let endRad = startRad + 2.6
                var arc = Path()
                arc.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .radians(startRad),
                    endAngle: .radians(endRad),
                    clockwise: false
                )
                ctx.stroke(
                    arc,
                    with: .linearGradient(
                        Gradient(colors: [Theme.aqua, Theme.violet]),
                        startPoint: CGPoint(x: center.x + cos(startRad) * radius, y: center.y + sin(startRad) * radius),
                        endPoint: CGPoint(x: center.x + cos(endRad) * radius, y: center.y + sin(endRad) * radius)
                    ),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                )

                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - 4.4, y: center.y - 4.4, width: 8.8, height: 8.8)),
                    with: .color(Theme.aqua.opacity(0.28))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - 3.0, y: center.y - 3.0, width: 6.0, height: 6.0)),
                    with: .color(Theme.aqua)
                )
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct AttentionBeaconDot: View {
    let color: Color
    let urgent: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

                if urgent {
                    let cycle = t.truncatingRemainder(dividingBy: 1.6)

                    if cycle < 0.9 {
                        let p1 = cycle / 0.9
                        let r1 = 4.0 + p1 * 5.2
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: center.x - r1, y: center.y - r1, width: r1 * 2, height: r1 * 2)),
                            with: .color(color.opacity((1.0 - p1) * 0.85)),
                            lineWidth: 1.8
                        )
                    }
                    if cycle >= 0.25 && cycle < 1.15 {
                        let p2 = (cycle - 0.25) / 0.9
                        let r2 = 4.0 + p2 * 5.2
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: center.x - r2, y: center.y - r2, width: r2 * 2, height: r2 * 2)),
                            with: .color(color.opacity((1.0 - p2) * 0.65)),
                            lineWidth: 1.4
                        )
                    }

                    let beat1 = cycle < 0.28 ? sin((cycle / 0.28) * .pi) : 0.0
                    let beat2 = (cycle >= 0.28 && cycle < 0.56) ? sin(((cycle - 0.28) / 0.28) * .pi) : 0.0
                    let coreR = 4.0 * (1.0 + max(beat1, beat2) * 0.32)

                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - coreR - 1.5, y: center.y - coreR - 1.5, width: (coreR + 1.5) * 2, height: (coreR + 1.5) * 2)),
                        with: .color(color.opacity(0.32))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)),
                        with: .color(color)
                    )
                } else {
                    let phase = (t / 1.8).truncatingRemainder(dividingBy: 1.0)
                    let r = 4.2 + phase * 4.5
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                        with: .color(color.opacity((1.0 - phase) * 0.65)),
                        lineWidth: 1.4
                    )
                    let coreR = 4.2 + 0.5 * sin(t * 3.5)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)),
                        with: .color(color)
                    )
                }
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct AttentionBellIcon: View {
    let color: Color
    let urgent: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)
            let active = phase < 0.65
            let norm = active ? (phase / 0.65) : 0.0
            let angle = active ? sin(phase * 34.0) * (1.0 - norm) * 18.0 : 0.0
            let scale = active ? (1.0 + 0.14 * sin(norm * .pi)) : 1.0

            Image(systemName: urgent ? "bell.badge.fill" : "hand.wave.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(angle))
                .scaleEffect(scale)
        }
    }
}

struct WorkingWaveBars: View {
    var tint: Color = Theme.aqua

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { idx in
                    let wave = 0.5 + 0.5 * sin(t * 5.6 - Double(idx) * 0.72)
                    let height = 4.0 + wave * 10.5
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, Theme.teal, Theme.violet],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 2.6, height: height)
                }
            }
            .frame(height: 15, alignment: .center)
        }
    }
}

struct WorkingShimmerStrip: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = (context.date.timeIntervalSinceReferenceDate * 0.55)
                .truncatingRemainder(dividingBy: 1.0)
            GeometryReader { geo in
                let width = geo.size.width
                let bandWidth = max(110, width * 0.42)
                let travel = width + bandWidth
                let xOffset = -bandWidth + travel * phase

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.aqua.opacity(0.18))

                    LinearGradient(
                        colors: [.clear, Theme.aqua, Theme.emerald, Theme.violet, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: xOffset)
                    .shadow(color: Theme.aqua.opacity(0.65), radius: 5)
                }
            }
            .frame(height: 4)
            .clipped()
        }
    }
}

struct NeedsYouPulseBorder: View {
    let cornerRadius: CGFloat
    var color: Color = Theme.coral
    var urgent: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let intensity: Double = {
                if urgent {
                    let cycle = t.truncatingRemainder(dividingBy: 1.6)
                    let beat1 = cycle < 0.28 ? sin((cycle / 0.28) * .pi) : 0.0
                    let beat2 = (cycle >= 0.28 && cycle < 0.56) ? sin(((cycle - 0.28) / 0.28) * .pi) : 0.0
                    return max(beat1, beat2)
                } else {
                    return 0.5 + 0.5 * sin(t * 2.6)
                }
            }()

            let opacity = urgent ? (0.45 + intensity * 0.55) : (0.35 + intensity * 0.42)
            let lineWidth: CGFloat = urgent ? 2.0 : 1.6

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color.opacity(opacity), lineWidth: lineWidth)
                .shadow(color: color.opacity(urgent ? (0.20 + intensity * 0.40) : (0.10 + intensity * 0.20)), radius: urgent ? 10 : 7)
        }
    }
}

struct AttentionCardBackground: View {
    let color: Color
    let urgent: Bool
    var hovered: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let intensity: Double = {
                if urgent {
                    let cycle = t.truncatingRemainder(dividingBy: 1.6)
                    let beat1 = cycle < 0.28 ? sin((cycle / 0.28) * .pi) : 0.0
                    let beat2 = (cycle >= 0.28 && cycle < 0.56) ? sin(((cycle - 0.28) / 0.28) * .pi) : 0.0
                    return max(beat1, beat2)
                } else {
                    return 0.5 + 0.5 * sin(t * 2.6)
                }
            }()

            let leadAlpha = urgent ? (0.16 + intensity * 0.14) : (0.11 + intensity * 0.09)
            let trailAlpha = urgent ? (0.06 + intensity * 0.06) : (0.04 + intensity * 0.04)

            ZStack {
                hovered ? Theme.cardSurfaceElevated : Theme.cardSurface
                LinearGradient(
                    colors: [color.opacity(leadAlpha), color.opacity(trailAlpha)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }
}

struct WorkingCardBackground: View {
    var hovered: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = (context.date.timeIntervalSinceReferenceDate / 2.4)
                .truncatingRemainder(dividingBy: 1.0)

            GeometryReader { geo in
                let width = geo.size.width
                let bandWidth = max(140, width * 0.55)
                let travel = width + bandWidth
                let xOffset = -bandWidth + travel * phase

                ZStack(alignment: .leading) {
                    hovered ? Theme.cardSurfaceElevated : Theme.cardSurface
                    Theme.aqua.opacity(0.07)

                    LinearGradient(
                        colors: [.clear, Theme.aqua.opacity(0.16), Theme.emerald.opacity(0.11), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: xOffset)
                }
            }
            .clipped()
        }
    }
}
