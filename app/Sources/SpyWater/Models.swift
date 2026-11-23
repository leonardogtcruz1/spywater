import Foundation
import SwiftUI

enum SessionSource: String, CaseIterable {
    case claudeCode
    case antigravity

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .antigravity: return "Antigravity"
        }
    }

    var icon: String {
        switch self {
        case .claudeCode: return "terminal.fill"
        case .antigravity: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .claudeCode: return Theme.amber
        case .antigravity: return Theme.aqua
        }
    }
}

enum SessionState: String, CaseIterable {
    case needsYou
    case waitingTerminal
    case yourTurn
    case error
    case working
    case idle
    case ended

    var priority: Int {
        switch self {
        case .needsYou: return 0
        case .waitingTerminal: return 1
        case .yourTurn, .error: return 2
        case .working: return 3
        case .idle: return 4
        case .ended: return 5
        }
    }

    var label: String {
        switch self {
        case .needsYou: return "Precisa de você"
        case .waitingTerminal: return "Esperando no terminal"
        case .yourTurn: return "Sua vez"
        case .error: return "Erro"
        case .working: return "Trabalhando"
        case .idle: return "Pronta"
        case .ended: return "Encerrada"
        }
    }

    var color: Color {
        switch self {
        case .needsYou: return Theme.coral
        case .waitingTerminal: return Theme.amber
        case .yourTurn: return Theme.amber
        case .error: return Theme.coral
        case .working: return Theme.aqua
        case .idle: return Theme.teal.opacity(0.75)
        case .ended: return .secondary
        }
    }
}

enum PendingKind: String {
    case permission
    case question
    case plan
}

struct PendingRequest: Identifiable {
    let id: UUID
    let sessionId: String
    var source: SessionSource = .claudeCode
    let kind: PendingKind
    let event: String
    let toolName: String
    let toolInput: [String: Any]
    let suggestions: [[String: Any]]
    let createdAt: Date
    let responder: HookResponder
}

struct Session: Identifiable {
    let id: String
    var source: SessionSource = .claudeCode
    var cwd: String
    var projectName: String
    var title: String?
    var model: String?
    var hasStatuslineModel: Bool = false
    var effort: String?
    var permissionMode: String?
    var state: SessionState
    var activity: String
    var lastPrompt: String?
    var lastAssistantMessage: String?
    var contextTokens: Int?
    var contextWindow: Int?
    var contextPct: Double?
    var costUSD: Double?
    var pid: Int32?
    var termProgram: String?
    var transcriptPath: String?
    var startedAt: Date
    var lastEventAt: Date
    var subagentsRunning: Int = 0
    var hasPermissionPromptInTerminal: Bool = false

    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        if let p = lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            let singleLine = p.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count > 60 {
                return String(singleLine.prefix(60)) + "…"
            }
            return singleLine
        }
        return projectName
    }
}

struct RateLimits {
    var fiveHourPct: Double?
    var fiveHourReset: Date?
    var sevenDayPct: Double?
    var sevenDayReset: Date?
    var spendLimitPct: Double?
    var spendLimitReset: Date?
    var spendUsedUSD: Double?
    var spendLimitUSD: Double?
    var updatedAt: Date
}

struct RecentSession: Identifiable {
    let id: String
    var source: SessionSource = .claudeCode
    let cwd: String
    let projectName: String
    let title: String?
    let lastPrompt: String?
    let model: String?
    let transcriptPath: String
    let lastActivityAt: Date
    let costUSD: Double?

    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        if let p = lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            let singleLine = p.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count > 60 {
                return String(singleLine.prefix(60)) + "…"
            }
            return singleLine
        }
        return projectName
    }
}
