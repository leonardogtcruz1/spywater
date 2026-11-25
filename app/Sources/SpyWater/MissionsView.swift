import AppKit
import SwiftUI

private final class MissionComposerState: ObservableObject {
    @Published var goal: String = ""
    @Published var projectPath: String = ""
    @Published var maxWorkers: Int = 3
    @Published var permissionMode: MissionPermissionMode = .spywaterGate

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("Selecionar pasta", "Select folder")
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
        }
    }
}

private final class ExpandedLogsState: ObservableObject {
    @Published var expandedIds: Set<UUID> = []

    func isExpanded(_ id: UUID) -> Bool {
        expandedIds.contains(id)
    }

    func toggle(_ id: UUID) {
        if expandedIds.contains(id) {
            expandedIds.remove(id)
        } else {
            expandedIds.insert(id)
        }
    }
}

struct MissionsView: View {
    @EnvironmentObject var engine: MissionEngine
    @StateObject private var composer = MissionComposerState()
    @StateObject private var logsState = ExpandedLogsState()

    private var canStart: Bool {
        !composer.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !composer.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                composerCard

                if engine.missions.isEmpty {
                    emptyMissionsCard
                } else {
                    ForEach(engine.missions) { mission in
                        MissionCardView(
                            mission: mission,
                            logsExpanded: logsState.isExpanded(mission.id),
                            onToggleLogs: { logsState.toggle(mission.id) }
                        )
                    }
                }
            }
            .padding(20)
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.aqua)
                Text(L10n.t("Nova missão · Divisor de tarefas (Claude Code)", "New mission · Task splitter (Claude Code)"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $composer.goal)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(height: 88)

                if composer.goal.isEmpty {
                    Text(L10n.t(
                        "Ex.: Crie uma API REST em Node com autenticação JWT, testes e frontend React…",
                        "e.g. Build a Node REST API with JWT auth, tests, and React frontend…"
                    ))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.insetSurface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .cornerRadius(8)

            HStack(spacing: 8) {
                TextField(L10n.t("Pasta do projeto (ex.: ~/Desktop/meu-app)", "Project folder (e.g. ~/Desktop/my-app)"), text: $composer.projectPath)
                    .textFieldStyle(.roundedBorder)

                Button(L10n.t("Escolher pasta…", "Choose folder…")) {
                    composer.pickFolder()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text(L10n.t("Agentes paralelos:", "Parallel agents:"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                    Picker("", selection: $composer.maxWorkers) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .labelsHidden()
                    .frame(width: 58)
                }

                HStack(spacing: 6) {
                    Text(L10n.t("Permissões:", "Permissions:"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                    Picker("", selection: $composer.permissionMode) {
                        ForEach(MissionPermissionMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                Spacer()

                Button {
                    engine.startMission(
                        goal: composer.goal,
                        projectPath: composer.projectPath,
                        maxWorkers: composer.maxWorkers,
                        permissionMode: composer.permissionMode
                    )
                    composer.goal = ""
                } label: {
                    Label(L10n.t("Dividir e iniciar", "Split & start"), systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.aqua)
                .disabled(!canStart)
            }
        }
        .padding(16)
        .background(Theme.cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.aqua.opacity(0.24), lineWidth: 1))
        .cornerRadius(14)
    }

    private var emptyMissionsCard: some View {
        VStack(spacing: 6) {
            Text(L10n.t("Nenhuma missão criada ainda", "No missions yet"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(L10n.t(
                "Descreva o que deseja construir acima: o SpyWater divide automaticamente em subtarefas e mantém vários agentes rodando em git worktrees até terminar.",
                "Describe what you want to build above: SpyWater automatically splits it into subtasks and keeps parallel agents running in git worktrees until done."
            ))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Theme.cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        .cornerRadius(12)
    }
}

private struct MissionCardView: View {
    let mission: Mission
    let logsExpanded: Bool
    let onToggleLogs: () -> Void
    @EnvironmentObject var engine: MissionEngine

    private var projectFolderName: String {
        let name = URL(fileURLWithPath: mission.projectPath).lastPathComponent
        return name.isEmpty ? mission.projectPath : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statusDot

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(mission.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(mission.status.label)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(mission.status.color.opacity(0.18))
                            .foregroundStyle(mission.status.color)
                            .clipShape(Capsule())
                    }
                    HStack(spacing: 8) {
                        Text(projectFolderName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        if !mission.tasks.isEmpty {
                            Text("· \(mission.completedCount)/\(mission.tasks.count) \(L10n.t("tarefas", "tasks"))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                        Text(L10n.t("· até \(mission.maxWorkers) agentes", "· up to \(mission.maxWorkers) agents"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                Spacer()

                controlButtons
            }

            if !mission.tasks.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.aqua, Theme.emerald], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(mission.progress > 0 ? 6 : 0, geo.size.width * mission.progress))
                    }
                }
                .frame(height: 5)
            }

            if let err = mission.errorMessage, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                        .font(.caption)
                }
                .foregroundStyle(Theme.coral)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.coral.opacity(0.12))
                .cornerRadius(8)
            }

            if !mission.tasks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(mission.tasks.enumerated()), id: \.element.id) { idx, task in
                        MissionTaskRow(missionId: mission.id, task: task)
                        if idx < mission.tasks.count - 1 {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }
                }
                .background(Theme.insetSurface)
                .cornerRadius(10)
            }

            HStack {
                Button {
                    onToggleLogs()
                } label: {
                    Label(
                        logsExpanded
                            ? L10n.t("Ocultar logs", "Hide logs")
                            : L10n.t("Ver logs (\(mission.logs.count))", "Show logs (\(mission.logs.count))"),
                        systemImage: logsExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(L10n.t("Abrir pasta", "Open folder")) {
                    Actions.openInFinder(cwd: mission.projectPath)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            }

            if logsExpanded {
                ScrollView {
                    Text(mission.logs.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 150)
                .background(Color.black.opacity(0.40))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Theme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(mission.status == .running ? Theme.aqua.opacity(0.45) : Theme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(14)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch mission.status {
        case .planning, .running:
            WorkingOrbitDot()
        case .failed, .paused:
            AttentionBeaconDot(color: mission.status.color, urgent: mission.status == .failed)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Theme.emerald)
                .frame(width: 18, height: 18)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 6) {
            if mission.status == .planning || mission.status == .running {
                Button(L10n.t("Pausar", "Pause")) {
                    engine.pauseMission(id: mission.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if mission.status == .paused || mission.status == .failed {
                Button(L10n.t("Retomar", "Resume")) {
                    engine.resumeMission(id: mission.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.aqua)
                .controlSize(.small)
            }
            if mission.status == .planning || mission.status == .running || mission.status == .paused {
                Button(L10n.t("Cancelar", "Cancel")) {
                    engine.cancelMission(id: mission.id)
                }
                .buttonStyle(.bordered)
                .tint(Theme.coral)
                .controlSize(.small)
            }
            if mission.status == .completed || mission.status == .failed || mission.status == .cancelled {
                Button(L10n.t("Remover", "Remove")) {
                    engine.deleteMission(id: mission.id)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.55))
                .controlSize(.small)
            }
        }
    }
}

private struct MissionTaskRow: View {
    let missionId: UUID
    let task: MissionTask
    @EnvironmentObject var engine: MissionEngine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            taskIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.id)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(task.status.color.opacity(0.20))
                        .foregroundStyle(task.status.color)
                        .cornerRadius(4)

                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    if !task.dependsOn.isEmpty {
                        let deps = task.dependsOn.joined(separator: ", ")
                        Text(L10n.t("após \(deps)", "after \(deps)"))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    if task.attempts > 1 {
                        Text(L10n.t("tentativa \(task.attempts)/\(task.maxAttempts)", "attempt \(task.attempts)/\(task.maxAttempts)"))
                            .font(.caption2)
                            .foregroundStyle(Theme.amber)
                    }

                    Spacer()

                    if task.status == .failed {
                        Button(L10n.t("Tentar de novo", "Retry")) {
                            engine.retryTask(missionId: missionId, taskId: task.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                if let err = task.lastError, !err.isEmpty {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Theme.coral)
                        .lineLimit(2)
                } else if let out = task.lastOutput, !out.isEmpty, task.status != .pending {
                    Text(out)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var taskIcon: some View {
        switch task.status {
        case .running, .merging:
            WorkingOrbitDot()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.emerald)
                .frame(width: 18, height: 18)
        case .pending:
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.coral)
                .frame(width: 18, height: 18)
        case .blocked:
            Image(systemName: "pause.circle")
                .font(.caption)
                .foregroundStyle(Theme.amber)
                .frame(width: 18, height: 18)
        }
    }
}
