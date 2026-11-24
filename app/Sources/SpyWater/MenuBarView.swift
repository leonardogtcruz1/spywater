import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.openWindow) private var openWindow

    private var mascotMood: MascotMood {
        MascotMood.from(store: store)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MiniMascotIcon(mood: mascotMood)
                Text("SpyWater")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.brandGradient)
                Spacer()
                if store.attentionCount > 0 {
                    Text("\(store.attentionCount) pendente\(store.attentionCount == 1 ? "" : "s")")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Theme.coral.opacity(0.20))
                        .foregroundStyle(Theme.coral)
                        .clipShape(Capsule())
                } else {
                    Text("\(store.sortedSessions.count) ativa\(store.sortedSessions.count == 1 ? "" : "s")")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.60))
                }
            }

            UsageHeader(
                rateLimits: store.rateLimits,
                localUsage: store.localUsage,
                statuslineInstalled: store.statuslineInstalled,
                now: store.now,
                compact: true
            )

            if !store.pending.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.pending) { req in
                            CompactPendingRow(request: req) {
                                openMain()
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            let topSessions = Array(store.sortedSessions.prefix(6))
            VStack(alignment: .leading, spacing: 6) {
                if topSessions.isEmpty {
                    Text("Nenhuma sessão ativa")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.vertical, 4)
                } else {
                    ForEach(topSessions) { s in
                        let st = store.effectiveState(for: s)
                        HStack(spacing: 6) {
                            SessionStatusDot(state: st)
                            Text(s.projectName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if st == .working {
                                WorkingWaveBars(tint: Theme.aqua)
                            }
                            Text(s.activity)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                            Spacer()
                            if let pct = s.contextPct {
                                Text("\(Int(pct.rounded()))%")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(pct >= 80 ? Theme.coral : .white.opacity(0.65))
                            }
                        }
                    }
                }
            }
            .padding(9)
            .background(Theme.cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder, lineWidth: 1))
            .cornerRadius(10)

            HStack {
                Button("Abrir painel") {
                    openMain()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.aqua)

                Spacer()

                Button("Sair") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(12)
        .frame(width: 390)
        .background(Theme.bgGradient)
        .preferredColorScheme(.dark)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct CompactPendingRow: View {
    let request: PendingRequest
    let onOpenMain: () -> Void
    @EnvironmentObject var store: SessionStore

    private var projectName: String {
        store.sessions[request.sessionId]?.projectName ?? "Claude"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(projectName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text("· \(SessionStore.describeTool(request.toolName, input: request.toolInput))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
                Spacer()
            }

            if request.kind == .question {
                HStack {
                    Button("Abrir no painel") {
                        onOpenMain()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                    .controlSize(.small)
                    Spacer()
                    Button(request.source == .antigravity ? "Antigravity" : "Terminal") {
                        store.release(request)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.65))
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 6) {
                    Button("Permitir") {
                        store.allow(request)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.emerald)
                    .controlSize(.small)

                    Button("Negar") {
                        store.deny(request)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.coral)
                    .controlSize(.small)

                    Spacer()

                    Button("Abrir") {
                        onOpenMain()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.aqua)
                    .controlSize(.small)
                }
            }
        }
        .padding(9)
        .background(Theme.coral.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.coral.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}
