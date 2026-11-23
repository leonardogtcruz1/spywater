import Foundation

struct LocalPlanUsage {
    let fiveHourTokens: Int
    let fiveHourCacheRead: Int
    let fiveHourMessages: Int
    let fiveHourSessions: Int
    let fiveHourCostUSD: Double
    let sevenDayTokens: Int
    let sevenDayCacheRead: Int
    let sevenDayMessages: Int
    let sevenDaySessions: Int
    let sevenDayCostUSD: Double
    let todayMessages: Int
    let todaySessions: Int
    let topModels: [(name: String, tokens: Int)]

    let agyFiveHourTokens: Int
    let agyFiveHourMessages: Int
    let agyFiveHourSessions: Int
    let agySevenDayTokens: Int
    let agySevenDayMessages: Int
    let agySevenDaySessions: Int
    let agyTodayMessages: Int
    let agyTodaySessions: Int
    let agyTopModels: [(name: String, tokens: Int)]

    let updatedAt: Date
}

func formatModelName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    let effortTags: Set<String> = ["low", "medium", "high", "xhigh", "max"]

    if lower.hasPrefix("claude-") {
        var parts = lower.dropFirst("claude-".count).split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return trimmed }

        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        var suffix = ""
        if let last = parts.last, effortTags.contains(last) {
            suffix = " (\(last.prefix(1).uppercased() + last.dropFirst()))" + suffix
            parts.removeLast()
        }
        if let last = parts.last, last == "1m" {
            suffix = " (1M)" + suffix
            parts.removeLast()
        }
        guard let family = parts.first else { return trimmed }
        let familyTitle = family.prefix(1).uppercased() + family.dropFirst()
        let rest = parts.dropFirst()
        if rest.isEmpty {
            return familyTitle + suffix
        }
        return "\(familyTitle) \(rest.joined(separator: "."))\(suffix)"
    }

    if lower.hasPrefix("gemini-") {
        var parts = lower.split(separator: "-").map(String.init)
        var suffix = ""
        if let last = parts.last, effortTags.contains(last) {
            suffix = " (\(last.prefix(1).uppercased() + last.dropFirst()))"
            parts.removeLast()
        }
        let words = parts.map { part -> String in
            if part.allSatisfy({ $0.isNumber || $0 == "." }) {
                return part
            }
            return part.prefix(1).uppercased() + part.dropFirst()
        }
        return words.joined(separator: " ") + suffix
    }

    return trimmed
}

final class UsageTracker {
    private enum SourceKind {
        case claude
        case antigravity
    }

    private struct TurnRecord {
        let timestamp: Date
        let model: String
        let billableTokens: Int
        let cacheRead: Int
    }

    private struct CachedFile {
        let source: SourceKind
        let mtime: Date
        let size: UInt64
        let sessionId: String
        let isRootTranscript: Bool
        let costUSD: Double?
        let records: [TurnRecord]
    }

    private let queue = DispatchQueue(label: "com.leonardocruz.spywater.usage", qos: .utility)
    private var cache: [String: CachedFile] = [:]

