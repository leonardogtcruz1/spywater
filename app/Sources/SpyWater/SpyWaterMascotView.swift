import SwiftUI

enum MascotMood {
    case calm
    case working
    case alert
    case error

    @MainActor
    static func from(store: SessionStore) -> MascotMood {
        if !store.pending.isEmpty {
            return .alert
        }
        let live = store.sortedSessions
        if live.contains(where: {
            let st = store.effectiveState(for: $0)
            return st == .needsYou || st == .waitingTerminal || st == .yourTurn
        }) {
            return .alert
        }
        if live.contains(where: { store.effectiveState(for: $0) == .error }) {
            return .error
        }
        if live.contains(where: { store.effectiveState(for: $0) == .working }) {
            return .working
        }
        return .calm
    }

    var accentColor: Color {
        switch self {
        case .calm: return Theme.teal
        case .working: return Theme.aqua
        case .alert: return Theme.coral
        case .error: return Theme.coral
        }
    }
}

private final class MascotTapState: ObservableObject {
    @Published var hopUntil: Date = .distantPast
    @Published var messageOverride: String?
    @Published var overrideUntil: Date = .distantPast
    private var tapCount = 0

    private let quips = [
        L10n.t("Bloop! Tudo sob controle!", "Bloop! Everything under control!"),
        L10n.t("Mergulhando nos logs…", "Diving into the logs…"),
        L10n.t("Radar ligado nas sessões!", "Radar locked on sessions!"),
        L10n.t("Opa! Tô de olho aqui!", "Hey! Keeping watch here!")
    ]

    func triggerTap(mood: MascotMood) {
        let current = Date()
        hopUntil = current.addingTimeInterval(0.7)
        if mood == .alert {
            messageOverride = L10n.t("Ei! Tem coisa esperando você!", "Hey! Something's waiting for you!")
        } else {
            messageOverride = quips[tapCount % quips.count]
        }
        tapCount += 1
        overrideUntil = current.addingTimeInterval(2.6)
    }
}

struct SpyWaterMascotView: View {
    let mood: MascotMood
    let attentionCount: Int
    let workingCount: Int
    let now: Date

    @StateObject private var ui = MascotTapState()

    private var caption: String {
        if now < ui.overrideUntil, let msg = ui.messageOverride {
            return msg
        }
        switch mood {
        case .alert:
            return attentionCount > 1
                ? L10n.t("\(attentionCount) precisam de você!", "\(attentionCount) need you!")
                : L10n.t("Precisa de você!", "Needs you!")
        case .error:
            return L10n.t("Ops, erro detectado!", "Oops, error detected!")
        case .working:
            return workingCount > 1
                ? L10n.t("\(workingCount) agentes no gás!", "\(workingCount) agents running!")
                : L10n.t("Agentes trabalhando…", "Agents working…")
        case .calm:
            return L10n.t("De olho nas águas…", "Watching the waters…")
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pillBorderAlpha: Double = mood == .alert
                    ? (0.45 + 0.45 * (0.5 + 0.5 * sin(t * 5.0)))
                    : 0.45

                HStack(spacing: 6) {
                    if mood == .alert {
                        AttentionBellIcon(color: Theme.coral, urgent: true)
                    } else {
                        Circle()
                            .fill(mood.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(red: 0.06, green: 0.11, blue: 0.21).opacity(0.92))
                )
                .overlay(
                    Capsule()
                        .stroke(mood.accentColor.opacity(pillBorderAlpha), lineWidth: mood == .alert ? 1.3 : 1.0)
                )
                .shadow(color: mood == .alert ? Theme.coral.opacity(0.25) : .black.opacity(0.35), radius: 8, y: 3)
                .padding(.bottom, 12)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                Canvas { ctx, size in
                    drawMascot(in: &ctx, size: size, date: context.date)
                }
                .frame(width: 82, height: 86)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                ui.triggerTap(mood: mood)
            }
            .help(L10n.t("SpyDrop — clique para interagir", "SpyDrop — click to interact"))
        }
    }

