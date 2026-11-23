import Foundation

struct TranscriptSnapshot {
    var title: String?
    var lastPrompt: String?
    var model: String?
    var contextTokens: Int?
    var contextWindow: Int?
    var costUSD: Double?
    var cwd: String?
}

enum TranscriptReader {
    static func readTail(path: String, maxBytes: UInt64 = 512 * 1024) -> TranscriptSnapshot? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }

        let fileSize: UInt64
        do {
            fileSize = try fh.seekToEnd()
        } catch {
            return nil
        }

        let offset: UInt64 = fileSize > maxBytes ? fileSize - maxBytes : 0
        do {
            try fh.seek(toOffset: offset)
        } catch {
            return nil
        }

        guard let data = try? fh.readToEnd(), !data.isEmpty else {
            return nil
        }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }

        var snapshot = TranscriptSnapshot()

        for rawLine in lines.reversed() {
            guard let lineData = rawLine.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
            else { continue }

            let type = obj.str("type")

            if snapshot.cwd == nil, let cwd = obj.nonEmptyStr("cwd") {
                snapshot.cwd = cwd
            }

            if type == "ai-title", snapshot.title == nil {
                snapshot.title = obj.nonEmptyStr("aiTitle")
            } else if type == "last-prompt", snapshot.lastPrompt == nil {
                snapshot.lastPrompt = obj.nonEmptyStr("lastPrompt")
            } else if type == "cost-state", snapshot.costUSD == nil {
                snapshot.costUSD = obj.double("totalCostUSD")
            } else if type == "assistant" {
                if let msg = obj.dict("message") {
                    if snapshot.model == nil {
                        snapshot.model = msg.nonEmptyStr("model")
                    }
                    if snapshot.contextTokens == nil, let usage = msg.dict("usage") {
                        let inp = usage.int("input_tokens") ?? 0
                        let create = usage.int("cache_creation_input_tokens") ?? 0
                        let read = usage.int("cache_read_input_tokens") ?? 0
                        snapshot.contextTokens = inp + create + read
                    }
                }
            } else if type == "user", snapshot.lastPrompt == nil {
                if let msg = obj.dict("message"), let content = msg.nonEmptyStr("content") {
                    snapshot.lastPrompt = content
                }
            }
        }

        if snapshot.cwd == nil && offset > 0 {
            if let headFH = FileHandle(forReadingAtPath: path) {
                defer { try? headFH.close() }
                if let headData = try? headFH.read(upToCount: 16 * 1024) {
                    let headText = String(decoding: headData, as: UTF8.self)
                    for rawLine in headText.split(separator: "\n", omittingEmptySubsequences: true) {
                        guard let lineData = rawLine.data(using: .utf8),
                              let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
                        else { continue }
                        if let cwd = obj.nonEmptyStr("cwd") {
                            snapshot.cwd = cwd
                            break
                        }
                    }
                }
            }
        }

        if snapshot.contextTokens != nil || snapshot.model != nil {
            let is1M = (snapshot.model?.lowercased().contains("1m") ?? false) || ((snapshot.contextTokens ?? 0) > 200_000)
            snapshot.contextWindow = is1M ? 1_000_000 : 200_000
        }

        return snapshot
    }

    static func scanRecent(excluding liveIds: Set<String>, completion: @escaping ([RecentSession]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let projectsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
            guard let projectDirs = try? fm.contentsOfDirectory(
                at: projectsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let cutoff = Date().addingTimeInterval(-7 * 86400)
            var candidates: [(id: String, url: URL, mtime: Date)] = []

            for dir in projectDirs {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                guard let entries = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for fileURL in entries {
                    guard fileURL.pathExtension == "jsonl" else { continue }
                    let sessionId = fileURL.deletingPathExtension().lastPathComponent
                    guard !liveIds.contains(sessionId) else { continue }
                    guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                          vals.isRegularFile == true,
                          let mtime = vals.contentModificationDate,
                          mtime >= cutoff
                    else { continue }
                    candidates.append((sessionId, fileURL, mtime))
                }
            }

            candidates.sort { $0.mtime > $1.mtime }

            var results: [RecentSession] = []
            for item in candidates.prefix(40) {
                guard let snap = readTail(path: item.url.path) else { continue }
                let cwd = snap.cwd ?? NSHomeDirectory()
                let projectName = URL(fileURLWithPath: cwd).lastPathComponent
                let recent = RecentSession(
                    id: item.id,
                    cwd: cwd,
                    projectName: projectName.isEmpty ? cwd : projectName,
                    title: snap.title,
                    lastPrompt: snap.lastPrompt,
                    model: snap.model.map(formatModelName),
                    transcriptPath: item.url.path,
                    lastActivityAt: item.mtime,
                    costUSD: snap.costUSD
                )
                results.append(recent)
                if results.count >= 30 { break }
            }

            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
}
