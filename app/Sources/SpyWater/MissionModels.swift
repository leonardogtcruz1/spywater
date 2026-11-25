import Foundation
import SwiftUI

enum MissionStatus: String, Codable {
    case planning
    case running
    case paused
    case completed
    case failed
    case cancelled

    var label: String {
        switch self {
        case .planning: return L10n.t("Planejando", "Planning")
        case .running: return L10n.t("Executando", "Running")
        case .paused: return L10n.t("Pausada", "Paused")
        case .completed: return L10n.t("Concluída", "Completed")
        case .failed: return L10n.t("Falhou", "Failed")
        case .cancelled: return L10n.t("Cancelada", "Cancelled")
        }
    }

    var color: Color {
        switch self {
        case .planning: return Theme.violet
        case .running: return Theme.aqua
        case .paused: return Theme.amber
        case .completed: return Theme.emerald
        case .failed: return Theme.coral
        case .cancelled: return .secondary
        }
    }
}

enum MissionTaskStatus: String, Codable {
    case pending
    case running
    case merging
    case done
    case failed
    case blocked

    var label: String {
        switch self {
        case .pending: return L10n.t("Na fila", "Queued")
        case .running: return L10n.t("Executando", "Running")
        case .merging: return L10n.t("Fazendo merge", "Merging")
        case .done: return L10n.t("Concluída", "Done")
        case .failed: return L10n.t("Falhou", "Failed")
        case .blocked: return L10n.t("Bloqueada", "Blocked")
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .running: return Theme.aqua
        case .merging: return Theme.teal
        case .done: return Theme.emerald
        case .failed: return Theme.coral
        case .blocked: return Theme.amber
        }
    }
}

enum MissionPermissionMode: String, Codable, CaseIterable {
    case spywaterGate
    case autonomous

    var label: String {
        switch self {
        case .spywaterGate: return L10n.t("Aprovar comandos no SpyWater", "Approve commands in SpyWater")
        case .autonomous: return L10n.t("Autônomo (sem pausas)", "Autonomous (no pauses)")
        }
    }
}

struct MissionTask: Identifiable, Codable {
    let id: String
    var title: String
    var prompt: String
    var dependsOn: [String]
    var verifyCommand: String?
    var status: MissionTaskStatus = .pending
    var attempts: Int = 0
    var maxAttempts: Int = 3
    var branchName: String?
    var worktreePath: String?
    var sessionId: String?
    var lastOutput: String?
    var lastError: String?
    var startedAt: Date?
    var finishedAt: Date?
}

struct Mission: Identifiable, Codable {
    let id: UUID
    var title: String
    var goal: String
    var projectPath: String
    var baseBranch: String
    var maxWorkers: Int
    var permissionMode: MissionPermissionMode
    var status: MissionStatus
    var tasks: [MissionTask]
    var logs: [String]
    var createdAt: Date
    var updatedAt: Date
    var errorMessage: String?

    var shortId: String {
        String(id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8))
    }

    var completedCount: Int {
        tasks.filter { $0.status == .done }.count
    }

    var runningCount: Int {
        tasks.filter { $0.status == .running || $0.status == .merging }.count
    }

    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(tasks.count)
    }
}
