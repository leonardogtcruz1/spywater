import SwiftUI

struct SessionRow: View {
    let session: Session
    @EnvironmentObject var store: SessionStore

    private var state: SessionState {
        store.effectiveState(for: session)
    }

    private var sessionPending: [PendingRequest] {
        store.pending(for: session.id)
    }

    private var borderColor: Color {
        switch state {
        case .working: return Theme.aqua.opacity(0.42)
        case .waitingTerminal, .yourTurn: return Theme.amber.opacity(0.45)
        case .error: return Theme.coral.opacity(0.55)
        case .idle: return Theme.teal.opacity(0.22)
        default: return Theme.cardBorder
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state == .working {
                WorkingShimmerStrip()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    PulsingStatusDot(
                        color: state.color,
                        animated: state == .working || state == .needsYou
                    )

                    Text(state.label)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(state.color.opacity(0.18))
                        .foregroundStyle(state.color)
                        .clipShape(Capsule())

                    Label(session.source.label, systemImage: session.source.icon)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(session.source.color.opacity(0.15))
                        .foregroundStyle(session.source.color)
                        .clipShape(Capsule())

                    Text(session.projectName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if session.displayTitle != session.projectName {
                        Text("· \(session.displayTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if session.subagentsRunning > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text("\(session.subagentsRunning) subagente\(session.subagentsRunning > 1 ? "s" : "")")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Theme.aqua.opacity(0.18))
                        .foregroundStyle(Theme.aqua)
                        .clipShape(Capsule())
                    }

                    if let model = session.model, !model.isEmpty {
                        Text(model)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Theme.violet.opacity(0.20))
                            .foregroundStyle(Theme.violet)
                            .overlay(
                                Capsule().stroke(Theme.violet.opacity(0.35), lineWidth: 0.8)
                            )
                            .clipShape(Capsule())
                    }

                    if let effort = session.effort, !effort.isEmpty {
                        Text(effort)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.white.opacity(0.70))
                            .clipShape(Capsule())
                    }

                    if let cost = session.costUSD {
                        Text(String(format: "$%.2f", cost))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.emerald)
                    }

                    Text(formatRelativeTime(session.lastEventAt, now: store.now))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }

                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        if state == .working {
                            WorkingWaveBars(tint: Theme.aqua)
                        }
                        Text(session.activity)
                            .font(session.activity.hasPrefix("$ ") ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.insetSurface)
                    .cornerRadius(8)

                    contextMeter
                }

                if !sessionPending.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(sessionPending) { req in
                            PendingCardView(request: req, isTopmost: req.id == store.topPendingId)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
        }
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            if state == .needsYou {
                NeedsYouPulseBorder(cornerRadius: 14, color: Theme.coral)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .contextMenu {
            if session.source == .antigravity {
                Button("Focar Antigravity") {
                    Actions.focusAntigravity()
                }
            } else {
                Button("Focar terminal") {
                    Actions.focusTerminal(termProgram: session.termProgram)
                }
            }
            Button("Abrir pasta") {
                Actions.openInFinder(cwd: session.cwd)
            }
            Button("Copiar ID") {
                Actions.copyToClipboard(session.id)
            }
        }
    }

    @ViewBuilder
    private var contextMeter: some View {
        if let pct = session.contextPct {
            let win = session.contextWindow ?? 200_000
            let isHigh = pct >= 80
            let tint = isHigh ? Theme.coral : (pct >= 60 ? Theme.amber : Theme.aqua)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        let frac = min(max(pct / 100.0, 0), 1.0)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: isHigh ? [Theme.amber, Theme.coral] : [Theme.teal, tint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * frac))
                        }
                    }
                    .frame(width: 72, height: 5)

                    Text("\(Int(pct.rounded()))% de \(formatTokens(win))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isHigh ? Theme.coral : .white.opacity(0.70))
                }
                if isHigh {
                    Text("considere /compact")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.coral)
                }
            }
        }
    }
}
