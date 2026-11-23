import SwiftUI

struct UsageHeader: View {
    let rateLimits: RateLimits?
    let now: Date
    var compact: Bool = false

    var body: some View {
        if let rl = rateLimits, rl.fiveHourPct != nil || rl.sevenDayPct != nil {
            if compact {
                VStack(alignment: .leading, spacing: 6) {
                    if let p5 = rl.fiveHourPct {
                        LimitBar(title: "Limite 5h", pct: p5, resetAt: rl.fiveHourReset, now: now, compact: true)
                    }
                    if let p7 = rl.sevenDayPct {
                        LimitBar(title: "Limite semanal", pct: p7, resetAt: rl.sevenDayReset, now: now, compact: true)
                    }
                }
            } else {
                HStack(spacing: 16) {
                    if let p5 = rl.fiveHourPct {
                        LimitBar(title: "Limite 5h", pct: p5, resetAt: rl.fiveHourReset, now: now, compact: false)
                    }
                    if let p7 = rl.sevenDayPct {
                        LimitBar(title: "Limite semanal", pct: p7, resetAt: rl.sevenDayReset, now: now, compact: false)
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.secondary)
                Text("Uso do plano indisponível — instale a status line (ver Configurações)")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LimitBar: View {
    let title: String
    let pct: Double
    let resetAt: Date?
    let now: Date
    let compact: Bool

    private var color: Color {
        if pct >= 85 { return .red }
        if pct >= 60 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(compact ? .caption2 : .caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(pct.rounded()))%")
                    .font(compact ? .caption2 : .caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                if let resetAt, resetAt > now {
                    Text("· renova em \(formatTimeUntil(resetAt, now: now))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(max(pct, 0), 100), total: 100)
                .tint(color)
        }
        .frame(maxWidth: .infinity)
    }
}
