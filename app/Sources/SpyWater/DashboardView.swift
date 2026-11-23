import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: SessionStore

    private var liveSessions: [Session] {
        store.sortedSessions
    }

    private var needsYouSessions: [Session] {
        liveSessions.filter { store.effectiveState(for: $0).priority <= 2 }
    }

    private var workingSessions: [Session] {
        liveSessions.filter { store.effectiveState(for: $0) == .working }
    }

    private var idleSessions: [Session] {
        liveSessions.filter { store.effectiveState(for: $0) == .idle }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let err = store.serverError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Tentar novamente") {
                        store.server.start()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    UsageHeader(rateLimits: store.rateLimits, now: store.now)
                    Spacer(minLength: 16)
                    HStack(spacing: 12) {
                        Label("\(liveSessions.count) ativa\(liveSessions.count == 1 ? "" : "s")", systemImage: "terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if store.attentionCount > 0 {
                            Label("\(store.attentionCount) pendente\(store.attentionCount == 1 ? "" : "s")", systemImage: "exclamationmark.bubble.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        if #available(macOS 14.0, *) {
                            SettingsLink {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(.borderless)
                            .help("Configurações")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            List {
                if liveSessions.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "eye")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Nenhuma sessão do Claude Code ativa. Abra o `claude` em um terminal.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                }

                if !needsYouSessions.isEmpty {
                    Section("Precisa de você") {
                        ForEach(needsYouSessions) { session in
                            SessionRow(session: session)
                        }
                    }
                }

                if !workingSessions.isEmpty {
                    Section("Trabalhando") {
                        ForEach(workingSessions) { session in
                            SessionRow(session: session)
                        }
                    }
                }

                if !idleSessions.isEmpty {
                    Section("Prontas") {
                        ForEach(idleSessions) { session in
                            SessionRow(session: session)
                        }
                    }
                }

                if !store.recent.isEmpty {
                    Section("Recentes — retomar") {
                        ForEach(store.recent) { item in
                            RecentRow(item: item)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct RecentRow: View {
    let item: RecentSession
    @EnvironmentObject var store: SessionStore

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.projectName)
                        .font(.subheadline.weight(.semibold))
                    if item.displayTitle != item.projectName {
                        Text("· \(item.displayTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.cwd)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let m = item.model {
                        Text("· \(m)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let c = item.costUSD {
                        Text(String(format: "· $%.2f", c))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("· \(formatRelativeTime(item.lastActivityAt, now: store.now))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Retomar") {
                Actions.resume(sessionId: item.id, cwd: item.cwd, terminal: store.terminalApp)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Abrir pasta") {
                Actions.openInFinder(cwd: item.cwd)
            }
            Button("Copiar ID") {
                Actions.copyToClipboard(item.id)
            }
        }
    }
}
