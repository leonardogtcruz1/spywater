import SwiftUI

private enum MainTab: String, CaseIterable {
    case sessions = "Sessões"
    case usage = "Uso do plano"
}

private enum SourceFilter: String, CaseIterable {
    case all = "Todos"
    case claude = "Claude"
    case agy = "Antigravity"

    func matches(_ source: SessionSource) -> Bool {
        switch self {
        case .all: return true
        case .claude: return source == .claudeCode
        case .agy: return source == .antigravity
        }
    }
}

private final class DashboardUIState: ObservableObject {
    @Published var tab: MainTab = .sessions
    @Published var filter: SourceFilter = .all
}

struct DashboardView: View {
    @EnvironmentObject var store: SessionStore
    @StateObject private var ui = DashboardUIState()

    private var allLiveSessions: [Session] {
        store.sortedSessions
    }

    private var liveSessions: [Session] {
        allLiveSessions.filter { ui.filter.matches($0.source) }
    }

    private var filteredRecent: [RecentSession] {
        store.recent.filter { ui.filter.matches($0.source) }
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

            // Soft ambient ocean glows
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.aqua.opacity(0.10), .clear],
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
                            colors: [Theme.violet.opacity(0.09), .clear],
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

                // Minimal Top Bar (~54pt)
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        MiniMascotIcon(mood: mascotMood)
                        Text("SpyWater")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.brandGradient)
                    }

                    Spacer()

                    tabSwitcher

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            store.refreshLocalUsage()
                            store.refreshRecent()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.68))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .help("Atualizar uso e sessões recentes")

                        if #available(macOS 14.0, *) {
                            SettingsLink {
                                Image(systemName: "gearshape.fill")
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.68))
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                            .help("Configurações")
                        }
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 54)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                if ui.tab == .usage {
                    PlanUsageTabView(
                        rateLimits: store.rateLimits,
                        localUsage: store.localUsage,
                        statuslineInstalled: store.statuslineInstalled,
                        now: store.now
                    )
                } else {
                    sessionsTabView
                }
            }

            if ui.tab == .sessions {
                SpyWaterMascotView(
                    mood: mascotMood,
                    attentionCount: store.attentionCount,
                    workingCount: allLiveSessions.filter { store.effectiveState(for: $0) == .working }.count,
                    now: store.now
                )
                .padding(.trailing, 18)
                .padding(.bottom, 14)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isSelected = ui.tab == tab
                Button {
                    ui.tab = tab
                } label: {
                    HStack(spacing: 6) {
                        if tab == .usage {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption2)
                        }
                        Text(tab.rawValue)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        if tab == .sessions && store.attentionCount > 0 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Theme.coral)
                                    .frame(width: 6, height: 6)
                                Text("\(store.attentionCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.coral)
                            }
                        }
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .cornerRadius(9)
    }

    private var sessionsTabView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                // Quiet right-aligned source filter
                HStack(spacing: 14) {
                    Spacer()
                    ForEach(SourceFilter.allCases, id: \.self) { mode in
                        let isSelected = ui.filter == mode
                        Button {
                            ui.filter = mode
                        } label: {
                            VStack(spacing: 3) {
                                Text(mode.rawValue)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.52))
                                Rectangle()
                                    .fill(isSelected ? Theme.aqua : Color.clear)
                                    .frame(height: 1.5)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 2)

                if liveSessions.isEmpty {
                    emptyStateCard
                }

                if !needsYouSessions.isEmpty {
                    HStack(spacing: 7) {
                        AttentionBellIcon(color: Theme.coral, urgent: true)
                        Text("Precisa de você")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.top, 2)

                    ForEach(needsYouSessions) { session in
                        SessionRow(session: session)
                    }
                }

                if !workingSessions.isEmpty {
                    HStack(spacing: 7) {
                        WorkingWaveBars(tint: Theme.aqua)
                        Text("Trabalhando")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.top, 4)

                    ForEach(workingSessions) { session in
                        SessionRow(session: session)
                    }
                }

                if !idleSessions.isEmpty {
                    Text("Prontas")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.80))
                        .padding(.top, 4)

                    ForEach(idleSessions) { session in
                        SessionRow(session: session)
                    }
                }

                if !filteredRecent.isEmpty {
                    Text("Recentes")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        ForEach(Array(filteredRecent.enumerated()), id: \.element.id) { idx, item in
                            RecentRow(item: item)
                            if idx < filteredRecent.count - 1 {
                                Divider().overlay(Color.white.opacity(0.06))
                            }
                        }
                    }
                    .background(Theme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 108)
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.title2)
                .foregroundStyle(Theme.brandGradient)
            Text("Nenhuma sessão ativa")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Abra o `claude` no terminal ou uma conversa no Antigravity.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.60))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .background(Theme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

private final class RecentHoverState: ObservableObject {
    @Published var isHovered = false
}

private struct RecentRow: View {
    let item: RecentSession
    @EnvironmentObject var store: SessionStore
    @StateObject private var hover = RecentHoverState()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.source.icon)
                .font(.caption)
                .foregroundStyle(item.source.color)
                .frame(width: 16)

            Text(item.projectName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            if item.displayTitle != item.projectName {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            Text(formatRelativeTime(item.lastActivityAt, now: store.now))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            if item.source == .antigravity {
                Button("Abrir") {
                    Actions.focusAntigravity(title: item.displayTitle, projectName: item.projectName)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Retomar") {
                    Actions.resume(sessionId: item.id, cwd: item.cwd, terminal: store.terminalApp)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hover.isHovered ? Color.white.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { over in
            hover.isHovered = over
        }
        .onTapGesture {
            if item.source == .antigravity {
                Actions.focusAntigravity(title: item.displayTitle, projectName: item.projectName)
            } else {
                Actions.resume(sessionId: item.id, cwd: item.cwd, terminal: store.terminalApp)
            }
        }
        .help(item.source == .antigravity ? "Clique para abrir no Antigravity" : "Clique para retomar no terminal")
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
