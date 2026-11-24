import Foundation

enum MergeOutcome {
    case merged(hadChanges: Bool)
    case conflict(String)
    case error(String)
}

enum WorktreeManager {
    private static let mergeQueue = DispatchQueue(label: "com.leonardocruz.spywater.gitmerge")

    private struct GitResult {
        let code: Int32
        let stdout: String
        let stderr: String

        var combinedOutput: String {
            [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    private static func runGit(_ args: [String], in dir: String? = nil) -> GitResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        var fullArgs: [String] = []
        if let dir {
            fullArgs += ["-C", dir]
        }
        fullArgs += args
        proc.arguments = fullArgs

        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return GitResult(code: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outStr = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errStr = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return GitResult(code: proc.terminationStatus, stdout: outStr, stderr: errStr)
    }

    private static func hasGitIdentity(at path: String) -> Bool {
        let name = runGit(["config", "user.name"], in: path).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = runGit(["config", "user.email"], in: path).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !email.isEmpty
    }

    static func ensureGitRepo(at path: String) -> (ok: Bool, baseBranch: String, error: String?) {
        mergeQueue.sync {
            let fm = FileManager.default
            if !fm.fileExists(atPath: path) {
                do {
                    try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
                } catch {
                    return (false, "main", "Não foi possível criar a pasta: \(error.localizedDescription)")
                }
            }

            let isRepo = runGit(["rev-parse", "--is-inside-work-tree"], in: path)
            if isRepo.code != 0 {
                let initRes = runGit(["init", "-b", "main"], in: path)
                if initRes.code != 0 {
                    let fallback = runGit(["init"], in: path)
                    if fallback.code != 0 {
                        return (false, "main", "Falha ao inicializar repositório git: \(fallback.combinedOutput)")
                    }
                }
            }

            let hasHead = runGit(["rev-parse", "--verify", "HEAD"], in: path)
            if hasHead.code != 0 {
                var commitArgs: [String] = []
                if !hasGitIdentity(at: path) {
                    commitArgs += ["-c", "user.name=SpyWater", "-c", "user.email=spywater@local"]
                }
                commitArgs += ["commit", "--allow-empty", "-m", "chore: initial commit (SpyWater)"]
                let commitRes = runGit(commitArgs, in: path)
                if commitRes.code != 0 {
                    return (false, "main", "Falha ao criar commit inicial: \(commitRes.combinedOutput)")
                }
            }

            let branchRes = runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
            let branch = branchRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseBranch = (branch.isEmpty || branch == "HEAD") ? "main" : branch
            return (true, baseBranch, nil)
        }
    }

    static func createWorktree(
        repoPath: String,
        missionShortId: String,
        taskId: String,
        baseBranch: String
    ) -> (worktreePath: String, branchName: String, error: String?) {
        mergeQueue.sync {
            let safeId = taskId.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            let cleanId = safeId.isEmpty ? "task" : safeId
            let branch = "spywater/\(missionShortId)/\(cleanId)"

            let fm = FileManager.default
            let wtURL = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".spywater/worktrees/\(missionShortId)/\(cleanId)", isDirectory: true)
            let wtPath = wtURL.path

            try? fm.createDirectory(at: wtURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            _ = runGit(["worktree", "remove", "--force", wtPath], in: repoPath)
            try? fm.removeItem(atPath: wtPath)
            _ = runGit(["worktree", "prune"], in: repoPath)
            _ = runGit(["branch", "-D", branch], in: repoPath)

            let addRes = runGit(["worktree", "add", "-b", branch, wtPath, baseBranch], in: repoPath)
            if addRes.code != 0 {
                return (wtPath, branch, "Falha ao criar worktree: \(addRes.combinedOutput)")
            }
            return (wtPath, branch, nil)
        }
    }

    static func commitAndMerge(
        repoPath: String,
        worktreePath: String,
        branchName: String,
        baseBranch: String,
        taskId: String,
        taskTitle: String
    ) -> MergeOutcome {
        mergeQueue.sync {
            let statusRes = runGit(["status", "--porcelain"], in: worktreePath)
            if statusRes.code != 0 {
                return .error("Falha ao verificar status na worktree: \(statusRes.combinedOutput)")
            }

            if !statusRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let addRes = runGit(["add", "-A"], in: worktreePath)
                if addRes.code != 0 {
                    return .error("Falha no git add: \(addRes.combinedOutput)")
                }

                var commitArgs: [String] = []
                if !hasGitIdentity(at: worktreePath) {
                    commitArgs += ["-c", "user.name=SpyWater", "-c", "user.email=spywater@local"]
                }
                commitArgs += ["commit", "-m", "mission(\(taskId)): \(taskTitle)"]
                let commitRes = runGit(commitArgs, in: worktreePath)
                if commitRes.code != 0 {
                    return .error("Falha no commit da tarefa \(taskId): \(commitRes.combinedOutput)")
                }
            }

            let countRes = runGit(["rev-list", "--count", "\(baseBranch)..\(branchName)"], in: repoPath)
            let commitCount = Int(countRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if commitCount == 0 {
                return .merged(hadChanges: false)
            }

            var mergeArgs: [String] = []
            if !hasGitIdentity(at: repoPath) {
                mergeArgs += ["-c", "user.name=SpyWater", "-c", "user.email=spywater@local"]
            }
            mergeArgs += ["merge", "--no-edit", branchName]
            let mergeRes = runGit(mergeArgs, in: repoPath)
            if mergeRes.code == 0 {
                return .merged(hadChanges: true)
            }

            _ = runGit(["merge", "--abort"], in: repoPath)
            return .conflict(mergeRes.combinedOutput)
        }
    }

    static func removeWorktree(
        repoPath: String,
        worktreePath: String,
        branchName: String?,
        deleteBranch: Bool
    ) {
        mergeQueue.sync {
            _ = runGit(["worktree", "remove", "--force", worktreePath], in: repoPath)
            try? FileManager.default.removeItem(atPath: worktreePath)
            _ = runGit(["worktree", "prune"], in: repoPath)
            if deleteBranch, let branchName, !branchName.isEmpty {
                _ = runGit(["branch", "-D", branchName], in: repoPath)
            }
        }
    }
}
