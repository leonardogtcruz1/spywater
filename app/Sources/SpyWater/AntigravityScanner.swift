import Foundation
import SQLite3

struct AgyConversationSummary {
    let id: String
    let title: String
    let cwd: String
    let projectName: String
    let isRunning: Bool
    let lastModifiedAt: Date
    let runningSubagents: Int
    let transcriptPath: String
}

struct AgyTranscriptSnapshot {
    var model: String?
    var contextTokens: Int?
    var contextWindow: Int?
    var lastPrompt: String?
    var lastActivity: String?
}

enum AntigravityScanner {
    private static let queue = DispatchQueue(label: "com.leonardocruz.spywater.agyscanner", qos: .utility)

    static func scanSummaries(completion: @escaping ([AgyConversationSummary]) -> Void) {
        queue.async {
            let result = performScanSummaries()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func performScanSummaries() -> [AgyConversationSummary] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent(".gemini/antigravity/conversation_summaries.db").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)

        var subagentCounts: [String: Int] = [:]
        var countStmt: OpaquePointer?
        let countSQL = "SELECT parent_conversation_id, COUNT(*) FROM conversation_summaries WHERE parent_conversation_id != '' AND status = 'CASCADE_RUN_STATUS_RUNNING' GROUP BY parent_conversation_id"
        if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK, let countStmt {
            defer { sqlite3_finalize(countStmt) }
            while sqlite3_step(countStmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(countStmt, 0) {
                    let parentId = String(cString: ptr)
                    let cnt = Int(sqlite3_column_int(countStmt, 1))
                    subagentCounts[parentId] = cnt
                }
            }
        }

        let cutoff = Date().addingTimeInterval(-7 * 86400)
        var summaries: [AgyConversationSummary] = []

        var stmt: OpaquePointer?
        let sql = "SELECT conversation_id, title, preview, status, workspace_uris, last_modified_time FROM conversation_summaries WHERE parent_conversation_id = '' AND killed = 0 ORDER BY last_modified_time DESC LIMIT 60"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idPtr)
            let rawTitle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let preview = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let status = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let workspacesJSON = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let modifiedStr = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""

            let modifiedAt = parseSQLiteTimestamp(modifiedStr) ?? Date.distantPast
            guard modifiedAt >= cutoff else { continue }

            let cwd = parseWorkspaceURI(workspacesJSON) ?? NSHomeDirectory()
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? preview : rawTitle
            let transcriptPath = home
                .appendingPathComponent(".gemini/antigravity/brain/\(id)/.system_generated/logs/transcript.jsonl")
                .path

            summaries.append(AgyConversationSummary(
                id: id,
                title: title,
                cwd: cwd,
                projectName: projectName.isEmpty ? cwd : projectName,
                isRunning: status == "CASCADE_RUN_STATUS_RUNNING",
                lastModifiedAt: modifiedAt,
                runningSubagents: subagentCounts[id] ?? 0,
                transcriptPath: transcriptPath
            ))
        }

        return summaries
    }

    static func readTranscriptTail(path: String, maxBytes: UInt64 = 512 * 1024) -> AgyTranscriptSnapshot? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }

        guard let fileSize = try? fh.seekToEnd() else { return nil }
        let offset: UInt64 = fileSize > maxBytes ? fileSize - maxBytes : 0
        guard (try? fh.seek(toOffset: offset)) != nil else { return nil }
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }

        var snapshot = AgyTranscriptSnapshot()

        for rawLine in lines.reversed() {
            guard let lineData = rawLine.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
            else { continue }

            let type = obj.str("type")

            if type == "PLANNER_RESPONSE" {
                if snapshot.model == nil, let m = obj.nonEmptyStr("model") {
                    snapshot.model = formatModelName(m)
                }
                if snapshot.contextTokens == nil {
                    let inp = obj.int("input_tokens")
                    let cacheRead = obj.int("cache_read_tokens")
                    if inp != nil || cacheRead != nil {
                        snapshot.contextTokens = (inp ?? 0) + (cacheRead ?? 0)
                    }
                }
                if snapshot.lastActivity == nil {
                    if let toolCalls = obj.arr("tool_calls"), let lastTC = toolCalls.last {
                        let name = lastTC.nonEmptyStr("name") ?? ""
                        let args = lastTC.dict("args") ?? [:]
                        if !name.isEmpty {
                            snapshot.lastActivity = SessionStore.describeTool(name, input: args)
                        }
                    } else if obj.nonEmptyStr("content") != nil {
                        snapshot.lastActivity = "Respondendo…"
                    }
                }
            } else if type == "USER_INPUT", snapshot.lastPrompt == nil {
                if let rawContent = obj.nonEmptyStr("content") {
                    snapshot.lastPrompt = extractUserRequest(rawContent)
                }
            }

            if snapshot.model != nil && snapshot.contextTokens != nil && snapshot.lastPrompt != nil && snapshot.lastActivity != nil {
                break
            }
        }

        if snapshot.contextTokens != nil || snapshot.model != nil {
            let lowerModel = snapshot.model?.lowercased() ?? ""
            let is1M = lowerModel.contains("gemini") || lowerModel.contains("1m") || ((snapshot.contextTokens ?? 0) > 200_000)
            snapshot.contextWindow = is1M ? 1_000_000 : 200_000
        }

        return snapshot
    }

    private static func parseWorkspaceURI(_ jsonStr: String) -> String? {
        guard let data = jsonStr.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [String],
              let first = arr.first
        else { return nil }
        if first.hasPrefix("file://"), let url = URL(string: first) {
            return url.path
        }
        return first
    }

    private static func parseSQLiteTimestamp(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Normalize "2026-11-23 23:30:25.534511+00:00" -> ISO-8601
        let iso = trimmed.replacingOccurrences(of: " ", with: "T")
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: iso) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let dotIdx = trimmed.firstIndex(of: ".") {
            let prefix = String(trimmed[..<dotIdx])
            return df.date(from: prefix)
        }
        return df.date(from: trimmed)
    }

    private static func extractUserRequest(_ raw: String) -> String {
        if let start = raw.range(of: "<USER_REQUEST>"),
           let end = raw.range(of: "</USER_REQUEST>", range: start.upperBound..<raw.endIndex) {
            return String(raw[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
