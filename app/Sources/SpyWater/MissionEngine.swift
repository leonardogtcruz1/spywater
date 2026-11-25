import Foundation

@MainActor
final class MissionEngine: ObservableObject {
    @Published var missions: [Mission] = []

    var onMissionCompleted: ((String) -> Void)?

    private var activeProcesses: [String: Process] = [:]

    private static var persistenceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spywater/missions.json")
    }

    init() {
        loadMissions()
    }

    var hasActiveMission: Bool {
        missions.contains { $0.status == .planning || $0.status == .running }
    }

    // MARK: - Persistence

    private func loadMissions() {
        let url = Self.persistenceURL
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var loaded = try? decoder.decode([Mission].self, from: data) else { return }

        var dirty = false
        for i in loaded.indices {
            if loaded[i].status == .planning || loaded[i].status == .running {
                loaded[i].status = .paused
                loaded[i].errorMessage = "SpyWater foi reiniciado durante a execução. Clique em Retomar para continuar."
                loaded[i].updatedAt = Date()
                dirty = true
            }
            for j in loaded[i].tasks.indices {
                if loaded[i].tasks[j].status == .running || loaded[i].tasks[j].status == .merging {
                    loaded[i].tasks[j].status = .pending
                    dirty = true
                }
            }
        }
        missions = loaded
        if dirty {
            saveMissions()
        }
    }

    private func saveMissions() {
        let fm = FileManager.default
        let dir = Self.persistenceURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(missions) {
            try? data.write(to: Self.persistenceURL, options: .atomic)
        }
    }

    private func missionIndex(_ id: UUID) -> Int? {
        missions.firstIndex { $0.id == id }
    }

    private func appendLog(_ missionId: UUID, _ line: String) {
        guard let idx = missionIndex(missionId) else { return }
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        let stamp = df.string(from: Date())
        missions[idx].logs.append("[\(stamp)] \(line)")
        if missions[idx].logs.count > 400 {
            missions[idx].logs.removeFirst(missions[idx].logs.count - 400)
        }
        missions[idx].updatedAt = Date()
    }

    // MARK: - Controls

    @discardableResult
    func startMission(
        goal: String,
        projectPath: String,
        maxWorkers: Int,
        permissionMode: MissionPermissionMode
    ) -> Mission {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let expandedPath = NSString(string: projectPath.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        let cleanPath = expandedPath.isEmpty ? NSHomeDirectory() : expandedPath
        let clampedWorkers = max(1, min(6, maxWorkers))
        let folderName = URL(fileURLWithPath: cleanPath).lastPathComponent
        let defaultTitle = folderName.isEmpty ? "Nova missão" : folderName

        let mission = Mission(
            id: UUID(),
            title: defaultTitle,
            goal: trimmedGoal,
            projectPath: cleanPath,
            baseBranch: "main",
            maxWorkers: clampedWorkers,
            permissionMode: permissionMode,
            status: .planning,
            tasks: [],
            logs: [],
            createdAt: Date(),
            updatedAt: Date(),
            errorMessage: nil
        )

        missions.insert(mission, at: 0)
        appendLog(mission.id, "Iniciando missão em \(cleanPath) (até \(clampedWorkers) agentes)…")
        saveMissions()
        runPlanner(missionId: mission.id)
        return mission
    }

    func pauseMission(id: UUID) {
        guard let idx = missionIndex(id) else { return }
        missions[idx].status = .paused
        missions[idx].updatedAt = Date()
        appendLog(id, "Missão pausada pelo usuário.")

        let planKey = "plan-\(id.uuidString)"
        if let proc = activeProcesses.removeValue(forKey: planKey), proc.isRunning {
            proc.terminate()
        }

        let taskPrefix = "task-\(id.uuidString)-"
        for (key, proc) in activeProcesses where key.hasPrefix(taskPrefix) {
            if proc.isRunning { proc.terminate() }
            activeProcesses.removeValue(forKey: key)
        }

        let repoPath = missions[idx].projectPath
        for j in missions[idx].tasks.indices {
            if missions[idx].tasks[j].status == .running || missions[idx].tasks[j].status == .merging {
                let wt = missions[idx].tasks[j].worktreePath
                let br = missions[idx].tasks[j].branchName
                missions[idx].tasks[j].status = .pending
                missions[idx].tasks[j].worktreePath = nil
                if let wt {
                    DispatchQueue.global(qos: .utility).async {
                        WorktreeManager.removeWorktree(repoPath: repoPath, worktreePath: wt, branchName: br, deleteBranch: true)
                    }
                }
            }
        }
        saveMissions()
    }

    func resumeMission(id: UUID) {
        guard let idx = missionIndex(id) else { return }
        missions[idx].errorMessage = nil
        missions[idx].updatedAt = Date()

        if missions[idx].tasks.isEmpty {
            missions[idx].status = .planning
            appendLog(id, "Reiniciando planejador…")
            saveMissions()
            runPlanner(missionId: id)
            return
        }

        for j in missions[idx].tasks.indices {
            if missions[idx].tasks[j].status == .blocked || missions[idx].tasks[j].status == .failed {
                if missions[idx].tasks[j].status == .failed {
                    missions[idx].tasks[j].attempts = 0
                }
                missions[idx].tasks[j].status = .pending
                missions[idx].tasks[j].lastError = nil
            }
        }
        missions[idx].status = .running
        appendLog(id, "Missão retomada.")
        saveMissions()
        scheduleNextTasks(for: id)
    }

    func retryTask(missionId: UUID, taskId: String) {
        guard let idx = missionIndex(missionId),
              let tIdx = missions[idx].tasks.firstIndex(where: { $0.id == taskId })
        else { return }

        missions[idx].tasks[tIdx].attempts = 0
        missions[idx].tasks[tIdx].status = .pending
        missions[idx].tasks[tIdx].lastError = nil
        for j in missions[idx].tasks.indices where missions[idx].tasks[j].status == .blocked {
            missions[idx].tasks[j].status = .pending
        }
        missions[idx].errorMessage = nil
        missions[idx].status = .running
        appendLog(missionId, "[\(taskId)] Reenfileirada para nova tentativa.")
        saveMissions()
        scheduleNextTasks(for: missionId)
    }

    func cancelMission(id: UUID) {
        guard let idx = missionIndex(id) else { return }
        missions[idx].status = .cancelled
        missions[idx].updatedAt = Date()
        appendLog(id, "Missão cancelada.")

        let planKey = "plan-\(id.uuidString)"
        if let proc = activeProcesses.removeValue(forKey: planKey), proc.isRunning {
            proc.terminate()
        }
        let taskPrefix = "task-\(id.uuidString)-"
        for (key, proc) in activeProcesses where key.hasPrefix(taskPrefix) {
            if proc.isRunning { proc.terminate() }
            activeProcesses.removeValue(forKey: key)
        }

        let repoPath = missions[idx].projectPath
        for j in missions[idx].tasks.indices {
            if let wt = missions[idx].tasks[j].worktreePath {
                let br = missions[idx].tasks[j].branchName
                missions[idx].tasks[j].worktreePath = nil
                DispatchQueue.global(qos: .utility).async {
                    WorktreeManager.removeWorktree(repoPath: repoPath, worktreePath: wt, branchName: br, deleteBranch: true)
                }
            }
        }
        saveMissions()
    }

    func deleteMission(id: UUID) {
        if let idx = missionIndex(id),
           missions[idx].status == .planning || missions[idx].status == .running {
            cancelMission(id: id)
        }
        missions.removeAll { $0.id == id }
        saveMissions()
    }

    // MARK: - Planner

    private func runPlanner(missionId: UUID) {
        guard let idx = missionIndex(missionId) else { return }
        let mission = missions[idx]

        guard let claudePath = Self.resolveClaudePath() else {
            missions[idx].status = .failed
            missions[idx].errorMessage = "Binário `claude` não encontrado (~/.local/bin/claude)."
            appendLog(missionId, "ERRO: claude CLI não encontrado.")
            saveMissions()
            return
        }

        let goal = mission.goal
        let projectPath = mission.projectPath

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gitInit = WorktreeManager.ensureGitRepo(at: projectPath)
            guard gitInit.ok else {
                DispatchQueue.main.async {
                    guard let self, let i = self.missionIndex(missionId) else { return }
                    self.missions[i].status = .failed
                    self.missions[i].errorMessage = gitInit.error
                    self.appendLog(missionId, "ERRO Git: \(gitInit.error ?? "desconhecido")")
                    self.saveMissions()
                }
                return
            }

            DispatchQueue.main.async {
                guard let self, let i = self.missionIndex(missionId) else { return }
                self.missions[i].baseBranch = gitInit.baseBranch
                self.appendLog(missionId, "Repositório pronto (branch base: \(gitInit.baseBranch)). Chamando planejador…")
                self.saveMissions()
            }

            let schema = """
            {"type":"object","properties":{"title":{"type":"string"},"tasks":{"type":"array","minItems":1,"items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"prompt":{"type":"string"},"depends_on":{"type":"array","items":{"type":"string"}},"verify_command":{"type":"string"}},"required":["id","title","prompt","depends_on"]}}},"required":["title","tasks"]}
            """

            let plannerPrompt = """
            Você é um arquiteto de software dividindo um projeto em subtarefas executáveis por agentes Claude Code em paralelo (cada agente roda em sua própria git worktree isolada).

            Pasta do projeto: \(projectPath)
            Objetivo do usuário:
            \(goal)

            Regras obrigatórias:
            1. Inspecione brevemente os arquivos existentes na pasta (se houver) apenas para entender a stack atual. NÃO edite nenhum arquivo.
            2. Divida o trabalho em 2 a 8 tarefas bem definidas (`id`: "T1", "T2", ...).
            3. Tarefas que dependem de setup inicial devem listar o ID em `depends_on` (ex.: T1 cria a estrutura base, T2 e T3 rodam em paralelo após T1 tocando arquivos disjuntos para evitar conflitos de merge, e a última tarefa integra/testa tudo).
            4. Cada `prompt` deve ser completo, autocontido e especificar claramente os arquivos que a tarefa possui/edita.
            5. Preencha `verify_command` quando houver um comando rápido de verificação/build/teste (ou string vazia `""`).
            6. Responda exclusivamente no JSON do schema solicitado, com títulos curtos em português.
            """

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: claudePath)
            proc.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
            proc.environment = Self.buildEnvironment()
            proc.arguments = [
                "-p", plannerPrompt,
                "--output-format", "json",
                "--json-schema", schema,
                "--permission-mode", "plan",
                "--name", "[Missão] Planejador"
            ]
            proc.standardInput = FileHandle.nullDevice

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            let planKey = "plan-\(missionId.uuidString)"
            DispatchQueue.main.async {
                self?.activeProcesses[planKey] = proc
            }

            do {
                try proc.run()
            } catch {
                DispatchQueue.main.async {
                    guard let self, let i = self.missionIndex(missionId) else { return }
                    self.activeProcesses.removeValue(forKey: planKey)
                    self.missions[i].status = .failed
                    self.missions[i].errorMessage = "Falha ao executar claude: \(error.localizedDescription)"
                    self.appendLog(missionId, "ERRO ao iniciar planejador: \(error.localizedDescription)")
                    self.saveMissions()
                }
                return
            }

            var outData = Data()
            var errData = Data()
            let dg = DispatchGroup()
            dg.enter()
            DispatchQueue.global(qos: .utility).async {
                outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                dg.leave()
            }
            dg.enter()
            DispatchQueue.global(qos: .utility).async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                dg.leave()
            }
            dg.wait()
            proc.waitUntilExit()

            let outStr = String(decoding: outData, as: UTF8.self)
            let errStr = String(decoding: errData, as: UTF8.self)
            let exitCode = proc.terminationStatus

            DispatchQueue.main.async {
                guard let self, let i = self.missionIndex(missionId) else { return }
                self.activeProcesses.removeValue(forKey: planKey)
                guard self.missions[i].status == .planning else { return }

                let combined = outStr + "\n" + errStr
                if Self.isAuthFailure(combined) {
                    self.missions[i].status = .paused
                    self.missions[i].errorMessage = "Autenticação do Claude expirada. Rode `claude auth login` no terminal e clique em Retomar."
                    self.appendLog(missionId, "Pausada: autenticação do Claude expirada.")
                    self.saveMissions()
                    return
                }

                guard exitCode == 0, let parsed = Self.parsePlannerOutput(outStr) else {
                    let snippet = String((errStr.isEmpty ? outStr : errStr).trimmingCharacters(in: .whitespacesAndNewlines).prefix(320))
                    self.missions[i].status = .failed
                    self.missions[i].errorMessage = "Planejador falhou (código \(exitCode)): \(snippet)"
                    self.appendLog(missionId, "ERRO no planejador (código \(exitCode)): \(snippet)")
                    self.saveMissions()
                    return
                }

                if let title = parsed.title, !title.isEmpty {
                    self.missions[i].title = title
                }
                self.missions[i].tasks = parsed.tasks
                self.missions[i].status = .running
                self.missions[i].errorMessage = nil
                self.appendLog(missionId, "Plano gerado com \(parsed.tasks.count) tarefas. Iniciando workers…")
                self.saveMissions()
                self.scheduleNextTasks(for: missionId)
            }
        }
    }

    // MARK: - DAG Scheduler & Workers

    private func scheduleNextTasks(for missionId: UUID) {
        guard let idx = missionIndex(missionId) else { return }
        guard missions[idx].status == .running else { return }

        var activeCount = missions[idx].tasks.filter { $0.status == .running || $0.status == .merging }.count
        let allIds = Set(missions[idx].tasks.map(\.id))

        while activeCount < missions[idx].maxWorkers {
            let doneIds = Set(missions[idx].tasks.filter { $0.status == .done }.map(\.id))
            guard let nextIdx = missions[idx].tasks.firstIndex(where: { task in
                guard task.status == .pending else { return false }
                let validDeps = task.dependsOn.filter { allIds.contains($0) }
                return validDeps.allSatisfy { doneIds.contains($0) }
            }) else {
                break
            }

            let taskId = missions[idx].tasks[nextIdx].id
            runWorker(missionId: missionId, taskId: taskId)
            activeCount += 1
        }

        let remainingActive = missions[idx].tasks.filter { $0.status == .running || $0.status == .merging }.count
        if remainingActive == 0 {
            if !missions[idx].tasks.isEmpty && missions[idx].tasks.allSatisfy({ $0.status == .done }) {
                missions[idx].status = .completed
                appendLog(missionId, "Missão concluída com sucesso!")
                saveMissions()
                onMissionCompleted?(missions[idx].title)
            } else {
                for j in missions[idx].tasks.indices where missions[idx].tasks[j].status == .pending {
                    missions[idx].tasks[j].status = .blocked
                }
                missions[idx].status = .failed
                if missions[idx].errorMessage == nil {
                    missions[idx].errorMessage = "Missão interrompida porque uma ou mais tarefas falharam."
                }
                appendLog(missionId, "Missão interrompida por tarefas com falha.")
                saveMissions()
            }
        }
    }

    private func runWorker(missionId: UUID, taskId: String) {
        guard let idx = missionIndex(missionId),
              let tIdx = missions[idx].tasks.firstIndex(where: { $0.id == taskId })
        else { return }

        guard let claudePath = Self.resolveClaudePath() else {
            missions[idx].tasks[tIdx].status = .failed
            missions[idx].tasks[tIdx].lastError = "Binário `claude` não encontrado."
            saveMissions()
            scheduleNextTasks(for: missionId)
            return
        }

        let prevError = missions[idx].tasks[tIdx].lastError
        missions[idx].tasks[tIdx].attempts += 1
        missions[idx].tasks[tIdx].status = .running
        missions[idx].tasks[tIdx].startedAt = Date()
        missions[idx].tasks[tIdx].lastError = nil
        missions[idx].tasks[tIdx].lastOutput = L10n.t("Preparando worktree…", "Preparing worktree…")

        let mission = missions[idx]
        let task = mission.tasks[tIdx]
        let attempt = task.attempts

        let depSummary = task.dependsOn.compactMap { depId -> String? in
            guard let dep = mission.tasks.first(where: { $0.id == depId && $0.status == .done }) else { return nil }
            return "- \(dep.id): \(dep.title)"
        }.joined(separator: "\n")

        appendLog(missionId, "[\(task.id)] Iniciando worker (tentativa \(attempt)/\(task.maxAttempts))…")
        saveMissions()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let wt = WorktreeManager.createWorktree(
                repoPath: mission.projectPath,
                missionShortId: mission.shortId,
                taskId: task.id,
                baseBranch: mission.baseBranch
            )
            if let wtErr = wt.error {
                DispatchQueue.main.async {
                    self?.handleTaskFailure(missionId: missionId, taskId: taskId, error: wtErr)
                }
                return
            }

            DispatchQueue.main.async {
                guard let self, let i = self.missionIndex(missionId),
                      let j = self.missions[i].tasks.firstIndex(where: { $0.id == taskId })
                else { return }
                self.missions[i].tasks[j].worktreePath = wt.worktreePath
                self.missions[i].tasks[j].branchName = wt.branchName
                self.missions[i].tasks[j].lastOutput = L10n.t("Executando Claude Code…", "Running Claude Code…")
                self.saveMissions()
            }

            var workerPrompt = """
            Você é um agente autônomo executando uma subtarefa de uma missão maior no repositório do projeto.

            Objetivo geral da missão:
            \(mission.goal)

            Sua tarefa (\(task.id)): \(task.title)
            Instruções:
            \(task.prompt)

            Contexto do ambiente:
            - Você está trabalhando em uma git worktree isolada na branch `\(wt.branchName)`.
            - Foque apenas no escopo e nos arquivos desta tarefa; ao finalizar, suas alterações serão integradas automaticamente na branch `\(mission.baseBranch)`.
            """

            if !depSummary.isEmpty {
                workerPrompt += "\n\nTarefas já concluídas antes desta:\n\(depSummary)"
            }
            if let verify = task.verifyCommand, !verify.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workerPrompt += "\n\nComando de verificação que será executado após você terminar: `\(verify)`"
            }
            if attempt > 1, let prevError, !prevError.isEmpty {
                workerPrompt += "\n\nATENÇÃO — Tentativa anterior falhou com:\n\(prevError)\nCorrija o problema."
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: claudePath)
            proc.currentDirectoryURL = URL(fileURLWithPath: wt.worktreePath, isDirectory: true)
            proc.environment = Self.buildEnvironment()

            var args = [
                "-p", workerPrompt,
                "--output-format", "stream-json",
                "--verbose",
                "--name", "[Missão] \(task.id): \(task.title)"
            ]
            if mission.permissionMode == .autonomous {
                args.append("--dangerously-skip-permissions")
            } else {
                args += ["--permission-mode", "acceptEdits"]
            }
            proc.arguments = args
            proc.standardInput = FileHandle.nullDevice

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            let procKey = "task-\(missionId.uuidString)-\(taskId)"
            DispatchQueue.main.async {
                self?.activeProcesses[procKey] = proc
            }

            do {
                try proc.run()
            } catch {
                WorktreeManager.removeWorktree(repoPath: mission.projectPath, worktreePath: wt.worktreePath, branchName: wt.branchName, deleteBranch: true)
                DispatchQueue.main.async {
                    self?.activeProcesses.removeValue(forKey: procKey)
                    self?.handleTaskFailure(missionId: missionId, taskId: taskId, error: "Falha ao iniciar claude: \(error.localizedDescription)")
                }
                return
            }

            var stderrData = Data()
            let errGroup = DispatchGroup()
            errGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
                errGroup.leave()
            }

            var lineBuffer = Data()
            var rawStdoutLines: [String] = []
            var lastErrorText: String?

            while true {
                let chunk = outPipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                lineBuffer.append(chunk)

                while let nlIndex = lineBuffer.firstIndex(of: 0x0A) {
                    let lineData = lineBuffer.subdata(in: 0..<nlIndex)
                    lineBuffer.removeSubrange(0...nlIndex)
                    let lineStr = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !lineStr.isEmpty else { continue }
                    rawStdoutLines.append(lineStr)
                    if rawStdoutLines.count > 60 { rawStdoutLines.removeFirst() }

                    if let event = Self.parseStreamEvent(lineData) {
                        if let err = event.errorText { lastErrorText = err }
                        DispatchQueue.main.async {
                            guard let self, let i = self.missionIndex(missionId),
                                  let j = self.missions[i].tasks.firstIndex(where: { $0.id == taskId })
                            else { return }
                            if let sid = event.sessionId {
                                self.missions[i].tasks[j].sessionId = sid
                            }
                            if let snippet = event.snippet {
                                self.missions[i].tasks[j].lastOutput = snippet
                            }
                        }
                    }
                }
            }

            errGroup.wait()
            proc.waitUntilExit()

            let stderrStr = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let exitCode = proc.terminationStatus

            DispatchQueue.main.async {
                self?.activeProcesses.removeValue(forKey: procKey)
            }

            var stillRunning = false
            let checkGroup = DispatchGroup()
            checkGroup.enter()
            DispatchQueue.main.async {
                if let self, let i = self.missionIndex(missionId) {
                    stillRunning = (self.missions[i].status == .running)
                }
                checkGroup.leave()
            }
            checkGroup.wait()

            guard stillRunning else {
                WorktreeManager.removeWorktree(repoPath: mission.projectPath, worktreePath: wt.worktreePath, branchName: wt.branchName, deleteBranch: true)
                return
            }

            let combinedRaw = rawStdoutLines.joined(separator: "\n") + "\n" + stderrStr
            if exitCode != 0 {
                WorktreeManager.removeWorktree(repoPath: mission.projectPath, worktreePath: wt.worktreePath, branchName: wt.branchName, deleteBranch: true)

                if Self.isAuthFailure(combinedRaw) {
                    DispatchQueue.main.async {
                        guard let self, let i = self.missionIndex(missionId),
                              let j = self.missions[i].tasks.firstIndex(where: { $0.id == taskId })
                        else { return }
                        self.missions[i].status = .paused
                        self.missions[i].errorMessage = "Autenticação do Claude expirada. Rode `claude auth login` no terminal e clique em Retomar."
                        self.missions[i].tasks[j].status = .pending
                        self.missions[i].tasks[j].attempts = max(0, self.missions[i].tasks[j].attempts - 1)
                        self.missions[i].tasks[j].worktreePath = nil
                        self.appendLog(missionId, "[\(taskId)] Pausada: autenticação expirada.")
                        self.saveMissions()
                    }
                    return
                }

                let errMsg = lastErrorText ?? (stderrStr.isEmpty ? "Claude saiu com código \(exitCode)" : String(stderrStr.prefix(400)))
                DispatchQueue.main.async {
                    self?.handleTaskFailure(missionId: missionId, taskId: taskId, error: errMsg)
                }
                return
            }

            // Optional verification command inside worktree before merge
            if let verify = task.verifyCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !verify.isEmpty {
                DispatchQueue.main.async {
                    guard let self, let i = self.missionIndex(missionId),
                          let j = self.missions[i].tasks.firstIndex(where: { $0.id == taskId })
                    else { return }
                    self.missions[i].tasks[j].lastOutput = L10n.t("Verificando: \(verify)", "Verifying: \(verify)")
                }
                let verifyRes = Self.runShellVerify(command: verify, in: wt.worktreePath)
                if !verifyRes.ok {
                    WorktreeManager.removeWorktree(repoPath: mission.projectPath, worktreePath: wt.worktreePath, branchName: wt.branchName, deleteBranch: true)
                    DispatchQueue.main.async {
                        self?.handleTaskFailure(missionId: missionId, taskId: taskId, error: "Verificação falhou (`\(verify)`):\n\(verifyRes.output)")
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                guard let self, let i = self.missionIndex(missionId),
                      let j = self.missions[i].tasks.firstIndex(where: { $0.id == taskId })
                else { return }
                self.missions[i].tasks[j].status = .merging
                self.missions[i].tasks[j].lastOutput = L10n.t(
                    "Integrando alterações em \(mission.baseBranch)…",
                    "Merging into \(mission.baseBranch)…"
                )
                self.saveMissions()
            }

            let mergeOutcome = WorktreeManager.commitAndMerge(
                repoPath: mission.projectPath,
                worktreePath: wt.worktreePath,
                branchName: wt.branchName,
                baseBranch: mission.baseBranch,
                taskId: task.id,
                taskTitle: task.title
            )
            WorktreeManager.removeWorktree(
                repoPath: mission.projectPath,
                worktreePath: wt.worktreePath,
                branchName: wt.branchName,
                deleteBranch: true
            )

            DispatchQueue.main.async {
                guard let self, let i = self.missionIndex(missionId),
                      let j = self.missions[i].tasks.firstIndex(where: { $0.id == taskId })
                else { return }
                self.missions[i].tasks[j].worktreePath = nil

                guard self.missions[i].status == .running else { return }

                switch mergeOutcome {
                case .merged(let hadChanges):
                    self.missions[i].tasks[j].status = .done
                    self.missions[i].tasks[j].finishedAt = Date()
                    self.missions[i].tasks[j].lastOutput = hadChanges
                        ? L10n.t("Integrada em \(mission.baseBranch)", "Merged into \(mission.baseBranch)")
                        : L10n.t("Concluída", "Completed")
                    self.appendLog(missionId, "[\(taskId)] Concluída" + (hadChanges ? " e integrada em \(mission.baseBranch)." : "."))
                    self.saveMissions()
                    self.scheduleNextTasks(for: missionId)

                case .conflict(let msg):
                    self.handleTaskFailure(
                        missionId: missionId,
                        taskId: taskId,
                        error: "Conflito de merge com `\(mission.baseBranch)` — tentando novamente na branch atualizada:\n\(String(msg.prefix(350)))"
                    )

                case .error(let msg):
                    self.handleTaskFailure(missionId: missionId, taskId: taskId, error: msg)
                }
            }
        }
    }

    private func handleTaskFailure(missionId: UUID, taskId: String, error: String) {
        guard let i = missionIndex(missionId),
              let j = missions[i].tasks.firstIndex(where: { $0.id == taskId })
        else { return }

        missions[i].tasks[j].worktreePath = nil
        missions[i].tasks[j].lastError = error

        if missions[i].status != .running {
            missions[i].tasks[j].status = .pending
            saveMissions()
            return
        }

        let attempts = missions[i].tasks[j].attempts
        let maxAttempts = missions[i].tasks[j].maxAttempts
        if attempts < maxAttempts {
            missions[i].tasks[j].status = .pending
            appendLog(missionId, "[\(taskId)] Falha na tentativa \(attempts)/\(maxAttempts) — reencaminhando: \(String(error.prefix(160)))")
        } else {
            missions[i].tasks[j].status = .failed
            missions[i].tasks[j].finishedAt = Date()
            appendLog(missionId, "[\(taskId)] FALHOU definitivamente: \(String(error.prefix(200)))")
        }
        saveMissions()
        scheduleNextTasks(for: missionId)
    }

    // MARK: - Helpers

    private static func resolveClaudePath() -> String? {
        if let envBin = ProcessInfo.processInfo.environment["SPYWATER_CLAUDE_BIN"],
           !envBin.isEmpty,
           FileManager.default.isExecutableFile(atPath: envBin) {
            return envBin
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    nonisolated private static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:\(basePath)"
        return env
    }

    nonisolated private static func isAuthFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("failed to authenticate")
            || lower.contains("claude auth login")
            || lower.contains("token expired")
    }

    nonisolated private static func runShellVerify(command: String, in dir: String) -> (ok: Bool, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: dir, isDirectory: true)
        proc.environment = buildEnvironment()
        proc.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let combined = [err, out].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return (proc.terminationStatus == 0, String(combined.prefix(600)))
    }

    private static func parsePlannerOutput(_ raw: String) -> (title: String?, tasks: [MissionTask])? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var outer: [String: Any]?
        if let data = trimmed.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            outer = obj
        } else {
            for line in trimmed.split(separator: "\n").reversed() {
                if let data = line.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    outer = obj
                    break
                }
            }
        }
        guard let outer else { return nil }

        var payload: [String: Any]?
        if let structured = outer.dict("structured_output") {
            payload = structured
        } else if let resStr = outer.nonEmptyStr("result") {
            let clean = stripMarkdownCodeFences(resStr)
            if let data = clean.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                payload = obj
            }
        } else if outer["tasks"] != nil {
            payload = outer
        }

        guard let payload, let rawTasks = payload.arr("tasks"), !rawTasks.isEmpty else {
            return nil
        }

        var seenIds = Set<String>()
        var parsedTasks: [MissionTask] = []

        for (idx, item) in rawTasks.enumerated() {
            let rawId = item.nonEmptyStr("id") ?? "T\(idx + 1)"
            let id = seenIds.contains(rawId) ? "\(rawId)_\(idx + 1)" : rawId
            seenIds.insert(id)

            let title = item.nonEmptyStr("title") ?? "Tarefa \(id)"
            let prompt = item.nonEmptyStr("prompt") ?? title
            let deps = (item["depends_on"] as? [String]) ?? []
            let verify = item.nonEmptyStr("verify_command")

            parsedTasks.append(MissionTask(
                id: id,
                title: title,
                prompt: prompt,
                dependsOn: deps,
                verifyCommand: verify
            ))
        }

        let validIds = Set(parsedTasks.map(\.id))
        for i in parsedTasks.indices {
            let ownId = parsedTasks[i].id
            parsedTasks[i].dependsOn = parsedTasks[i].dependsOn.filter { $0 != ownId && validIds.contains($0) }
        }

        return (payload.nonEmptyStr("title"), parsedTasks)
    }

    private static func stripMarkdownCodeFences(_ s: String) -> String {
        var text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let firstNL = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNL)...])
            }
            if text.hasSuffix("```") {
                text = String(text.dropLast(3))
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseStreamEvent(_ lineData: Data) -> (sessionId: String?, snippet: String?, errorText: String?)? {
        guard let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] else {
            return nil
        }
        let sid = obj.nonEmptyStr("session_id")
        let type = obj.str("type")

        if type == "assistant", let msg = obj.dict("message"), let content = msg.arr("content") {
            for block in content.reversed() {
                if block.str("type") == "tool_use", let name = block.nonEmptyStr("name") {
                    let input = block.dict("input") ?? [:]
                    return (sid, SessionStore.describeTool(name, input: input), nil)
                }
                if block.str("type") == "text", let txt = block.nonEmptyStr("text") {
                    let line = txt.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? txt
                    let trunc = line.count > 80 ? String(line.prefix(80)) + "…" : line
                    return (sid, trunc, nil)
                }
            }
        }

        if type == "result" {
            let isErr = obj.bool("is_error") ?? false
            let res = obj.nonEmptyStr("result")
            if isErr {
                return (sid, nil, res)
            }
            if let res {
                let line = res.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? res
                let trunc = line.count > 80 ? String(line.prefix(80)) + "…" : line
                return (sid, trunc, nil)
            }
        }

        return sid != nil ? (sid, nil, nil) : nil
    }
}
