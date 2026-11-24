import SwiftUI

struct CompactUsageStrip: View {
    let rateLimits: RateLimits?
    let localUsage: LocalPlanUsage?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.caption2)
                .foregroundStyle(Theme.aqua)

            if let rl = rateLimits, rl.fiveHourPct != nil || rl.sevenDayPct != nil {
                HStack(spacing: 6) {
                    if let p5 = rl.fiveHourPct {
                        Text("5h: \(Int(p5.rounded()))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.usageColor(for: p5))
                    }
                    if rl.fiveHourPct != nil && rl.sevenDayPct != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    if let p7 = rl.sevenDayPct {
                        Text("7d: \(Int(p7.rounded()))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.usageColor(for: p7))
                    }
                }
            } else if let u = localUsage {
                Text("5h: \(formatTokens(u.fiveHourTokens)) · 7d: \(formatTokens(u.sevenDayTokens))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                Text("Uso do plano")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if let u = localUsage, u.agySevenDayTokens > 0 {
                Text("Agy 7d: \(formatTokens(u.agySevenDayTokens))")
                    .font(.caption2)
                    .foregroundStyle(Theme.aqua.opacity(0.80))
            }
        }
        .padding(.horizontal, 4)
    }
}
