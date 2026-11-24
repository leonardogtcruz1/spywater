import SwiftUI

struct PlanUsageTabView: View {
    let rateLimits: RateLimits?
    let localUsage: LocalPlanUsage?
    let statuslineInstalled: Bool
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Section 1: Claude Code
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.amber)
                        Text("Claude Code")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 14) {
                        ClaudeWindowCard(
                            title: "Janela de 5 horas",
                            icon: "bolt.fill",
                            accent: Theme.aqua,
                            pct: rateLimits?.fiveHourPct,
                            resetAt: rateLimits?.fiveHourReset,
                            localText: fiveHourSummary,
                            statuslineInstalled: statuslineInstalled,
                            now: now
                        )

                        ClaudeWindowCard(
                            title: "Limite semanal (7 dias)",
                            icon: "calendar",
                            accent: Theme.violet,
                            pct: rateLimits?.sevenDayPct,
                            resetAt: rateLimits?.sevenDayReset,
                            localText: sevenDaySummary,
                            statuslineInstalled: statuslineInstalled,
                            now: now
                        )
                    }

                    if let rl = rateLimits, let spendPct = rl.spendLimitPct {
                        SpendLimitCard(
                            pct: spendPct,
                            usedUSD: rl.spendUsedUSD,
                            limitUSD: rl.spendLimitUSD,
                            resetAt: rl.spendLimitReset,
                            now: now
                        )
                    }

                    if let u = localUsage {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Hoje")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.88))
                                Spacer()
                                Text("\(u.todayMessages) turnos · \(u.todaySessions) \(u.todaySessions == 1 ? "sessão" : "sessões")")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                            }

                            if !u.topModels.isEmpty {
                                Divider().overlay(Color.white.opacity(0.08))
                                ModelBreakdownList(
                                    title: "Modelos mais usados (7 dias)",
                                    models: u.topModels,
                                    accent: Theme.violet
                                )
                            }
                        }
                        .padding(16)
                        .background(Theme.cardSurface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                        .cornerRadius(12)
                    }
                }

                // Section 2: Antigravity / Gemini
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.aqua)
                        Text("Antigravity / Gemini")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        if let u = localUsage {
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Últimas 5 horas")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.60))
                                    Text("\(formatTokens(u.agyFiveHourTokens)) tokens")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(Theme.aqua)
                                    Text("\(u.agyFiveHourMessages) turnos · \(u.agyFiveHourSessions) \(u.agyFiveHourSessions == 1 ? "conversa" : "conversas")")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 1, height: 48)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Últimos 7 dias")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.60))
                                    Text("\(formatTokens(u.agySevenDayTokens)) tokens")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(Theme.teal)
                                    Text("\(u.agySevenDayMessages) turnos · \(u.agySevenDaySessions) \(u.agySevenDaySessions == 1 ? "conversa" : "conversas")")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !u.agyTopModels.isEmpty {
                                Divider().overlay(Color.white.opacity(0.08))
                                ModelBreakdownList(
                                    title: "Modelos mais usados (7 dias)",
                                    models: u.agyTopModels,
                                    accent: Theme.aqua
                                )
                            }

                            if u.agyTodayMessages > 0 {
                                Divider().overlay(Color.white.opacity(0.08))
                                Text("Hoje: \(u.agyTodayMessages) turnos em \(u.agyTodaySessions) \(u.agyTodaySessions == 1 ? "conversa" : "conversas")")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.60))
                            }
                        } else {
                            Text("Lendo transcripts locais…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.60))
                        }
                    }
                    .padding(16)
                    .background(Theme.cardSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    .cornerRadius(12)
                }
            }
            .padding(20)
        }
    }

    private var fiveHourSummary: String {
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

    private var sevenDaySummary: String {
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

private struct ClaudeWindowCard: View {
    let title: String
    let icon: String
    let accent: Color
    let pct: Double?
    let resetAt: Date?
    let localText: String
    let statuslineInstalled: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.90))
                Spacer()
                if let resetAt, resetAt > now {
                    Text("renova em \(formatTimeUntil(resetAt, now: now))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            if let pct {
                Text("\(Int(pct.rounded()))%")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.usageColor(for: pct))
            } else {
                Text(statuslineInstalled ? "Aguarda 1ª resposta" : "Instale a status line nas Configurações")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statuslineInstalled ? .white.opacity(0.55) : Theme.amber)
                    .padding(.vertical, 4)
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
                    }
                }
            }
            .frame(height: 7)

            Text(localText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.24), lineWidth: 1))
        .cornerRadius(12)
    }
}

private struct SpendLimitCard: View {
    let pct: Double
    let usedUSD: Double?
    let limitUSD: Double?
    let resetAt: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Limite de gasto", systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.90))
                Spacer()
                if let usedUSD, let limitUSD {
                    Text(String(format: "$%.2f / $%.2f (%d%%)", usedUSD, limitUSD, Int(pct.rounded())))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.usageColor(for: pct))
                } else {
                    Text("\(Int(pct.rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.usageColor(for: pct))
                }
                if let resetAt, resetAt > now {
                    Text("· renova em \(formatTimeUntil(resetAt, now: now))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            GeometryReader { geo in
                let fraction = min(max(pct / 100.0, 0), 1.0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(Theme.usageGradient(for: pct))
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Theme.cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        .cornerRadius(12)
    }
}

private struct ModelBreakdownList: View {
    let title: String
    let models: [(name: String, tokens: Int)]
    let accent: Color

    private var maxTokens: Int {
        max(1, models.map(\.tokens).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.60))

            ForEach(models, id: \.name) { item in
                HStack(spacing: 10) {
                    Text(item.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.90))
                        .frame(width: 170, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        let frac = min(max(Double(item.tokens) / Double(maxTokens), 0), 1.0)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(accent.opacity(0.85))
                                .frame(width: max(6, geo.size.width * frac))
                        }
                    }
                    .frame(height: 5)

                    Text(formatTokens(item.tokens))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}
