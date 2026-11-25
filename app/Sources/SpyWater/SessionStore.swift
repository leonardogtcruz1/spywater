import AppKit
import Darwin
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [String: Session] = [:]
    @Published var pending: [PendingRequest] = []
    @Published var rateLimits: RateLimits?
    @Published var localUsage: LocalPlanUsage?
    @Published var statuslineInstalled: Bool = false
    @Published var agyHooksInstalled: Bool = false
    @Published var recent: [RecentSession] = []
    @Published var serverError: String?
    @Published var now: Date = Date()

    let server = HookServer()
    let notifier = Notifier()
    private let usageTracker = UsageTracker()
    private let isDemoMode = ProcessInfo.processInfo.environment["SPYWATER_DEMO"] == "1"

    var onOpenMainWindow: (() -> Void)?

    private var tickTimer: Timer?
    private var livenessTimer: Timer?
    private var transcriptTimer: Timer?
    private var recentTimer: Timer?
    private var usageTimer: Timer?
    private var agySyncTimer: Timer?

    private var claudeRecent: [RecentSession] = []
    private var agyRecent: [RecentSession] = []
    private var agyLastHookAt: [String: Date] = [:]

    init() {
        ensureDefaults()
        loadCachedRateLimits()
        setupCallbacks()
        notifier.setup()
        server.start()
        startTimers()
        refreshRecent()
        refreshLocalUsage()
        syncAntigravitySummaries()
    }

    private func ensureDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "holdSeconds") == nil {
            defaults.set(120, forKey: "holdSeconds")
        }
        if defaults.object(forKey: "terminalApp") == nil {
            defaults.set("terminal", forKey: "terminalApp")
        }
        if defaults.object(forKey: "autolaunchInitialized") == nil {
            defaults.set(true, forKey: "autolaunchInitialized")
            defaults.set(true, forKey: "autolaunch")
            setAutolaunchFile(enabled: true)
        }
    }

    func setAutolaunchFile(enabled: Bool) {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".spywater", isDirectory: true)
        let file = dir.appendingPathComponent("autolaunch")
        if enabled {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: file.path, contents: Data())
        } else {
            try? fm.removeItem(at: file)
        }
    }

    var holdSeconds: Int {
        if UserDefaults.standard.object(forKey: "holdSeconds") == nil {
            return 120
        }
        return UserDefaults.standard.integer(forKey: "holdSeconds")
    }

    var terminalApp: String {
        UserDefaults.standard.string(forKey: "terminalApp") ?? "terminal"
    }

    private func setupCallbacks() {
        server.onError = { [weak self] err in
            self?.serverError = err
        }
        server.onEvent = { [weak self] payload, headers in
            self?.handleEvent(payload, headers: headers)
        }
        server.onBlockingHook = { [weak self] payload, headers, responder in
            self?.handleBlockingHook(payload, headers: headers, responder: responder)
        }
        server.onAgyEvent = { [weak self] event, payload, headers in
            self?.handleAgyEvent(event, payload: payload, headers: headers)
        }
        server.onAgyPreToolUse = { [weak self] payload, headers, responder in
            self?.handleAgyPreToolUse(payload, headers: headers, responder: responder)
        }
        server.onStatusline = { [weak self] payload in
            self?.handleStatusline(payload)
        }
        server.onGetPending = { [weak self] reply in
            guard let self else { reply([]); return }
            let items: [[String: Any]] = self.pending.map { req in
                [
                    "id": req.id.uuidString,
                    "sessionId": req.sessionId,
                    "source": req.source.rawValue,
                    "kind": req.kind.rawValue,
                    "toolName": req.toolName
                ]
            }
            reply(items)
        }
        server.onGetSessions = { [weak self] reply in
            guard let self else { reply([]); return }
            let items: [[String: Any]] = self.sessions.values.map { s in
                [
                    "id": s.id,
                    "source": s.source.rawValue,
                    "state": self.effectiveState(for: s).rawValue,
                    "cwd": s.cwd,
                    "model": s.model ?? "",
                    "activity": s.activity,
                    "pendingCount": self.pending(for: s.id).count
                ]
            }
            reply(items)
        }
        server.onDebugDecide = { [weak self] body, reply in
            guard let self else { reply(false); return }
            guard let idStr = body.nonEmptyStr("id"),
                  let uuid = UUID(uuidString: idStr),
                  let req = self.pending.first(where: { $0.id == uuid }),
                  let action = body.nonEmptyStr("action")
            else {
                reply(false)
                return
            }

            switch action {
            case "allow":
                self.allow(req)
                reply(true)
            case "deny":
                self.deny(req, message: body.nonEmptyStr("message"))
                reply(true)
            case "release":
                self.release(req)
                reply(true)
            case "answer":
                let rawAnswers = body.dict("answers") ?? [:]
                var answers: [String: String] = [:]
                for (k, v) in rawAnswers {
                    if let s = v as? String {
                        answers[k] = s
                    }
                }
                self.answer(req, answers: answers)
                reply(true)
            default:
                reply(false)
            }
        }

        notifier.onPermissionAction = { [weak self] pendingId, allowAction in
            guard let self, let req = self.pending.first(where: { $0.id == pendingId }) else { return }
            if allowAction {
                self.allow(req)
            } else {
                self.deny(req)
            }
        }
        notifier.onOpenMainWindow = { [weak self] in
            self?.onOpenMainWindow?()
        }
    }

    private func startTimers() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onTick()
            }
        }
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkLiveness()
            }
        }
        agySyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncAntigravitySummaries()
            }
        }
        transcriptTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllLiveTranscripts()
            }
        }
        recentTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshRecent()
            }
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLocalUsage()
            }
        }
    }

    private func onTick() {
        let current = Date()
        now = current

        let limit = holdSeconds
        if limit > 0 {
            let expired = pending.filter { current.timeIntervalSince($0.createdAt) > Double(limit) }
            for req in expired {
                release(req)
            }
        }
    }

    func effectiveState(for session: Session) -> SessionState {
        if session.state == .ended { return .ended }
        if pending.contains(where: { $0.sessionId == session.id }) {
            return .needsYou
        }
        return session.state
    }

    func pending(for sessionId: String) -> [PendingRequest] {
        pending.filter { $0.sessionId == sessionId }
    }

    var sortedSessions: [Session] {
        let live = sessions.values.filter { effectiveState(for: $0) != .ended }
        return live.sorted { a, b in
            let sA = effectiveState(for: a)
            let sB = effectiveState(for: b)
            if sA.priority != sB.priority {
                return sA.priority < sB.priority
            }
            if sA.priority == 0 {
                let dA = oldestPendingDate(for: a.id) ?? a.lastEventAt
                let dB = oldestPendingDate(for: b.id) ?? b.lastEventAt
                if dA != dB { return dA < dB }
            }
            return a.lastEventAt > b.lastEventAt
        }
    }

    var attentionCount: Int {
        sessions.values.filter {
            let st = effectiveState(for: $0)
            return st != .ended && st.priority <= 2
        }.count
    }

    var topPendingId: UUID? {
        for s in sortedSessions {
            if let first = pending(for: s.id).first {
                return first.id
            }
        }
        return nil
    }

    private func oldestPendingDate(for sessionId: String) -> Date? {
        pending.filter { $0.sessionId == sessionId }.map(\.createdAt).min()
    }

    // MARK: - Claude Code Events

    @discardableResult
    private func upsertSession(from payload: [String: Any], headers: [String: String] = [:]) -> String? {
        guard let id = payload.nonEmptyStr("session_id") else { return nil }
        let timestamp = Date()

        let payloadCwd = payload.nonEmptyStr("cwd")
            ?? payload.dict("workspace")?.nonEmptyStr("current_dir")

        var session = sessions[id] ?? Session(
            id: id,
            source: .claudeCode,
            cwd: payloadCwd ?? NSHomeDirectory(),
            projectName: Self.projectName(from: payloadCwd ?? NSHomeDirectory()),
            state: .idle,
            activity: L10n.t("Sessão ativa", "Active session"),
            startedAt: timestamp,
            lastEventAt: timestamp
        )

        session.source = .claudeCode
        if let cwd = payloadCwd {
            session.cwd = cwd
            session.projectName = Self.projectName(from: cwd)
        }
        if let tp = payload.nonEmptyStr("transcript_path") {
            session.transcriptPath = tp
        }
        if let ppidStr = headers["x-spy-ppid"], let pid = Int32(ppidStr), pid > 0 {
            if Self.isClaudeProcess(pid) {
                session.pid = pid
            } else if session.pid == nil {
                session.pid = nil
            }
        }
        if let term = headers["x-spy-term"], !term.isEmpty {
            session.termProgram = term
        }
        if let pm = payload.nonEmptyStr("permission_mode") {
            session.permissionMode = pm
        }
        if let eff = payload.dict("effort")?.nonEmptyStr("level") {
            session.effort = eff
        }
        session.lastEventAt = timestamp

        sessions[id] = session
        rebuildMergedRecent()
        return id
    }

    private func handleEvent(_ payload: [String: Any], headers: [String: String]) {
        guard let event = payload.nonEmptyStr("hook_event_name") else { return }
        let toolName = payload.nonEmptyStr("tool_name") ?? ""
        let toolInput = payload.dict("tool_input") ?? [:]

        if event == "PreToolUse" && toolName == "AskUserQuestion" {
            return
        }

        guard let id = upsertSession(from: payload, headers: headers) else { return }

        if event == "SubagentStart" {
            sessions[id]?.subagentsRunning += 1
            return
        }
        if event == "SubagentStop" {
            sessions[id]?.subagentsRunning = max(0, (sessions[id]?.subagentsRunning ?? 1) - 1)
            return
        }

        if payload.nonEmptyStr("agent_id") != nil {
            if event == "PreToolUse" {
                let agentType = payload.nonEmptyStr("agent_type") ?? "subagente"
                sessions[id]?.activity = "[\(agentType)] \(Self.describeTool(toolName, input: toolInput))"
            }
            return
        }

        switch event {
        case "SessionStart":
            sessions[id]?.state = .idle
            sessions[id]?.activity = L10n.t("Sessão iniciada", "Session started")
            if let m = payload.nonEmptyStr("model"), sessions[id]?.hasStatuslineModel == false {
                sessions[id]?.model = formatModelName(m)
            }
            if let title = payload.nonEmptyStr("session_title") {
                sessions[id]?.title = title
            }
            refreshTranscript(for: id)

        case "UserPromptSubmit":
            sessions[id]?.state = .working
            if let prompt = payload.nonEmptyStr("prompt") {
                sessions[id]?.lastPrompt = prompt
            }
            sessions[id]?.activity = L10n.t("Pensando…", "Thinking…")
            sessions[id]?.hasPermissionPromptInTerminal = false

        case "PreToolUse":
            sessions[id]?.state = .working
            sessions[id]?.activity = Self.describeTool(toolName, input: toolInput)

        case "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            sessions[id]?.state = .working
            sessions[id]?.activity = L10n.t("Pensando…", "Thinking…")
            let stale = pending.filter { $0.sessionId == id && $0.kind == .permission && $0.toolName == toolName }
            for req in stale {
                release(req)
            }

        case "Notification":
            let ntype = payload.nonEmptyStr("notification_type") ?? payload.nonEmptyStr("type") ?? ""
            let msg = payload.nonEmptyStr("message") ?? L10n.t("Aguardando no terminal", "Waiting in terminal")
            if ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"].contains(ntype) {
                sessions[id]?.hasPermissionPromptInTerminal = true
                if !pending.contains(where: { $0.sessionId == id }) {
                    sessions[id]?.state = .waitingTerminal
                    sessions[id]?.activity = msg
                }
            } else if ntype == "idle_prompt" {
                if sessions[id]?.state != .ended {
                    sessions[id]?.state = .yourTurn
                }
            }

        case "Stop":
            let bgTasks = payload.anyArr("background_tasks") ?? []
            if !bgTasks.isEmpty {
                sessions[id]?.state = .working
                sessions[id]?.activity = L10n.t("Aguardando tarefas em segundo plano", "Waiting for background tasks")
            } else {
                sessions[id]?.state = .yourTurn
                sessions[id]?.activity = L10n.t("Aguardando sua instrução", "Waiting for your input")
                if let s = sessions[id] {
                    notifier.notifyYourTurn(session: s)
                }
            }
            if let lastMsg = payload.nonEmptyStr("last_assistant_message") {
                sessions[id]?.lastAssistantMessage = lastMsg
            }
            refreshTranscript(for: id)
            refreshLocalUsage()

        case "StopFailure":
            sessions[id]?.state = .error
            sessions[id]?.activity = payload.nonEmptyStr("error")
                ?? payload.nonEmptyStr("message")
                ?? L10n.t("Erro na resposta", "Response error")

        case "SessionEnd":
            sessions[id]?.state = .ended
            sessions[id]?.activity = L10n.t("Sessão encerrada", "Session ended")
            let orphans = pending.filter { $0.sessionId == id }
            for req in orphans {
                release(req)
            }
            refreshRecent()
            refreshLocalUsage()

        default:
            break
        }
    }

    private func handleBlockingHook(_ payload: [String: Any], headers: [String: String], responder: HookResponder) {
        guard let id = upsertSession(from: payload, headers: headers) else {
            responder.respond(body: nil)
            return
        }

        let event = payload.nonEmptyStr("hook_event_name") ?? "PermissionRequest"
        let toolName = payload.nonEmptyStr("tool_name") ?? "Tool"
        let toolInput = payload.dict("tool_input") ?? [:]
        let suggestions = payload.arr("permission_suggestions") ?? []

        let kind: PendingKind
        if toolName == "AskUserQuestion" {
            kind = .question
        } else if toolName == "ExitPlanMode" {
            kind = .plan
        } else {
            kind = .permission
        }

        let req = PendingRequest(
            id: UUID(),
            sessionId: id,
            source: .claudeCode,
            kind: kind,
            event: event,
            toolName: toolName,
            toolInput: toolInput,
            suggestions: suggestions,
            createdAt: Date(),
            responder: responder
        )

        let summary = Self.describeTool(toolName, input: toolInput)
        if sessions[id]?.state != .ended {
            sessions[id]?.activity = summary
        }

        pending.append(req)

        let reqId = req.id
        responder.setOnClientGone { [weak self] in
            self?.removePending(id: reqId)
        }

        let projectName = sessions[id]?.projectName ?? "Claude"
        notifier.notifyPending(req, projectName: projectName, summary: summary)
    }

    // MARK: - Antigravity Events

    @discardableResult
    private func upsertAgySession(from payload: [String: Any], headers: [String: String] = [:]) -> String? {
        guard let id = payload.nonEmptyStr("conversationId") else { return nil }
        let timestamp = Date()
        let wsPaths = payload["workspacePaths"] as? [String]
        let firstWorkspace = wsPaths?.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let cwd = firstWorkspace ?? sessions[id]?.cwd ?? NSHomeDirectory()

        var session = sessions[id] ?? Session(
            id: id,
            source: .antigravity,
            cwd: cwd,
            projectName: Self.projectName(from: cwd),
            state: .working,
            activity: L10n.t("Conversa ativa", "Active conversation"),
            startedAt: timestamp,
            lastEventAt: timestamp
        )

        session.source = .antigravity
        if let firstWorkspace {
            session.cwd = firstWorkspace
            session.projectName = Self.projectName(from: firstWorkspace)
        }
        if let rawTP = payload.nonEmptyStr("transcriptPath") {
            session.transcriptPath = NSString(string: rawTP).expandingTildeInPath
        }
        if let m = payload.nonEmptyStr("modelName") {
            session.model = formatModelName(m)
        }
        if let lastInput = payload.nonEmptyStr("lastUserInput") {
            session.lastPrompt = lastInput
        }
        session.lastEventAt = timestamp
        agyLastHookAt[id] = timestamp

        sessions[id] = session
        rebuildMergedRecent()
        return id
    }

    private func handleAgyEvent(_ event: String, payload: [String: Any], headers: [String: String]) {
        guard let id = upsertAgySession(from: payload, headers: headers) else { return }

        switch event {
        case "SessionStart":
            sessions[id]?.state = .idle
            sessions[id]?.activity = L10n.t("Conversa iniciada", "Conversation started")
            refreshAgyTranscript(for: id)

        case "PreInvocation":
            sessions[id]?.state = .working
            sessions[id]?.activity = L10n.t("Pensando…", "Thinking…")

        case "PostInvocation":
            refreshAgyTranscript(for: id)

        case "PostToolUse":
            let toolCall = payload.dict("toolCall") ?? [:]
            let toolName = toolCall.nonEmptyStr("name") ?? ""
            let err = payload.nonEmptyStr("error")
            sessions[id]?.state = .working
            if let err {
                let fallbackTool = L10n.t("ferramenta", "tool")
                sessions[id]?.activity = L10n.t("Erro em \(toolName.isEmpty ? fallbackTool : toolName): \(err)", "Error in \(toolName.isEmpty ? fallbackTool : toolName): \(err)")
            } else {
                sessions[id]?.activity = L10n.t("Pensando…", "Thinking…")
            }
            let stale = pending.filter {
                $0.sessionId == id && $0.source == .antigravity && $0.kind == .permission && $0.toolName == toolName
            }
            for req in stale {
                release(req)
            }

        case "Stop":
            let fullyIdle = payload.bool("fullyIdle") ?? true
            let reason = payload.nonEmptyStr("terminationReason") ?? ""
            let err = payload.nonEmptyStr("error")
            if !fullyIdle {
                sessions[id]?.state = .working
                sessions[id]?.activity = L10n.t("Aguardando tarefas em segundo plano", "Waiting for background tasks")
            } else if reason == "error" || err != nil {
                sessions[id]?.state = .error
                sessions[id]?.activity = err ?? L10n.t("Erro na execução", "Execution error")
            } else {
                sessions[id]?.state = .yourTurn
                sessions[id]?.activity = L10n.t("Aguardando sua instrução", "Waiting for your input")
                if let s = sessions[id] {
                    notifier.notifyYourTurn(session: s)
                }
            }
            refreshAgyTranscript(for: id)
            refreshLocalUsage()

        default:
            break
        }
    }

    private func handleAgyPreToolUse(_ payload: [String: Any], headers: [String: String], responder: HookResponder) {
        guard let id = upsertAgySession(from: payload, headers: headers) else {
            responder.respond(body: jsonData(["decision": "allow"]))
            return
        }

        let toolCall = payload.dict("toolCall") ?? [:]
        let toolName = toolCall.nonEmptyStr("name") ?? "Tool"
        let toolInput = toolCall.dict("args") ?? [:]
        let summary = Self.describeTool(toolName, input: toolInput)

        sessions[id]?.state = .working
        sessions[id]?.activity = summary

        let shouldGate: PendingKind?
        if toolName == "ask_question" {
            shouldGate = .question
        } else if toolName == "ask_permission" {
            shouldGate = .permission
        } else if toolName == "run_command" && UserDefaults.standard.bool(forKey: "agyInterceptCommands") {
            shouldGate = .permission
        } else {
            shouldGate = nil
        }

        guard let kind = shouldGate else {
            responder.respond(body: jsonData(["decision": "allow"]))
            return
        }

        let req = PendingRequest(
            id: UUID(),
            sessionId: id,
            source: .antigravity,
            kind: kind,
            event: "PreToolUse",
            toolName: toolName,
            toolInput: toolInput,
            suggestions: [],
            createdAt: Date(),
            responder: responder
        )

        pending.append(req)
        let reqId = req.id
        responder.setOnClientGone { [weak self] in
            self?.removePending(id: reqId)
        }

        let projectName = sessions[id]?.projectName ?? "Antigravity"
        notifier.notifyPending(req, projectName: projectName, summary: summary)
    }

    // MARK: - Statusline

    private func handleStatusline(_ payload: [String: Any]) {
        if let sid = payload.nonEmptyStr("session_id") {
            let timestamp = Date()
            if sessions[sid] == nil {
                let cwd = payload.dict("workspace")?.nonEmptyStr("current_dir")
                    ?? payload.nonEmptyStr("cwd")
                    ?? NSHomeDirectory()
                sessions[sid] = Session(
                    id: sid,
                    source: .claudeCode,
                    cwd: cwd,
                    projectName: Self.projectName(from: cwd),
                    state: .idle,
                    activity: L10n.t("Sessão ativa", "Active session"),
                    startedAt: timestamp,
                    lastEventAt: timestamp
                )
                rebuildMergedRecent()
            }

            if let cwd = payload.dict("workspace")?.nonEmptyStr("current_dir") ?? payload.nonEmptyStr("cwd") {
                sessions[sid]?.cwd = cwd
                sessions[sid]?.projectName = Self.projectName(from: cwd)
            }
            if let tp = payload.nonEmptyStr("transcript_path") {
                sessions[sid]?.transcriptPath = tp
            }
            if let sname = payload.nonEmptyStr("session_name") {
                sessions[sid]?.title = sname
            }
            if let m = payload.dict("model"),
               let display = m.nonEmptyStr("display_name") ?? m.nonEmptyStr("id") {
                sessions[sid]?.model = display
                sessions[sid]?.hasStatuslineModel = true
            }
            if let eff = payload.dict("effort")?.nonEmptyStr("level") {
                sessions[sid]?.effort = eff
            }
            if let cw = payload.dict("context_window") {
                if let pct = cw.double("used_percentage") {
                    sessions[sid]?.contextPct = pct
                }
                if let win = cw.int("context_window_size") {
                    sessions[sid]?.contextWindow = win
                }
                if let tot = cw.int("total_input_tokens") {
                    sessions[sid]?.contextTokens = tot
                }
            }
            if let cost = payload.dict("cost")?.double("total_cost_usd") {
                sessions[sid]?.costUSD = cost
            }
        }

        if let rl = payload.dict("rate_limits") {
            let five = rl.dict("five_hour")
            let seven = rl.dict("seven_day")
            let spend = rl.dict("spend_limit")
            if five != nil || seven != nil || spend != nil {
                let fivePct = five?.double("used_percentage")
                let fiveReset = five?.double("resets_at").map { Date(timeIntervalSince1970: $0) }
                let sevenPct = seven?.double("used_percentage")
                let sevenReset = seven?.double("resets_at").map { Date(timeIntervalSince1970: $0) }
                let spendPct = spend?.double("used_percentage")
                let spendReset = spend?.double("resets_at").map { Date(timeIntervalSince1970: $0) }
                let spendUsed = spend?.double("used_usd")
                let spendLimit = spend?.double("limit_usd")
                let updated = RateLimits(
                    fiveHourPct: fivePct,
                    fiveHourReset: fiveReset,
                    sevenDayPct: sevenPct,
                    sevenDayReset: sevenReset,
                    spendLimitPct: spendPct,
                    spendLimitReset: spendReset,
                    spendUsedUSD: spendUsed,
                    spendLimitUSD: spendLimit,
                    updatedAt: Date()
                )
                rateLimits = updated
                saveCachedRateLimits(updated)
            }
        }
    }

    // MARK: - Decisions

    func allow(_ req: PendingRequest) {
        if req.source == .antigravity {
            req.responder.respond(body: jsonData([
                "decision": "auto_approve",
                "reason": "Aprovado pelo usuário no SpyWater"
            ]))
            removePending(id: req.id)
            return
        }

        let bodyObj: [String: Any]
        if req.event == "PreToolUse" {
            var hookOut: [String: Any] = [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow"
            ]
            if req.kind == .plan {
                hookOut["updatedInput"] = req.toolInput
            }
            bodyObj = ["hookSpecificOutput": hookOut]
        } else {
            var decision: [String: Any] = ["behavior": "allow"]
            if req.kind == .plan {
                decision["updatedInput"] = req.toolInput
            }
            bodyObj = [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": decision
                ]
            ]
        }
        req.responder.respond(body: jsonData(bodyObj))
        removePending(id: req.id)
    }

    func allowAlways(_ req: PendingRequest, suggestion: [String: Any]) {
        if req.source == .antigravity {
            allow(req)
            return
        }
        let decision: [String: Any] = {
            var d: [String: Any] = [
                "behavior": "allow",
                "updatedPermissions": [suggestion]
            ]
            if req.kind == .plan {
                d["updatedInput"] = req.toolInput
            }
            return d
        }()
        let bodyObj: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision
            ]
        ]
        req.responder.respond(body: jsonData(bodyObj))
        removePending(id: req.id)
    }

    func deny(_ req: PendingRequest, message: String? = nil) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = trimmed.isEmpty ? "Negado pelo usuário no SpyWater" : trimmed

        if req.source == .antigravity {
            req.responder.respond(body: jsonData([
                "decision": "deny",
                "reason": reason
            ]))
            removePending(id: req.id)
            return
        }

        let bodyObj: [String: Any]
        if req.event == "PreToolUse" {
            bodyObj = [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason
                ]
            ]
        } else {
            bodyObj = [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "deny",
                        "message": reason,
                        "interrupt": false
                    ]
                ]
            ]
        }
        req.responder.respond(body: jsonData(bodyObj))
        removePending(id: req.id)
    }

    func answer(_ req: PendingRequest, answers: [String: String]) {
        if req.source == .antigravity {
            let summaryLines = answers
                .sorted { $0.key < $1.key }
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
            let reason = "Resposta do usuário (via SpyWater):\n\(summaryLines)"
            req.responder.respond(body: jsonData([
                "decision": "deny",
                "reason": reason
            ]))
            removePending(id: req.id)
            return
        }

        let originalQuestions = req.toolInput.anyArr("questions") ?? []
        let updatedInput: [String: Any] = [
            "questions": originalQuestions,
            "answers": answers
        ]

        let bodyObj: [String: Any]
        if req.event == "PreToolUse" {
            bodyObj = [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                    "updatedInput": updatedInput
                ]
            ]
        } else {
            bodyObj = [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "allow",
                        "updatedInput": updatedInput
                    ]
                ]
            ]
        }
        req.responder.respond(body: jsonData(bodyObj))
        removePending(id: req.id)
    }

    func release(_ req: PendingRequest) {
        if req.source == .antigravity {
            req.responder.respond(body: jsonData(["decision": "allow"]))
        } else {
            req.responder.respond(body: nil)
        }
        removePending(id: req.id)
    }

    private func removePending(id: UUID) {
        pending.removeAll { $0.id == id }
        notifier.removePendingNotification(id: id)
    }

    // MARK: - Background Refresh

    private func checkLiveness() {
        for (id, var session) in sessions {
            guard session.source == .claudeCode, session.state != .ended, let pid = session.pid else { continue }
            if !Self.isClaudeProcess(pid) {
                if kill(pid, 0) != 0 && errno == ESRCH {
                    session.state = .ended
                    session.activity = "Processo encerrado"
                    sessions[id] = session
                    let orphans = pending.filter { $0.sessionId == id }
                    for req in orphans {
                        release(req)
                    }
                } else {
                    session.pid = nil
                    sessions[id] = session
                }
            }
        }
    }

    private func refreshAllLiveTranscripts() {
        for (id, session) in sessions where effectiveState(for: session) != .ended {
            if session.source == .antigravity {
                refreshAgyTranscript(for: id)
            } else {
                refreshTranscript(for: id)
            }
        }
    }

    func refreshTranscript(for sessionId: String) {
        guard let path = sessions[sessionId]?.transcriptPath, !path.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let snap = TranscriptReader.readTail(path: path) else { return }
            DispatchQueue.main.async {
                guard let self, var s = self.sessions[sessionId] else { return }
                if s.title == nil, let t = snap.title { s.title = t }
                if s.lastPrompt == nil, let lp = snap.lastPrompt { s.lastPrompt = lp }
                if !s.hasStatuslineModel, s.model == nil, let m = snap.model { s.model = formatModelName(m) }
                if s.contextTokens == nil, let tok = snap.contextTokens { s.contextTokens = tok }
                if s.contextWindow == nil, let win = snap.contextWindow { s.contextWindow = win }
                if s.contextPct == nil, let tok = s.contextTokens, let win = s.contextWindow, win > 0 {
                    s.contextPct = (Double(tok) / Double(win)) * 100.0
                }
                if s.costUSD == nil, let c = snap.costUSD { s.costUSD = c }
                self.sessions[sessionId] = s
            }
        }
    }

    func refreshAgyTranscript(for sessionId: String) {
        guard let path = sessions[sessionId]?.transcriptPath, !path.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let snap = AntigravityScanner.readTranscriptTail(path: path) else { return }
            DispatchQueue.main.async {
                guard let self, var s = self.sessions[sessionId] else { return }
                if let m = snap.model { s.model = m }
                if s.lastPrompt == nil, let lp = snap.lastPrompt { s.lastPrompt = lp }
                if let tok = snap.contextTokens { s.contextTokens = tok }
                if let win = snap.contextWindow { s.contextWindow = win }
                if let tok = s.contextTokens, let win = s.contextWindow, win > 0 {
                    s.contextPct = (Double(tok) / Double(win)) * 100.0
                }
                let hookAge = Date().timeIntervalSince(self.agyLastHookAt[sessionId] ?? .distantPast)
                if hookAge > 4.0, s.state == .working, let act = snap.lastActivity {
                    s.activity = act
                }
                self.sessions[sessionId] = s
            }
        }
    }

    func syncAntigravitySummaries() {
        if isDemoMode { return }
        AntigravityScanner.scanSummaries { [weak self] summaries in
            guard let self else { return }
            let current = Date()
            var nextAgyRecent: [RecentSession] = []

            for summary in summaries {
                if summary.isRunning {
                    var session = self.sessions[summary.id] ?? Session(
                        id: summary.id,
                        source: .antigravity,
                        cwd: summary.cwd,
                        projectName: summary.projectName,
                        title: summary.title.isEmpty ? nil : summary.title,
                        state: .working,
                        activity: L10n.t("Trabalhando no Antigravity…", "Working in Antigravity…"),
                        transcriptPath: summary.transcriptPath,
                        startedAt: summary.lastModifiedAt,
                        lastEventAt: summary.lastModifiedAt,
                        subagentsRunning: summary.runningSubagents
                    )
                    session.source = .antigravity
                    session.cwd = summary.cwd
                    session.projectName = summary.projectName
                    if !summary.title.isEmpty { session.title = summary.title }
                    session.subagentsRunning = summary.runningSubagents
                    session.transcriptPath = summary.transcriptPath

                    let hookAge = current.timeIntervalSince(self.agyLastHookAt[summary.id] ?? .distantPast)
                    let hasPending = self.pending.contains(where: { $0.sessionId == summary.id })
                    if hookAge > 5.0 && !hasPending {
                        session.state = .working
                        if summary.lastModifiedAt > session.lastEventAt {
                            session.lastEventAt = summary.lastModifiedAt
                        }
                    }

                    self.sessions[summary.id] = session
                    self.refreshAgyTranscript(for: summary.id)
                } else {
                    if var existing = self.sessions[summary.id], existing.source == .antigravity {
                        let hasPending = self.pending.contains(where: { $0.sessionId == summary.id })
                        if !hasPending && current.timeIntervalSince(existing.lastEventAt) > 15 {
                            if current.timeIntervalSince(summary.lastModifiedAt) < 15 * 60 {
                                if existing.state == .working {
                                    existing.state = .yourTurn
                                    existing.activity = "Aguardando sua instrução"
                                }
                            } else if current.timeIntervalSince(summary.lastModifiedAt) >= 20 * 60 {
                                existing.state = .ended
                                existing.activity = "Conversa encerrada"
                            }
                            self.sessions[summary.id] = existing
                        }
                    }

                    let cachedModel = self.sessions[summary.id]?.model
                    let cachedPrompt = self.sessions[summary.id]?.lastPrompt
                    nextAgyRecent.append(RecentSession(
                        id: summary.id,
                        source: .antigravity,
                        cwd: summary.cwd,
                        projectName: summary.projectName,
                        title: summary.title.isEmpty ? nil : summary.title,
                        lastPrompt: cachedPrompt,
                        model: cachedModel,
                        transcriptPath: summary.transcriptPath,
                        lastActivityAt: summary.lastModifiedAt,
                        costUSD: nil
                    ))
                }
            }

            self.agyRecent = nextAgyRecent
            self.rebuildMergedRecent()
        }
    }

    func refreshRecent() {
        if isDemoMode {
            let now = Date()
            claudeRecent = [
                RecentSession(
                    id: "demo-recent-1",
                    source: .claudeCode,
                    cwd: "/Users/leonardocruz/Projects/payments-worker",
                    projectName: "payments-worker",
                    title: "Stripe idempotency keys",
                    lastPrompt: "Add idempotency key persistence for retryable charges",
                    model: "Sonnet 4.6",
                    transcriptPath: "",
                    lastActivityAt: now.addingTimeInterval(-18 * 60),
                    costUSD: 0.92
                ),
                RecentSession(
                    id: "demo-recent-3",
                    source: .claudeCode,
                    cwd: "/Users/leonardocruz/Projects/search-indexer",
                    projectName: "search-indexer",
                    title: "Vector batching pipeline",
                    lastPrompt: "Batch embedding upserts in chunks of 128",
                    model: "Opus 4.6",
                    transcriptPath: "",
                    lastActivityAt: now.addingTimeInterval(-95 * 60),
                    costUSD: 1.45
                )
            ]
            agyRecent = [
                RecentSession(
                    id: "demo-recent-2",
                    source: .antigravity,
                    cwd: "/Users/leonardocruz/Projects/design-system",
                    projectName: "design-system",
                    title: "Token contrast audit",
                    lastPrompt: "Verify WCAG AA contrast ratios across dark surfaces",
                    model: "Gemini 3 Pro (High)",
                    transcriptPath: "",
                    lastActivityAt: now.addingTimeInterval(-42 * 60),
                    costUSD: nil
                )
            ]
            rebuildMergedRecent()
            return
        }
        let liveIds = Set(sessions.values.filter { effectiveState(for: $0) != .ended }.map(\.id))
        TranscriptReader.scanRecent(excluding: liveIds) { [weak self] items in
            guard let self else { return }
            self.claudeRecent = items
            self.rebuildMergedRecent()
        }
        syncAntigravitySummaries()
    }

    private func rebuildMergedRecent() {
        let liveIds = Set(sessions.values.filter { effectiveState(for: $0) != .ended }.map(\.id))
        let combined = (claudeRecent + agyRecent)
            .filter { !liveIds.contains($0.id) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
        recent = Array(combined.prefix(40))
    }

    func refreshLocalUsage() {
        if isDemoMode {
            statuslineInstalled = true
            agyHooksInstalled = true
            localUsage = LocalPlanUsage(
                fiveHourTokens: 142_000,
                fiveHourCacheRead: 510_000,
                fiveHourMessages: 18,
                fiveHourSessions: 3,
                fiveHourCostUSD: 1.84,
                sevenDayTokens: 1_420_000,
                sevenDayCacheRead: 4_850_000,
                sevenDayMessages: 164,
                sevenDaySessions: 19,
                sevenDayCostUSD: 19.40,
                todayMessages: 26,
                todaySessions: 4,
                topModels: [
                    (name: "Opus 4.6", tokens: 940_000),
                    (name: "Sonnet 4.6", tokens: 390_000),
                    (name: "Haiku 4.5", tokens: 90_000)
                ],
                agyFiveHourTokens: 96_000,
                agyFiveHourMessages: 12,
                agyFiveHourSessions: 2,
                agySevenDayTokens: 620_000,
                agySevenDayMessages: 74,
                agySevenDaySessions: 11,
                agyTodayMessages: 16,
                agyTodaySessions: 3,
                agyTopModels: [
                    (name: "Gemini 3 Pro (High)", tokens: 440_000),
                    (name: "Gemini 3 Flash", tokens: 180_000)
                ],
                updatedAt: Date()
            )
            return
        }
        statuslineInstalled = Self.checkStatuslineInstalled()
        agyHooksInstalled = Self.checkAgyHooksInstalled()
        usageTracker.scan { [weak self] usage in
            self?.localUsage = usage
        }
    }

    static func checkStatuslineInstalled() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sl = obj["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String
        else { return false }
        return cmd.contains("statusline-tee.sh")
    }

    static func checkAgyHooksInstalled() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/config/hooks.json")
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }
        return obj["spywater"] != nil
    }

    private static var rateLimitsCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spywater/rate-limits-cache.json")
    }

    private func loadCachedRateLimits() {
        let url = Self.rateLimitsCacheURL
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        let current = Date()
        var fivePct = obj.double("fiveHourPct")
        var fiveReset = obj.double("fiveHourReset").map { Date(timeIntervalSince1970: $0) }
        if let r = fiveReset, r <= current {
            fivePct = nil
            fiveReset = nil
        }

        var sevenPct = obj.double("sevenDayPct")
        var sevenReset = obj.double("sevenDayReset").map { Date(timeIntervalSince1970: $0) }
        if let r = sevenReset, r <= current {
            sevenPct = nil
            sevenReset = nil
        }

        var spendPct = obj.double("spendLimitPct")
        var spendReset = obj.double("spendLimitReset").map { Date(timeIntervalSince1970: $0) }
        var spendUsed = obj.double("spendUsedUSD")
        var spendLim = obj.double("spendLimitUSD")
        if let r = spendReset, r <= current {
            spendPct = nil
            spendReset = nil
            spendUsed = nil
            spendLim = nil
        }

        guard fivePct != nil || sevenPct != nil || spendPct != nil else { return }
        let updated = obj.double("updatedAt").map { Date(timeIntervalSince1970: $0) } ?? current
        rateLimits = RateLimits(
            fiveHourPct: fivePct,
            fiveHourReset: fiveReset,
            sevenDayPct: sevenPct,
            sevenDayReset: sevenReset,
            spendLimitPct: spendPct,
            spendLimitReset: spendReset,
            spendUsedUSD: spendUsed,
            spendLimitUSD: spendLim,
            updatedAt: updated
        )
    }

    private func saveCachedRateLimits(_ rl: RateLimits) {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".spywater", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var obj: [String: Any] = ["updatedAt": rl.updatedAt.timeIntervalSince1970]
        if let v = rl.fiveHourPct { obj["fiveHourPct"] = v }
        if let d = rl.fiveHourReset { obj["fiveHourReset"] = d.timeIntervalSince1970 }
        if let v = rl.sevenDayPct { obj["sevenDayPct"] = v }
        if let d = rl.sevenDayReset { obj["sevenDayReset"] = d.timeIntervalSince1970 }
        if let v = rl.spendLimitPct { obj["spendLimitPct"] = v }
        if let d = rl.spendLimitReset { obj["spendLimitReset"] = d.timeIntervalSince1970 }
        if let v = rl.spendUsedUSD { obj["spendUsedUSD"] = v }
        if let v = rl.spendLimitUSD { obj["spendLimitUSD"] = v }

        let data = jsonData(obj)
        try? data.write(to: Self.rateLimitsCacheURL, options: .atomic)
    }

    // MARK: - Helpers

    private static func isClaudeProcess(_ pid: Int32) -> Bool {
        var buf = [CChar](repeating: 0, count: 256)
        let len = proc_name(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return false }
        let name = String(cString: buf).lowercased()
        return name.contains("claude") || name.contains("node")
    }

    private static func projectName(from cwd: String) -> String {
        let comp = URL(fileURLWithPath: cwd).lastPathComponent
        return comp.isEmpty ? cwd : comp
    }

    nonisolated static func describeTool(_ name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            let cmd = input.str("command") ?? ""
            let firstLine = cmd.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? cmd
            let truncated = firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
            return truncated.isEmpty ? "Bash" : "$ \(truncated)"
        case "run_command":
            let cmd = input.str("CommandLine") ?? ""
            let firstLine = cmd.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? cmd
            let truncated = firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
            return truncated.isEmpty ? L10n.t("Comando", "Command") : "$ \(truncated)"
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            let filePath = input.str("file_path") ?? input.str("notebook_path") ?? ""
            let base = filePath.isEmpty ? "" : URL(fileURLWithPath: filePath).lastPathComponent
            return base.isEmpty ? L10n.t("Editando arquivo", "Editing file") : L10n.t("Editando \(base)", "Editing \(base)")
        case "edit_file", "replace_file_content", "multi_replace_file_content", "write_file", "write_to_file":
            let filePath = input.str("Path") ?? input.str("TargetFile") ?? ""
            let base = filePath.isEmpty ? "" : URL(fileURLWithPath: filePath).lastPathComponent
            return base.isEmpty ? L10n.t("Editando arquivo", "Editing file") : L10n.t("Editando \(base)", "Editing \(base)")
        case "Read":
            let filePath = input.str("file_path") ?? ""
            let base = filePath.isEmpty ? "" : URL(fileURLWithPath: filePath).lastPathComponent
            return base.isEmpty ? L10n.t("Lendo arquivo", "Reading file") : L10n.t("Lendo \(base)", "Reading \(base)")
        case "read_file", "view_file":
            let filePath = input.str("Path") ?? input.str("AbsolutePath") ?? ""
            let base = filePath.isEmpty ? "" : URL(fileURLWithPath: filePath).lastPathComponent
            return base.isEmpty ? L10n.t("Lendo arquivo", "Reading file") : L10n.t("Lendo \(base)", "Reading \(base)")
        case "Grep", "Glob":
            let pat = input.str("pattern") ?? ""
            let trunc = pat.count > 50 ? String(pat.prefix(50)) + "…" : pat
            return trunc.isEmpty ? L10n.t("Buscando", "Searching") : L10n.t("Buscando \(trunc)", "Searching \(trunc)")
        case "grep_search":
            let pat = input.str("Query") ?? ""
            let trunc = pat.count > 50 ? String(pat.prefix(50)) + "…" : pat
            return trunc.isEmpty ? L10n.t("Buscando", "Searching") : L10n.t("Buscando \(trunc)", "Searching \(trunc)")
        case "find_by_name":
            let pat = input.str("Pattern") ?? ""
            let trunc = pat.count > 50 ? String(pat.prefix(50)) + "…" : pat
            return trunc.isEmpty ? L10n.t("Buscando", "Searching") : L10n.t("Buscando \(trunc)", "Searching \(trunc)")
        case "list_dir":
            let dirPath = input.str("DirectoryPath") ?? ""
            let base = dirPath.isEmpty ? "" : URL(fileURLWithPath: dirPath).lastPathComponent
            return base.isEmpty ? L10n.t("Listando pasta", "Listing folder") : L10n.t("Listando \(base)", "Listing \(base)")
        case "WebFetch", "WebSearch", "search_web", "read_url_content":
            let q = input.str("url") ?? input.str("Url") ?? input.str("query") ?? ""
            let trunc = q.count > 60 ? String(q.prefix(60)) + "…" : q
            return trunc.isEmpty ? "Web" : "Web: \(trunc)"
        case "Agent", "Task":
            let desc = input.str("description") ?? ""
            return desc.isEmpty ? L10n.t("Subagente", "Subagent") : L10n.t("Subagente: \(desc)", "Subagent: \(desc)")
        case "invoke_subagent":
            let role = input.str("Role") ?? ""
            return role.isEmpty ? L10n.t("Subagente", "Subagent") : L10n.t("Subagente: \(role)", "Subagent: \(role)")
        case "AskUserQuestion", "ask_question":
            return L10n.t("Aguardando resposta", "Waiting for answer")
        case "ExitPlanMode":
            return L10n.t("Plano pronto para aprovação", "Plan ready for approval")
        case "ask_permission":
            let action = input.nonEmptyStr("Action") ?? ""
            let target = input.nonEmptyStr("Target") ?? ""
            let combined = [action, target].filter { !$0.isEmpty }.joined(separator: " ")
            return combined.isEmpty ? L10n.t("Solicitando permissão", "Requesting permission") : L10n.t("Permissão: \(combined)", "Permission: \(combined)")
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.dropFirst(5).split(separator: "__", maxSplits: 1)
                if parts.count == 2 {
                    return "MCP \(parts[0]) › \(parts[1])"
                }
            }
            return name.isEmpty ? L10n.t("Executando ferramenta", "Running tool") : name
        }
    }
}
