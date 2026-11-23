import SwiftUI

struct UsageHeader: View {
    let rateLimits: RateLimits?
    let localUsage: LocalPlanUsage?
    let statuslineInstalled: Bool
    let now: Date
    var compact: Bool = false

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                WindowUsageCard(
                    title: "Claude · 5 horas",
                    icon: "bolt.fill",
                    accent: Theme.aqua,
                    pct: rateLimits?.fiveHourPct,
                    resetAt: rateLimits?.fiveHourReset,
                    localSummary: fiveHourLocalSummary,
                    statuslineInstalled: statuslineInstalled,
                    now: now
                )

                WindowUsageCard(
                    title: "Claude · 7 dias",
                    icon: "calendar.badge.clock",
                    accent: Theme.violet,
                    pct: rateLimits?.sevenDayPct,
                    resetAt: rateLimits?.sevenDayReset,
                    localSummary: sevenDayLocalSummary,
                    statuslineInstalled: statuslineInstalled,
                    now: now
                )
            }

            if let u = localUsage, (u.todayMessages > 0 || !u.topModels.isEmpty || u.agySevenDayMessages > 0 || u.agySevenDayTokens > 0 || rateLimits?.spendLimitPct != nil) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if u.todayMessages > 0 {
                            StatChip(
                                icon: "sun.max.fill",
                                tint: Theme.amber,
                                text: "Hoje: \(u.todayMessages) turnos · \(u.todaySessions) \(u.todaySessions == 1 ? "sessão" : "sessões")"
                            )
                        }

                        if u.agySevenDayMessages > 0 || u.agySevenDayTokens > 0 {
                            StatChip(
                                icon: "sparkles",
                                tint: Theme.aqua,
                                text: "Antigravity 5h: \(formatTokens(u.agyFiveHourTokens)) tok · \(u.agyFiveHourMessages) turnos"
                            )
                            StatChip(
                                icon: "sparkles",
                                tint: Theme.teal,
                                text: "Antigravity 7d: \(formatTokens(u.agySevenDayTokens)) tok · \(u.agySevenDayMessages) turnos"
                            )
                        }

                        ForEach(u.agyTopModels, id: \.name) { item in
                            StatChip(
                                icon: "cpu",
                                tint: Theme.aqua,
                                text: "\(item.name): \(formatTokens(item.tokens))"
                            )
                        }

                        ForEach(u.topModels, id: \.name) { item in
                            StatChip(
                                icon: "sparkles",
                                tint: Theme.violet,
                                text: "\(item.name): \(formatTokens(item.tokens))"
                            )
                        }

                        if let rl = rateLimits, let spendPct = rl.spendLimitPct {
                            let spendText: String = {
                                if let used = rl.spendUsedUSD, let lim = rl.spendLimitUSD {
                                    return String(format: "Gasto: $%.2f / $%.2f (%d%%)", used, lim, Int(spendPct.rounded()))
                                }
                                return "Gasto: \(Int(spendPct.rounded()))%"
                            }()
                            StatChip(
                                icon: "creditcard.fill",
                                tint: Theme.usageColor(for: spendPct),
                                text: spendText
                            )
                        }
                    }
                }
            }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            CompactWindowRow(
                title: "5h",
                accent: Theme.aqua,
                pct: rateLimits?.fiveHourPct,
                resetAt: rateLimits?.fiveHourReset,
                localText: localUsage.map { "\(formatTokens($0.fiveHourTokens)) tok" },
                now: now
            )
            CompactWindowRow(
                title: "7d",
                accent: Theme.violet,
                pct: rateLimits?.sevenDayPct,
                resetAt: rateLimits?.sevenDayReset,
                localText: localUsage.map { "\(formatTokens($0.sevenDayTokens)) tok" },
                now: now
            )
            if let u = localUsage, (u.agySevenDayTokens > 0 || u.agySevenDayMessages > 0) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(Theme.aqua)
                    Text("Antigravity · 5h: \(formatTokens(u.agyFiveHourTokens)) tok · 7d: \(formatTokens(u.agySevenDayTokens)) tok")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                }
            }
        }
        .padding(9)
        .background(Theme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var fiveHourLocalSummary: String {
        guard let u = localUsage else { return "Lendo transcripts locais…" }
        var parts = [
            "\(formatTokens(u.fiveHourTokens)) tokens",
            "\(u.fiveHourMessages) turnos",
            "\(u.fiveHourSessions) \(u.fiveHourSessions == 1 ? "sessão" : "sessões")"
        ]
        if u.fiveHourCostUSD > 0.009 {
            parts.append(String(format: "$%.2f", u.fiveHourCostUSD))
        }
        return parts.joined(separator: " · ")
    }

    private var sevenDayLocalSummary: String {
        guard let u = localUsage else { return "Lendo transcripts locais…" }
        var parts = [
            "\(formatTokens(u.sevenDayTokens)) tokens",
            "\(u.sevenDayMessages) turnos"
        ]
        if u.sevenDayCostUSD > 0.009 {
            parts.append(String(format: "$%.2f", u.sevenDayCostUSD))
        } else {
            parts.append("\(u.sevenDaySessions) sessões")
        }
        return parts.joined(separator: " · ")
    }
}

private struct WindowUsageCard: View {
    let title: String
    let icon: String
    let accent: Color
    let pct: Double?
    let resetAt: Date?
    let localSummary: String
    let statuslineInstalled: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                if let pct {
                    if let resetAt, resetAt > now {
                        Text("renova em \(formatTimeUntil(resetAt, now: now))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                    Text("\(Int(pct.rounded()))%")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.usageColor(for: pct).opacity(0.20))
                        .foregroundStyle(Theme.usageColor(for: pct))
                        .cornerRadius(6)
                } else {
                    Text(statuslineInstalled ? "aguarda resposta" : "sem status line")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(statuslineInstalled ? Color.white.opacity(0.65) : Theme.amber)
                        .cornerRadius(5)
                }
            }

            GeometryReader { geo in
                let fraction = min(max((pct ?? 0) / 100.0, 0), 1.0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    if let pct, pct > 0 {
                        Capsule()
                            .fill(Theme.usageGradient(for: pct))
                            .frame(width: max(6, geo.size.width * fraction))
                    } else {
                        Capsule()
                            .fill(accent.opacity(0.28))
                            .frame(width: statuslineInstalled ? 28 : 12)
                    }
                }
            }
            .frame(height: 6)

            Text(localSummary)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

private struct CompactWindowRow: View {
    let title: String
    let accent: Color
    let pct: Double?
    let resetAt: Date?
    let localText: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Limite \(title)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                if let localText {
                    Text("· \(localText)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                if let pct {
                    if let resetAt, resetAt > now {
                        Text("\(formatTimeUntil(resetAt, now: now)) ·")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Text("\(Int(pct.rounded()))%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.usageColor(for: pct))
                } else {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            GeometryReader { geo in
                let fraction = min(max((pct ?? 0) / 100.0, 0), 1.0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    if let pct, pct > 0 {
                        Capsule()
                            .fill(Theme.usageGradient(for: pct))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 4)
        }
    }
}

private struct StatChip: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}
