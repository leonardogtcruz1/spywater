import SwiftUI

private enum SourceFilter: String, CaseIterable {
    case all = "Todos"
    case claude = "Claude Code"
    case agy = "Antigravity"

    func matches(_ source: SessionSource) -> Bool {
        switch self {
        case .all: return true
        case .claude: return source == .claudeCode
        case .agy: return source == .antigravity
        }
    }
}

private final class SourceFilterState: ObservableObject {
    @Published var selected: SourceFilter = .all
}

struct DashboardView: View {
    @EnvironmentObject var store: SessionStore
    @StateObject private var filter = SourceFilterState()

    private var allLiveSessions: [Session] {
        store.sortedSessions
    }

    private var liveSessions: [Session] {
        allLiveSessions.filter { filter.selected.matches($0.source) }
    }

    private var filteredRecent: [RecentSession] {
        store.recent.filter { filter.selected.matches($0.source) }
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

    private var mascotMood: MascotMood {
        MascotMood.from(store: store)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.bgGradient
                .ignoresSafeArea()

            // Ambient bioluminescent glows
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.aqua.opacity(0.16), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 280
                        )
                    )
                    .frame(width: 560, height: 560)
                    .position(x: 90, y: 40)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.violet.opacity(0.14), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 280
                        )
                    )
                    .frame(width: 560, height: 560)
                    .position(x: geo.size.width - 70, y: 60)
            }
            .allowsHitTesting(false)

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
                    .background(Theme.coral.opacity(0.20))
                    .foregroundStyle(Theme.coral)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        MiniMascotIcon(mood: mascotMood)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("SpyWater")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Theme.brandGradient)
                            Text("Monitor ao vivo · Claude Code & Antigravity")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                        }

                        Spacer(minLength: 16)

                        HStack(spacing: 8) {
                            HeaderPill(
                                icon: "terminal.fill",
                                text: "\(allLiveSessions.count) ativa\(allLiveSessions.count == 1 ? "" : "s")",
                                tint: Theme.aqua
                            )

                            let allWorking = allLiveSessions.filter { store.effectiveState(for: $0) == .working }.count
                            if allWorking > 0 {
                                HStack(spacing: 6) {
                                    WorkingWaveBars(tint: Theme.teal)
                                    Text("\(allWorking) trabalhando")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.teal)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.teal.opacity(0.14))
                                .overlay(Capsule().stroke(Theme.teal.opacity(0.35), lineWidth: 1))
                                .clipShape(Capsule())
                            }

                            if store.attentionCount > 0 {
                                HeaderPill(
                                    icon: "exclamationmark.bubble.fill",
                                    text: "\(store.attentionCount) pendente\(store.attentionCount == 1 ? "" : "s")",
                                    tint: Theme.coral
                                )
                            }

                            Button {
                                store.refreshLocalUsage()
                                store.refreshRecent()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .padding(6)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Atualizar uso e sessões recentes")

                            if #available(macOS 14.0, *) {
                                SettingsLink {
                                    Image(systemName: "gearshape.fill")
                                        .font(.callout)
                                        .foregroundStyle(.white.opacity(0.75))
                                        .padding(6)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Configurações")
                            }
                        }
                    }

                    UsageHeader(
                        rateLimits: store.rateLimits,
                        localUsage: store.localUsage,
                        statuslineInstalled: store.statuslineInstalled,
                        now: store.now
                    )

                    filterBar
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if liveSessions.isEmpty {
                            emptyStateCard
                        }

                        if !needsYouSessions.isEmpty {
                            SectionHeaderView(
                                title: "Precisa de você",
                                count: needsYouSessions.count,
                                tint: Theme.coral,
                                icon: "exclamationmark.circle.fill"
                            )
                            ForEach(needsYouSessions) { session in
                                SessionRow(session: session)
                            }
                        }

                        if !workingSessions.isEmpty {
                            SectionHeaderView(
                                title: "Trabalhando",
                                count: workingSessions.count,
                                tint: Theme.aqua,
                                icon: "waveform"
                            )
                            ForEach(workingSessions) { session in
                                SessionRow(session: session)
                            }
                        }

                        if !idleSessions.isEmpty {
                            SectionHeaderView(
                                title: "Prontas",
                                count: idleSessions.count,
                                tint: Theme.teal,
                                icon: "checkmark.circle.fill"
                            )
                            ForEach(idleSessions) { session in
                                SessionRow(session: session)
                            }
                        }

                        if !filteredRecent.isEmpty {
                            SectionHeaderView(
                                title: "Recentes — retomar",
                                count: filteredRecent.count,
                                tint: Theme.violet,
                                icon: "clock.arrow.circlepath"
                            )
                            VStack(spacing: 8) {
                                ForEach(filteredRecent) { item in
                                    RecentRow(item: item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 108)
                }
            }

            SpyWaterMascotView(
                mood: mascotMood,
                attentionCount: store.attentionCount,
                workingCount: allLiveSessions.filter { store.effectiveState(for: $0) == .working }.count,
                now: store.now
            )
            .padding(.trailing, 18)
            .padding(.bottom, 14)
        }
        .preferredColorScheme(.dark)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(SourceFilter.allCases, id: \.self) { mode in
                let isSelected = filter.selected == mode
                let count = allLiveSessions.filter { mode.matches($0.source) }.count
                let tint: Color = {
                    switch mode {
                    case .all: return Theme.violet
                    case .claude: return Theme.amber
                    case .agy: return Theme.aqua
                    }
                }()

                Button {
                    filter.selected = mode
                } label: {
                    HStack(spacing: 5) {
                        if mode == .claude {
                            Image(systemName: "terminal.fill").font(.caption2)
                        } else if mode == .agy {
                            Image(systemName: "sparkles").font(.caption2)
                        }
                        Text(mode.rawValue)
                            .font(.caption.weight(isSelected ? .bold : .medium))
                        Text("\(count)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(tint.opacity(isSelected ? 0.30 : 0.14))
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(isSelected ? tint : .white.opacity(0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isSelected ? tint.opacity(0.16) : Color.white.opacity(0.05))
                    .overlay(
                        Capsule().stroke(isSelected ? tint.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.aqua.opacity(0.14))
                    .frame(width: 54, height: 54)
                Image(systemName: "eye.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.brandGradient)
            }
            Text("Nenhuma sessão ativa")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Nenhuma sessão ativa. Abra o `claude` no terminal ou uma conversa no Antigravity.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(Theme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.aqua.opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

private struct HeaderPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.15))
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
    }
}

private struct SectionHeaderView: View {
    let title: String
    let count: Int
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(tint.opacity(0.20))
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
        .padding(.top, 4)
    }
}

private struct RecentRow: View {
    let item: RecentSession
    @EnvironmentObject var store: SessionStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Label(item.source.label, systemImage: item.source.icon)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(item.source.color.opacity(0.16))
                        .foregroundStyle(item.source.color)
                        .clipShape(Capsule())

                    Text(item.projectName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if item.displayTitle != item.projectName {
                        Text("· \(item.displayTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.cwd)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                    if let m = item.model {
                        Text("· \(m)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.violet)
                    }
                    if let c = item.costUSD {
                        Text(String(format: "· $%.2f", c))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.emerald)
                    }
                    Text("· \(formatRelativeTime(item.lastActivityAt, now: store.now))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.50))
                }
            }

            Spacer()

            if item.source == .antigravity {
                Button {
                    Actions.focusAntigravity()
                } label: {
                    Label("Abrir", systemImage: "arrow.up.forward.app.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.aqua)
                .controlSize(.small)
            } else {
                Button {
                    Actions.resume(sessionId: item.id, cwd: item.cwd, terminal: store.terminalApp)
                } label: {
                    Label("Retomar", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.violet)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(12)
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
