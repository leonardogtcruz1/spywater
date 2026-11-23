import SwiftUI

struct PulsingStatusDot: View {
    let color: Color
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = (context.date.timeIntervalSinceReferenceDate * 0.85)
                    .truncatingRemainder(dividingBy: 1.0)
                ZStack {
                    Circle()
                        .stroke(color.opacity((1.0 - phase) * 0.75), lineWidth: 1.6)
                        .frame(width: 9, height: 9)
                        .scaleEffect(0.9 + phase * 1.45)

                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                        .shadow(color: color.opacity(0.7), radius: 4)
                }
                .frame(width: 18, height: 18)
            }
        } else {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .shadow(color: color.opacity(0.45), radius: 3)
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct WorkingWaveBars: View {
    var tint: Color = Theme.aqua

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { idx in
                    let wave = 0.5 + 0.5 * sin(t * 5.4 + Double(idx) * 0.85)
                    let height = 4.0 + wave * 10.0
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, Theme.violet],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 15, alignment: .center)
        }
    }
}

struct WorkingShimmerStrip: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = (context.date.timeIntervalSinceReferenceDate * 0.5)
                .truncatingRemainder(dividingBy: 1.0)
            GeometryReader { geo in
                let width = geo.size.width
                let bandWidth = max(90, width * 0.35)
                let travel = width + bandWidth
                let xOffset = -bandWidth + travel * phase

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.aqua.opacity(0.14))

                    LinearGradient(
                        colors: [.clear, Theme.aqua, Theme.violet, Theme.teal, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: xOffset)
                }
            }
            .frame(height: 2.5)
            .clipped()
        }
    }
}

struct NeedsYouPulseBorder: View {
    let cornerRadius: CGFloat
    var color: Color = Theme.coral

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 3.2)
            let opacity = 0.32 + pulse * 0.45
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color.opacity(opacity), lineWidth: 1.4)
                .shadow(color: color.opacity(pulse * 0.25), radius: 6)
        }
    }
}
