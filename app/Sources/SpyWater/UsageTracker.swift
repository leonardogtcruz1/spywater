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
    let updatedAt: Date
}

func formatModelName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    guard lower.hasPrefix("claude-") else { return trimmed }

    var parts = lower.dropFirst("claude-".count).split(separator: "-").map(String.init)
    guard !parts.isEmpty else { return trimmed }

    if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
        parts.removeLast()
    }
    var suffix = ""
    if let last = parts.last, last == "1m" {
        suffix = " (1M)"
        parts.removeLast()
    }
    guard let family = parts.first else { return trimmed }
    let familyTitle = family.prefix(1).uppercased() + family.dropFirst()
    let rest = parts.dropFirst()
    if rest.isEmpty {
        return familyTitle + suffix
    }
    let version = rest.joined(separator: ".")
    return "\(familyTitle) \(version)\(suffix)"
}

final class UsageTracker {
    private struct TurnRecord {
        let timestamp: Date
        let model: String
        let billableTokens: Int
        let cacheRead: Int
    }

    private struct CachedFile {
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
        let projectsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
        let now = Date()
        let cutoff7d = now.addingTimeInterval(-7 * 86400)
        let cutoff5h = now.addingTimeInterval(-5 * 3600)
        let startOfToday = Calendar.current.startOfDay(for: now)

        var activePaths = Set<String>()

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
                        updateCacheIfNeeded(path: entry.path, mtime: mtime, size: size, sessionId: sid, isRoot: true)
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
                                updateCacheIfNeeded(path: subFile.path, mtime: smtime, size: ssize, sessionId: sid, isRoot: false)
                            }
                        }
                    }
                }
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

        for cached in cache.values {
            var sessionHad5h = false
            var sessionHad7d = false

            for rec in cached.records {
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
            }

            if cached.isRootTranscript, let cost = cached.costUSD, cost > 0 {
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
            updatedAt: now
        )
    }

    private func updateCacheIfNeeded(path: String, mtime: Date, size: UInt64, sessionId: String, isRoot: Bool) {
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
            mtime: mtime,
            size: size,
            sessionId: sessionId,
            isRootTranscript: isRoot,
            costUSD: costUSD,
            records: records
        )
    }
}
