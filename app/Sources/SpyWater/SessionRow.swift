import SwiftUI

private final class RowHoverState: ObservableObject {
    @Published var isHovered = false
}

struct SessionRow: View {
    let session: Session
    @EnvironmentObject var store: SessionStore
    @StateObject private var hover = RowHoverState()

    private var state: SessionState {
        store.effectiveState(for: session)
    }

    private var sessionPending: [PendingRequest] {
        store.pending(for: session.id)
    }

    private var borderColor: Color {
        switch state {
        case .working: return Theme.aqua.opacity(0.55)
        case .waitingTerminal, .yourTurn: return Theme.amber.opacity(0.45)
        case .error: return Theme.coral.opacity(0.55)
        case .idle: return Theme.cardBorder
        default: return Theme.cardBorder
        }
    }

    private var needsAttention: Bool {
        state == .needsYou || state == .waitingTerminal || state == .yourTurn || state == .error
    }

    private var isUrgentAttention: Bool {
        state == .needsYou || state == .error
    }

    var body: some View {
        HStack(spacing: 0) {
            if needsAttention {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [state.color, state.color.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5.0)
                    .shadow(color: state.color.opacity(0.75), radius: 7)
            }

            VStack(alignment: .leading, spacing: 0) {
                if state == .working {
                    WorkingShimmerStrip()
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Clickable header + activity area redirects straight to this agent
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            SessionStatusDot(state: state)

                            if needsAttention {
                                let badgeFg = Color(red: 0.05, green: 0.07, blue: 0.12)
                                HStack(spacing: 4) {
                                    AttentionBellIcon(color: badgeFg, urgent: isUrgentAttention)
                                    Text(state.label)
                                        .font(.caption2.weight(.bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(state.color)
                                .foregroundStyle(badgeFg)
                                .clipShape(Capsule())
                            }

                            Image(systemName: session.source.icon)
                                .font(.caption2)
                                .foregroundStyle(session.source.color)

                            Text(session.projectName)
                                .font(.headline)
                                .foregroundStyle(.white)

                            if session.displayTitle != session.projectName {
                                Text("· \(session.displayTitle)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            if session.subagentsRunning > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "cpu")
                                        .font(.caption2)
                                    Text("\(session.subagentsRunning)")
                                        .font(.caption2.weight(.semibold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.aqua.opacity(0.16))
                                .foregroundStyle(Theme.aqua)
                                .clipShape(Capsule())
                            }

                            if let model = session.model, !model.isEmpty {
                                Text(model)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.violet.opacity(0.16))
                                    .foregroundStyle(Theme.violet)
                                    .clipShape(Capsule())
                            }

                            Text(formatRelativeTime(session.lastEventAt, now: store.now))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.48))

                            if state != .working || hover.isHovered {
                                HStack(spacing: 3) {
                                    Text("Abrir")
                                        .font(.caption2.weight(.semibold))
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(state == .working ? Theme.aqua : state.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(hover.isHovered ? 0.12 : 0.06))
                                .clipShape(Capsule())
                            }
                        }

                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                if state == .working {
                                    WorkingWaveBars(tint: Theme.aqua)
                                } else if needsAttention {
                                    Image(systemName: isUrgentAttention ? "exclamationmark.triangle.fill" : "arrow.turn.down.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(state.color)
                                }
                                Text(session.activity)
                                    .font(session.activity.hasPrefix("$ ") ? .system(.caption, design: .monospaced) : .caption)
                                    .foregroundStyle(.white.opacity(0.84))
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, needsAttention ? 8 : 0)
                            .padding(.vertical, needsAttention ? 4 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(needsAttention ? state.color.opacity(0.08) : Color.clear)
                            .cornerRadius(6)

                            contextMeter
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { over in
                        hover.isHovered = over
                    }
                    .onTapGesture {
                        Actions.openLiveSession(session, terminal: store.terminalApp)
                    }
                    .help("Clique para ir até este agente")

                    if !sessionPending.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(sessionPending) { req in
                                PendingCardView(request: req, isTopmost: req.id == store.topPendingId)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
            }
        }
        .background {
            if needsAttention {
                AttentionCardBackground(color: state.color, urgent: isUrgentAttention, hovered: hover.isHovered)
            } else if state == .working {
                WorkingCardBackground(hovered: hover.isHovered)
            } else {
                hover.isHovered ? Theme.cardSurfaceElevated : Theme.cardSurface
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            if needsAttention {
                NeedsYouPulseBorder(cornerRadius: 14, color: state.color, urgent: isUrgentAttention)
            } else if state == .working {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(hover.isHovered ? Theme.aqua.opacity(0.80) : borderColor, lineWidth: 1.4)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(hover.isHovered ? Theme.aqua.opacity(0.35) : borderColor, lineWidth: 1)
            }
        }
        .contextMenu {
            Button(session.source == .antigravity ? "Focar Antigravity" : "Focar terminal") {
                Actions.openLiveSession(session, terminal: store.terminalApp)
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
            let isHigh = pct >= 80
            let tint = isHigh ? Theme.coral : (pct >= 60 ? Theme.amber : Theme.aqua)
            VStack(alignment: .trailing, spacing: 3) {
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
                    .frame(width: 52, height: 4)

                    Text("\(Int(pct.rounded()))%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isHigh ? Theme.coral : .white.opacity(0.62))
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
