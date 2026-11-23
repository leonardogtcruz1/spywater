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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(state.color)
                    .frame(width: 9, height: 9)

                Text(state.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.color)

                Text(session.projectName)
                    .font(.headline)

                if session.displayTitle != session.projectName {
                    Text("· \(session.displayTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if session.subagentsRunning > 0 {
                    Label("\(session.subagentsRunning) subagente\(session.subagentsRunning > 1 ? "s" : "")", systemImage: "cpu")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }

                if let model = session.model, !model.isEmpty {
                    Text(model)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.14))
                        .cornerRadius(4)
                }

                if let effort = session.effort, !effort.isEmpty {
                    Text(effort)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let cost = session.costUSD {
                    Text(String(format: "$%.2f", cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(formatRelativeTime(session.lastEventAt, now: store.now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text(session.activity)
                    .font(session.activity.hasPrefix("$ ") ? .system(.caption, design: .monospaced) : .caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

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
        .padding(.vertical, 6)
        .contextMenu {
            Button("Focar terminal") {
                Actions.focusTerminal(termProgram: session.termProgram)
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
            HStack(spacing: 6) {
                ProgressView(value: min(max(pct, 0), 100), total: 100)
                    .frame(width: 70)
                    .tint(isHigh ? .red : (pct >= 60 ? .orange : .blue))
                Text("\(Int(pct.rounded()))% de \(formatTokens(win))")
                    .font(.caption2)
                    .foregroundStyle(isHigh ? .red : .secondary)
                if isHigh {
                    Text("considere /compact")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
