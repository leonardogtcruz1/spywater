import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UsageHeader(rateLimits: store.rateLimits, now: store.now, compact: true)

            Divider()

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

                Divider()
            }

            let topSessions = Array(store.sortedSessions.prefix(6))
            if topSessions.isEmpty {
                Text("Nenhuma sessão ativa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(topSessions) { s in
                        let st = store.effectiveState(for: s)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(st.color)
                                .frame(width: 7, height: 7)
                            Text(s.projectName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(s.activity)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            if let pct = s.contextPct {
                                Text("\(Int(pct.rounded()))%")
                                    .font(.caption2)
                                    .foregroundStyle(pct >= 80 ? .red : .secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Abrir painel") {
                    openMain()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Sair") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 380)
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
                Text("· \(SessionStore.describeTool(request.toolName, input: request.toolInput))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            if request.kind == .question {
                HStack {
                    Button("Abrir no painel") {
                        onOpenMain()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                    Button("Terminal") {
                        store.release(request)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 6) {
                    Button("Permitir") {
                        store.allow(request)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)

                    Button("Negar") {
                        store.deny(request)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)

                    Spacer()

                    Button("Abrir") {
                        onOpenMain()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .background(Color.red.opacity(0.07))
        .cornerRadius(6)
    }
}