    private lazy var isoWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private lazy var isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func scan(completion: @escaping (LocalPlanUsage) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.performScan()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func parseDate(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        return isoWithFrac.date(from: str) ?? isoNoFrac.date(from: str)
    }

    private func performScan() -> LocalPlanUsage {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let now = Date()
        let cutoff7d = now.addingTimeInterval(-7 * 86400)
        let cutoff5h = now.addingTimeInterval(-5 * 3600)
        let startOfToday = Calendar.current.startOfDay(for: now)

        var activePaths = Set<String>()

        // 1. Scan Claude Code transcripts
        let projectsURL = home.appendingPathComponent(".claude/projects", isDirectory: true)
        if let projectDirs = try? fm.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for projDir in projectDirs {
                guard (try? projDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                guard let entries = try? fm.contentsOfDirectory(
                    at: projDir,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for entry in entries {
                    guard let vals = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey]) else {
                        continue
                    }

                    if vals.isRegularFile == true && entry.pathExtension == "jsonl" {
                        let mtime = vals.contentModificationDate ?? .distantPast
                        guard mtime >= cutoff7d else { continue }
                        let size = UInt64(vals.fileSize ?? 0)
                        let sid = entry.deletingPathExtension().lastPathComponent
                        activePaths.insert(entry.path)
                        updateClaudeCacheIfNeeded(path: entry.path, mtime: mtime, size: size, sessionId: sid, isRoot: true)
                    } else if vals.isDirectory == true {
                        let sid = entry.lastPathComponent
                        let subagentsDir = entry.appendingPathComponent("subagents", isDirectory: true)
                        if let subFiles = try? fm.contentsOfDirectory(
                            at: subagentsDir,
                            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                            options: [.skipsHiddenFiles]
                        ) {
                            for subFile in subFiles where subFile.pathExtension == "jsonl" {
                                guard let svals = try? subFile.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                                      svals.isRegularFile == true,
                                      let smtime = svals.contentModificationDate,
                                      smtime >= cutoff7d
                                else { continue }
                                let ssize = UInt64(svals.fileSize ?? 0)
                                activePaths.insert(subFile.path)
                                updateClaudeCacheIfNeeded(path: subFile.path, mtime: smtime, size: ssize, sessionId: sid, isRoot: false)
                            }
                        }
                    }
                }
            }
        }

        // 2. Scan Antigravity transcripts
        let brainURL = home.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        if let convDirs = try? fm.contentsOfDirectory(
            at: brainURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for convDir in convDirs {
                guard (try? convDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let sid = convDir.lastPathComponent
                let tURL = convDir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
                guard let vals = try? tURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                      vals.isRegularFile == true,
                      let mtime = vals.contentModificationDate,
                      mtime >= cutoff7d
                else { continue }
                let size = UInt64(vals.fileSize ?? 0)
                activePaths.insert(tURL.path)
                updateAgyCacheIfNeeded(path: tURL.path, mtime: mtime, size: size, sessionId: sid)
            }
        }

        cache = cache.filter { activePaths.contains($0.key) }

        var fiveHourTokens = 0
        var fiveHourCacheRead = 0
        var fiveHourMessages = 0
        var fiveHourSessionSet = Set<String>()
        var fiveHourCost = 0.0

        var sevenDayTokens = 0
        var sevenDayCacheRead = 0
        var sevenDayMessages = 0
        var sevenDaySessionSet = Set<String>()
        var sevenDayCost = 0.0

        var todayMessages = 0
        var todaySessionSet = Set<String>()
        var modelTotals: [String: Int] = [:]

        var agyFiveHourTokens = 0
        var agyFiveHourMessages = 0
        var agyFiveHourSessionSet = Set<String>()
        var agySevenDayTokens = 0
        var agySevenDayMessages = 0
        var agySevenDaySessionSet = Set<String>()
        var agyTodayMessages = 0
        var agyTodaySessionSet = Set<String>()
        var agyModelTotals: [String: Int] = [:]

        for cached in cache.values {
            var sessionHad5h = false
            var sessionHad7d = false

            for rec in cached.records {
                switch cached.source {
                case .claude:
                    if rec.timestamp >= cutoff7d {
                        sevenDayTokens += rec.billableTokens
                        sevenDayCacheRead += rec.cacheRead
                        sevenDayMessages += 1
                        sevenDaySessionSet.insert(cached.sessionId)
                        sessionHad7d = true
                        if !rec.model.isEmpty {
                            let display = formatModelName(rec.model)
                            modelTotals[display, default: 0] += rec.billableTokens
                        }
                    }
                    if rec.timestamp >= cutoff5h {
                        fiveHourTokens += rec.billableTokens
                        fiveHourCacheRead += rec.cacheRead
                        fiveHourMessages += 1
                        fiveHourSessionSet.insert(cached.sessionId)
                        sessionHad5h = true
                    }
                    if rec.timestamp >= startOfToday {
                        todayMessages += 1
                        todaySessionSet.insert(cached.sessionId)
                    }

                case .antigravity:
                    if rec.timestamp >= cutoff7d {
                        agySevenDayTokens += rec.billableTokens
                        agySevenDayMessages += 1
                        agySevenDaySessionSet.insert(cached.sessionId)
                        if !rec.model.isEmpty {
                            let display = formatModelName(rec.model)
                            agyModelTotals[display, default: 0] += rec.billableTokens
                        }
                    }
                    if rec.timestamp >= cutoff5h {
                        agyFiveHourTokens += rec.billableTokens
                        agyFiveHourMessages += 1
                        agyFiveHourSessionSet.insert(cached.sessionId)
                    }
                    if rec.timestamp >= startOfToday {
                        agyTodayMessages += 1
                        agyTodaySessionSet.insert(cached.sessionId)
                    }
                }
            }

            if cached.source == .claude, cached.isRootTranscript, let cost = cached.costUSD, cost > 0 {
                if sessionHad7d || cached.mtime >= cutoff7d {
                    sevenDayCost += cost
                }
                if sessionHad5h || cached.mtime >= cutoff5h {
                    fiveHourCost += cost
                }
            }
        }

        let topModels = modelTotals
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (name: $0.key, tokens: $0.value) }

        let agyTopModels = agyModelTotals
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (name: $0.key, tokens: $0.value) }