    private func drawMascot(in ctx: inout GraphicsContext, size: CGSize, date: Date) {
        let t = date.timeIntervalSinceReferenceDate

        var hopOffset: Double = 0
        if date < ui.hopUntil {
            let remaining = ui.hopUntil.timeIntervalSince(date)
            let progress = 1.0 - max(0, min(1, remaining / 0.7))
            hopOffset = -sin(progress * .pi) * 15.0
        }

        let alertCycle = t.truncatingRemainder(dividingBy: 2.0)
        var dx: Double = 0
        var bob: Double = 0
        var tiltDeg: Double = 0
        var alertHopIntensity: Double = 0

        switch mood {
        case .calm:
            bob = sin(t * 2.1) * 3.0
        case .working:
            // Smooth continuous figure-eight focus glide
            dx = sin(t * 1.6) * 2.2
            bob = sin(t * 3.2) * 2.6
        case .alert:
            // Crisp periodic double-hop + brief attentive pause
            if alertCycle < 0.38 {
                let p = alertCycle / 0.38
                bob = -sin(p * .pi) * 9.5
                tiltDeg = sin(p * .pi) * -6.0
                alertHopIntensity = sin(p * .pi)
            } else if alertCycle >= 0.40 && alertCycle < 0.78 {
                let p = (alertCycle - 0.40) / 0.38
                bob = -sin(p * .pi) * 7.0
                tiltDeg = sin(p * .pi) * 6.0
                alertHopIntensity = sin(p * .pi)
            } else {
                bob = sin(t * 3.0) * 1.2
            }
        case .error:
            bob = sin(t * 1.6) * 1.5
        }

        let dy = bob + hopOffset
        let cx = size.width * 0.52 + dx
        let cy = size.height * 0.58 + dy

        // Floor ripple shadow
        let shadowScale = max(0.60, min(1.1, 1.0 + dy / 40.0))
        let rippleRect = CGRect(
            x: cx - 22 * shadowScale,
            y: size.height - 10,
            width: 44 * shadowScale,
            height: 7 * shadowScale
        )
        ctx.fill(Path(ellipseIn: rippleRect), with: .color(mood.accentColor.opacity(0.24)))

        // Distinct background motion: .working = sonar sweep + orbiters; .alert = twin coral hop ripples
        if mood == .working {
            let center = CGPoint(x: cx, y: cy)
            let sweepAngle = t * 2.2
            let wedgeSpan = 1.15
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(
                center: center,
                radius: 33.0,
                startAngle: .radians(sweepAngle - wedgeSpan),
                endAngle: .radians(sweepAngle),
                clockwise: false
            )
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(Theme.aqua.opacity(0.14)))

            var ray = Path()
            ray.move(to: center)
            ray.addLine(to: CGPoint(x: cx + cos(sweepAngle) * 33.0, y: cy + sin(sweepAngle) * 33.0))
            ctx.stroke(ray, with: .color(Theme.aqua.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

            // Tilted elliptical orbit sparkles
            for i in 0..<3 {
                let angle = t * 2.5 + Double(i) * (2.0 * .pi / 3.0)
                let ox = cos(angle) * 30.0
                let oy = sin(angle) * 14.0
                let rot = 0.35
                let px = cx + ox * cos(rot) - oy * sin(rot)
                let py = cy + ox * sin(rot) + oy * cos(rot) - 2.0
                let dotRect = CGRect(x: px - 2.3, y: py - 2.3, width: 4.6, height: 4.6)
                let sparkColor = i == 1 ? Theme.violet : (i == 2 ? Theme.teal : Theme.aqua)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(sparkColor.opacity(0.9)))
            }
        } else if mood == .alert {
            if alertCycle < 0.9 {
                let p1 = alertCycle / 0.9
                let r1 = 21.0 + p1 * 16.0
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: cx - r1, y: cy - r1, width: r1 * 2, height: r1 * 2)),
                    with: .color(Theme.coral.opacity((1.0 - p1) * 0.72)),
                    lineWidth: 2.0
                )
            }
            if alertCycle >= 0.32 && alertCycle < 1.22 {
                let p2 = (alertCycle - 0.32) / 0.9
                let r2 = 21.0 + p2 * 16.0
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: cx - r2, y: cy - r2, width: r2 * 2, height: r2 * 2)),
                    with: .color(Theme.amber.opacity((1.0 - p2) * 0.60)),
                    lineWidth: 1.6
                )
            }
        }

        // Rising tiny bubbles
        for i in 0..<3 {
            let speed = 0.42 + Double(i) * 0.11
            let phase = (t * speed + Double(i) * 0.37).truncatingRemainder(dividingBy: 1.0)
            let bx = cx + (i == 0 ? -24.0 : (i == 1 ? 25.0 : -15.0)) + sin(t * 2.5 + Double(i)) * 2.2
            let by = (size.height - 14.0) - phase * 48.0
            let br = 1.6 + Double(i % 2) * 0.9
            let alpha = sin(phase * .pi) * 0.65
            ctx.fill(
                Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                with: .color(Theme.aqua.opacity(alpha))
            )
        }

        // Draw SpyDrop body + antenna + face inside tilted layer for lively hops
        ctx.drawLayer { bodyCtx in
            bodyCtx.translateBy(x: cx, y: cy)
            bodyCtx.rotate(by: .degrees(tiltDeg))
            bodyCtx.translateBy(x: -cx, y: -cy)

            // Periscope / antenna behind head
            let antTilt = mood == .working ? sin(t * 3.0) * 2.8 : sin(t * 1.4) * 1.0
            var antenna = Path()
            antenna.move(to: CGPoint(x: cx + 5, y: cy - 19))
            antenna.addQuadCurve(
                to: CGPoint(x: cx + 12 + antTilt, y: cy - 30),
                control: CGPoint(x: cx + 7, y: cy - 29)
            )
            bodyCtx.stroke(antenna, with: .color(Theme.teal.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            let beaconGlow = mood == .alert
                ? (0.45 + 0.55 * alertHopIntensity)
                : (0.55 + 0.45 * sin(t * 3.0))
            let tipX = cx + 12 + antTilt
            let tipY = cy - 30
            bodyCtx.fill(
                Path(ellipseIn: CGRect(x: tipX - 5.0, y: tipY - 5.0, width: 10, height: 10)),
                with: .color(mood.accentColor.opacity(0.40 * beaconGlow))
            )
            bodyCtx.fill(
                Path(ellipseIn: CGRect(x: tipX - 2.6, y: tipY - 2.6, width: 5.2, height: 5.2)),
                with: .color(mood == .alert ? Theme.amber : Theme.aqua)
            )

            // Water-drop body path
            let w: Double = 42.0
            let h: Double = 44.0
            let topY = cy - h * 0.52
            let botY = cy + h * 0.46
            var drop = Path()
            drop.move(to: CGPoint(x: cx, y: topY))
            drop.addCurve(
                to: CGPoint(x: cx + w * 0.5, y: cy + 4),
                control1: CGPoint(x: cx + 9, y: topY + 6),
                control2: CGPoint(x: cx + w * 0.5, y: cy - 10)
            )
            drop.addCurve(
                to: CGPoint(x: cx, y: botY),
                control1: CGPoint(x: cx + w * 0.5, y: botY - 2),
                control2: CGPoint(x: cx + w * 0.28, y: botY)
            )
            drop.addCurve(
                to: CGPoint(x: cx - w * 0.5, y: cy + 4),
                control1: CGPoint(x: cx - w * 0.28, y: botY),
                control2: CGPoint(x: cx - w * 0.5, y: botY - 2)
            )
            drop.addCurve(
                to: CGPoint(x: cx, y: topY),
                control1: CGPoint(x: cx - w * 0.5, y: cy - 10),
                control2: CGPoint(x: cx - 9, y: topY + 6)
            )
            drop.closeSubpath()

            let bodyColors: [Color]
            switch mood {
            case .calm:
                bodyColors = [Theme.aqua, Theme.teal]
            case .working:
                bodyColors = [Theme.aqua, Theme.violet]
            case .alert:
                bodyColors = [Theme.amber, Theme.coral]
            case .error:
                bodyColors = [Theme.coral, Theme.violet]
            }

            bodyCtx.fill(
                drop,
                with: .linearGradient(
                    Gradient(colors: bodyColors),
                    startPoint: CGPoint(x: cx - 12, y: topY),
                    endPoint: CGPoint(x: cx + 12, y: botY)
                )
            )
            bodyCtx.stroke(drop, with: .color(.white.opacity(0.32)), lineWidth: 1.1)

            // Glossy specular highlight on top-left
            var shine = Path()
            shine.addEllipse(in: CGRect(x: cx - 12, y: cy - 10, width: 6.5, height: 11))
            bodyCtx.drawLayer { layerCtx in
                layerCtx.translateBy(x: cx - 8.75, y: cy - 4.5)
                layerCtx.rotate(by: .degrees(20))
                layerCtx.translateBy(x: -(cx - 8.75), y: -(cy - 4.5))
                layerCtx.fill(shine, with: .color(.white.opacity(0.35)))
            }

            // Expressive eyes
            let blinkCycle = t.truncatingRemainder(dividingBy: 3.6)
            let isBlinking = blinkCycle > 3.45

            let lookX: Double
            let lookY: Double
            switch mood {
            case .working:
                lookX = sin(t * 2.6) * 2.6
                lookY = 0
            case .alert:
                lookX = 0
                lookY = -1.4
            case .calm:
                lookX = sin(t * 0.8) * 1.1
                lookY = 0
            case .error:
                lookX = 0
                lookY = 1.0
            }

            let leftEyeX = cx - 7.5 + lookX
            let rightEyeX = cx + 7.5 + lookX
            let eyeY = cy + 2.5 + lookY
            let eyeColor = Color(red: 0.04, green: 0.07, blue: 0.14)

            if isBlinking {
                for ex in [leftEyeX, rightEyeX] {
                    var lid = Path()
                    lid.move(to: CGPoint(x: ex - 3.2, y: eyeY))
                    lid.addQuadCurve(to: CGPoint(x: ex + 3.2, y: eyeY), control: CGPoint(x: ex, y: eyeY + 2.2))
                    bodyCtx.stroke(lid, with: .color(eyeColor), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
            } else {
                for ex in [leftEyeX, rightEyeX] {
                    bodyCtx.fill(
                        Path(ellipseIn: CGRect(x: ex - 3.2, y: eyeY - 3.8, width: 6.4, height: 7.6)),
                        with: .color(eyeColor)
                    )
                    bodyCtx.fill(
                        Path(ellipseIn: CGRect(x: ex - 1.6, y: eyeY - 2.4, width: 2.3, height: 2.3)),
                        with: .color(.white.opacity(0.95))
                    )
                }
            }

            // Rosy cheeks
            bodyCtx.fill(
                Path(ellipseIn: CGRect(x: cx - 15.5, y: cy + 6.5, width: 5.5, height: 3.2)),
                with: .color(Theme.coral.opacity(0.45))
            )
            bodyCtx.fill(
                Path(ellipseIn: CGRect(x: cx + 10.0, y: cy + 6.5, width: 5.5, height: 3.2)),
                with: .color(Theme.coral.opacity(0.45))
            )

            // Mouth
            var mouth = Path()
            let mouthY = cy + 9.5 + lookY * 0.5
            switch mood {
            case .calm:
                mouth.move(to: CGPoint(x: cx - 3.5 + lookX * 0.5, y: mouthY - 0.5))
                mouth.addQuadCurve(
                    to: CGPoint(x: cx + 3.5 + lookX * 0.5, y: mouthY - 0.5),
                    control: CGPoint(x: cx + lookX * 0.5, y: mouthY + 3.2)
                )
                bodyCtx.stroke(mouth, with: .color(eyeColor), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            case .working:
                bodyCtx.fill(
                    Path(ellipseIn: CGRect(x: cx - 2.2 + lookX * 0.5, y: mouthY - 1.5, width: 4.4, height: 4.0)),
                    with: .color(eyeColor)
                )
            case .alert:
                mouth.move(to: CGPoint(x: cx - 4.0, y: mouthY - 1.0))
                mouth.addQuadCurve(to: CGPoint(x: cx + 4.0, y: mouthY - 1.0), control: CGPoint(x: cx, y: mouthY + 4.5))
                mouth.closeSubpath()
                bodyCtx.fill(mouth, with: .color(eyeColor))
            case .error:
                mouth.move(to: CGPoint(x: cx - 3.5, y: mouthY + 1.5))
                mouth.addQuadCurve(to: CGPoint(x: cx + 3.5, y: mouthY + 1.5), control: CGPoint(x: cx, y: mouthY - 2.0))
                bodyCtx.stroke(mouth, with: .color(eyeColor), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }

        // Floating animated "!" badge on .alert mood
        if mood == .alert {
            let badgeBounce = -alertHopIntensity * 4.5
            let bx = cx - 22.0
            let by = cy - 23.0 + badgeBounce
            let br = 8.0 + alertHopIntensity * 1.2
            let badgeRect = CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)
            ctx.fill(
                Path(ellipseIn: badgeRect),
                with: .linearGradient(
                    Gradient(colors: [Theme.coral, Theme.amber]),
                    startPoint: CGPoint(x: bx, y: by - br),
                    endPoint: CGPoint(x: bx, y: by + br)
                )
            )
            ctx.stroke(Path(ellipseIn: badgeRect), with: .color(.white.opacity(0.6)), lineWidth: 1.0)

            var stem = Path()
            stem.move(to: CGPoint(x: bx, y: by - 4.0))
            stem.addLine(to: CGPoint(x: bx, y: by + 1.0))
            ctx.stroke(stem, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: bx - 1.2, y: by + 2.8, width: 2.4, height: 2.4)), with: .color(.white))
        }
    }
}

struct MiniMascotIcon: View {
    let mood: MascotMood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let blink = t.truncatingRemainder(dividingBy: 3.6) > 3.45
            let bob = sin(t * 2.5) * 1.2

            Canvas { ctx, size in
                let cx = size.width * 0.5
                let cy = size.height * 0.54 + bob

                var drop = Path()
                drop.move(to: CGPoint(x: cx, y: cy - 10))
                drop.addCurve(to: CGPoint(x: cx + 9.5, y: cy + 2), control1: CGPoint(x: cx + 4, y: cy - 7), control2: CGPoint(x: cx + 9.5, y: cy - 3))
                drop.addCurve(to: CGPoint(x: cx, y: cy + 10), control1: CGPoint(x: cx + 9.5, y: cy + 8), control2: CGPoint(x: cx + 5, y: cy + 10))
                drop.addCurve(to: CGPoint(x: cx - 9.5, y: cy + 2), control1: CGPoint(x: cx - 5, y: cy + 10), control2: CGPoint(x: cx - 9.5, y: cy + 8))
                drop.addCurve(to: CGPoint(x: cx, y: cy - 10), control1: CGPoint(x: cx - 9.5, y: cy - 3), control2: CGPoint(x: cx - 4, y: cy - 7))
                drop.closeSubpath()

                let colors: [Color] = mood == .alert ? [Theme.amber, Theme.coral] : [Theme.aqua, Theme.violet]
                ctx.fill(drop, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: cx, y: cy - 10), endPoint: CGPoint(x: cx, y: cy + 10)))

                let eyeColor = Color(red: 0.04, green: 0.07, blue: 0.14)
                for dx in [-3.2, 3.2] {
                    if blink {
                        ctx.fill(Path(CGRect(x: cx + dx - 1.5, y: cy + 0.5, width: 3, height: 1.1)), with: .color(eyeColor))
                    } else {
                        ctx.fill(Path(ellipseIn: CGRect(x: cx + dx - 1.5, y: cy - 1.0, width: 3.0, height: 3.4)), with: .color(eyeColor))
                    }
                }
            }
            .frame(width: 26, height: 26)
        }
    }
}
