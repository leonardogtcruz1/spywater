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
        "Bloop! Tudo sob controle!",
        "Mergulhando nos logs…",
        "Radar ligado nas sessões!",
        "Opa! Tô de olho aqui!"
    ]

    func triggerTap(mood: MascotMood) {
        let current = Date()
        hopUntil = current.addingTimeInterval(0.7)
        if mood == .alert {
            messageOverride = "Ei! Tem coisa esperando você!"
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
            return attentionCount > 1 ? "\(attentionCount) precisam de você!" : "Precisa de você!"
        case .error:
            return "Ops, erro detectado!"
        case .working:
            return workingCount > 1 ? "\(workingCount) agentes no gás!" : "Agentes trabalhando…"
        case .calm:
            return "De olho nas águas…"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(mood.accentColor)
                    .frame(width: 6, height: 6)
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
                    .stroke(mood.accentColor.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .padding(.bottom, 12)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                Canvas { ctx, size in
                    drawMascot(in: &ctx, size: size, date: context.date)
                }
                .frame(width: 78, height: 82)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                ui.triggerTap(mood: mood)
            }
            .help("SpyDrop — clique para interagir")
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

        let bob: Double
        switch mood {
        case .calm:
            bob = sin(t * 2.1) * 3.0
        case .working:
            bob = sin(t * 4.4) * 4.2
        case .alert:
            bob = -abs(sin(t * 5.2)) * 6.5
        case .error:
            bob = sin(t * 1.6) * 1.5
        }

        let dy = bob + hopOffset
        let cx = size.width * 0.5
        let cy = size.height * 0.58 + dy

        // Floor ripple shadow
        let shadowScale = max(0.65, min(1.1, 1.0 + dy / 40.0))
        let rippleRect = CGRect(
            x: cx - 22 * shadowScale,
            y: size.height - 11,
            width: 44 * shadowScale,
            height: 7 * shadowScale
        )
        ctx.fill(Path(ellipseIn: rippleRect), with: .color(mood.accentColor.opacity(0.24)))

        // Working / alert aura & particles
        if mood == .working {
            let pulse = (t * 0.9).truncatingRemainder(dividingBy: 1.0)
            let ringR = 23.0 + pulse * 14.0
            let ringRect = CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)
            ctx.stroke(
                Path(ellipseIn: ringRect),
                with: .color(Theme.aqua.opacity((1.0 - pulse) * 0.45)),
                lineWidth: 1.5
            )

            for i in 0..<3 {
                let angle = t * 2.4 + Double(i) * (2.0 * .pi / 3.0)
                let px = cx + cos(angle) * 29.0
                let py = cy + sin(angle) * 18.0 - 4.0
                let dotRect = CGRect(x: px - 2.3, y: py - 2.3, width: 4.6, height: 4.6)
                let sparkColor = i == 1 ? Theme.violet : Theme.aqua
                ctx.fill(Path(ellipseIn: dotRect), with: .color(sparkColor.opacity(0.85)))
            }
        } else if mood == .alert {
            let pulse = (t * 1.3).truncatingRemainder(dividingBy: 1.0)
            let ringR = 22.0 + pulse * 15.0
            let ringRect = CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)
            ctx.stroke(
                Path(ellipseIn: ringRect),
                with: .color(Theme.coral.opacity((1.0 - pulse) * 0.65)),
                lineWidth: 2.0
            )
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

        // Periscope / antenna behind head
        let tilt = mood == .working ? sin(t * 3.0) * 2.5 : sin(t * 1.4) * 1.0
        var antenna = Path()
        antenna.move(to: CGPoint(x: cx + 5, y: cy - 19))
        antenna.addQuadCurve(
            to: CGPoint(x: cx + 12 + tilt, y: cy - 30),
            control: CGPoint(x: cx + 7, y: cy - 29)
        )
        ctx.stroke(antenna, with: .color(Theme.teal.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        let beaconGlow = 0.55 + 0.45 * sin(t * (mood == .alert ? 7.0 : 3.0))
        let tipX = cx + 12 + tilt
        let tipY = cy - 30
        ctx.fill(
            Path(ellipseIn: CGRect(x: tipX - 4.5, y: tipY - 4.5, width: 9, height: 9)),
            with: .color(mood.accentColor.opacity(0.35 * beaconGlow))
        )
        ctx.fill(
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

        ctx.fill(
            drop,
            with: .linearGradient(
                Gradient(colors: bodyColors),
                startPoint: CGPoint(x: cx - 12, y: topY),
                endPoint: CGPoint(x: cx + 12, y: botY)
            )
        )
        ctx.stroke(drop, with: .color(.white.opacity(0.32)), lineWidth: 1.1)

        // Glossy specular highlight on top-left
        var shine = Path()
        shine.addEllipse(in: CGRect(x: cx - 12, y: cy - 10, width: 6.5, height: 11))
        ctx.drawLayer { layerCtx in
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
            lookX = sin(t * 2.6) * 2.4
            lookY = 0
        case .alert:
            lookX = 0
            lookY = -1.2
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
                ctx.stroke(lid, with: .color(eyeColor), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        } else {
            for ex in [leftEyeX, rightEyeX] {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: ex - 3.2, y: eyeY - 3.8, width: 6.4, height: 7.6)),
                    with: .color(eyeColor)
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: ex - 1.6, y: eyeY - 2.4, width: 2.3, height: 2.3)),
                    with: .color(.white.opacity(0.95))
                )
            }
        }

        // Rosy cheeks
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - 15.5, y: cy + 6.5, width: 5.5, height: 3.2)),
            with: .color(Theme.coral.opacity(0.45))
        )
        ctx.fill(
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
            ctx.stroke(mouth, with: .color(eyeColor), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        case .working:
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - 2.2 + lookX * 0.5, y: mouthY - 1.5, width: 4.4, height: 4.0)),
                with: .color(eyeColor)
            )
        case .alert:
            mouth.move(to: CGPoint(x: cx - 4.0, y: mouthY - 1.0))
            mouth.addQuadCurve(to: CGPoint(x: cx + 4.0, y: mouthY - 1.0), control: CGPoint(x: cx, y: mouthY + 4.5))
            mouth.closeSubpath()
            ctx.fill(mouth, with: .color(eyeColor))
        case .error:
            mouth.move(to: CGPoint(x: cx - 3.5, y: mouthY + 1.5))
            mouth.addQuadCurve(to: CGPoint(x: cx + 3.5, y: mouthY + 1.5), control: CGPoint(x: cx, y: mouthY - 2.0))
            ctx.stroke(mouth, with: .color(eyeColor), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
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