        return LocalPlanUsage(
            fiveHourTokens: fiveHourTokens,
            fiveHourCacheRead: fiveHourCacheRead,
            fiveHourMessages: fiveHourMessages,
            fiveHourSessions: fiveHourSessionSet.count,
            fiveHourCostUSD: fiveHourCost,
            sevenDayTokens: sevenDayTokens,
            sevenDayCacheRead: sevenDayCacheRead,
            sevenDayMessages: sevenDayMessages,
            sevenDaySessions: sevenDaySessionSet.count,
            sevenDayCostUSD: sevenDayCost,
            todayMessages: todayMessages,
            todaySessions: todaySessionSet.count,
            topModels: topModels,
            agyFiveHourTokens: agyFiveHourTokens,
            agyFiveHourMessages: agyFiveHourMessages,
            agyFiveHourSessions: agyFiveHourSessionSet.count,
            agySevenDayTokens: agySevenDayTokens,
            agySevenDayMessages: agySevenDayMessages,
            agySevenDaySessions: agySevenDaySessionSet.count,
            agyTodayMessages: agyTodayMessages,
            agyTodaySessions: agyTodaySessionSet.count,
            agyTopModels: agyTopModels,
            updatedAt: now
        )
    }

    private func updateClaudeCacheIfNeeded(path: String, mtime: Date, size: UInt64, sessionId: String, isRoot: Bool) {
        if let existing = cache[path], existing.mtime == mtime, existing.size == size {
            return
        }

        guard let data = FileManager.default.contents(atPath: path) else { return }
        let text = String(decoding: data, as: UTF8.self)

        var seenMessageIds = Set<String>()
        var records: [TurnRecord] = []
        var costUSD: Double?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = rawLine.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
            else { continue }

            let type = obj.str("type")
            if type == "cost-state" {
                if let c = obj.double("totalCostUSD") {
                    costUSD = c
                }
                continue
            }

            guard type == "assistant",
                  let msg = obj.dict("message"),
                  let usage = msg.dict("usage")
            else { continue }

            let dedupKey = msg.nonEmptyStr("id") ?? obj.nonEmptyStr("uuid") ?? ""
            if !dedupKey.isEmpty {
                if seenMessageIds.contains(dedupKey) { continue }
                seenMessageIds.insert(dedupKey)
            }

            guard let ts = parseDate(obj.nonEmptyStr("timestamp")) else { continue }
            let inp = usage.int("input_tokens") ?? 0
            let out = usage.int("output_tokens") ?? 0
            let create = usage.int("cache_creation_input_tokens") ?? 0
            let read = usage.int("cache_read_input_tokens") ?? 0
            let model = msg.nonEmptyStr("model") ?? ""

            records.append(TurnRecord(
                timestamp: ts,
                model: model,
                billableTokens: inp + out + create,
                cacheRead: read
            ))
        }

        cache[path] = CachedFile(
            source: .claude,
            mtime: mtime,
            size: size,
            sessionId: sessionId,
            isRootTranscript: isRoot,
            costUSD: costUSD,
            records: records
        )
    }

    private func updateAgyCacheIfNeeded(path: String, mtime: Date, size: UInt64, sessionId: String) {
        if let existing = cache[path], existing.mtime == mtime, existing.size == size {
            return
        }

        guard let data = FileManager.default.contents(atPath: path) else { return }
        let text = String(decoding: data, as: UTF8.self)

        var records: [TurnRecord] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = rawLine.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
            else { continue }

            guard obj.str("type") == "PLANNER_RESPONSE" else { continue }
            guard let ts = parseDate(obj.nonEmptyStr("created_at")) else { continue }

            let inp = obj.int("input_tokens") ?? 0
            let out = obj.int("output_tokens") ?? 0
            let read = obj.int("cache_read_tokens") ?? 0
            let model = obj.nonEmptyStr("model") ?? ""

            records.append(TurnRecord(
                timestamp: ts,
                model: model,
                billableTokens: inp + out,
                cacheRead: read
            ))
        }

        cache[path] = CachedFile(
            source: .antigravity,
            mtime: mtime,
            size: size,
            sessionId: sessionId,
            isRootTranscript: true,
            costUSD: nil,
            records: records
        )
    }
}
