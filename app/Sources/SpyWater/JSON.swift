import Foundation

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? {
        self[key] as? String
    }

    func nonEmptyStr(_ key: String) -> String? {
        guard let s = self[key] as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : s
    }

    func dict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func arr(_ key: String) -> [[String: Any]]? {
        self[key] as? [[String: Any]]
    }

    func anyArr(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }

    func int(_ key: String) -> Int? {
        guard let num = self[key] as? NSNumber else { return nil }
        if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
        return num.intValue
    }

    func double(_ key: String) -> Double? {
        guard let num = self[key] as? NSNumber else { return nil }
        if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
        return num.doubleValue
    }

    func bool(_ key: String) -> Bool? {
        self[key] as? Bool
    }
}

func jsonData(_ obj: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data()
}

func prettyJSON(_ obj: Any) -> String {
    guard JSONSerialization.isValidJSONObject(obj),
          let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
          let s = String(data: data, encoding: .utf8)
    else {
        return String(describing: obj)
    }
    return s
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 {
        let v = Double(n) / 1_000_000.0
        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))M" : String(format: "%.1fM", v)
    } else if n >= 1_000 {
        return "\(n / 1_000)k"
    }
    return "\(n)"
}

func formatRelativeTime(_ date: Date, now: Date = Date()) -> String {
    let sec = max(0, Int(now.timeIntervalSince(date)))
    if sec < 60 { return "há \(sec) s" }
    let min = sec / 60
    if min < 60 { return "há \(min) min" }
    let hrs = min / 60
    if hrs < 24 { return "há \(hrs) h" }
    let days = hrs / 24
    return "há \(days) d"
}

func formatTimeUntil(_ date: Date, now: Date = Date()) -> String {
    let sec = max(0, Int(date.timeIntervalSince(now)))
    if sec < 60 { return "\(sec)s" }
    let min = sec / 60
    if min < 60 { return "\(min)m" }
    let hrs = min / 60
    let remMin = min % 60
    if hrs < 24 {
        return remMin > 0 ? "\(hrs)h \(remMin)m" : "\(hrs)h"
    }
    let days = hrs / 24
    let remHrs = hrs % 24
    return remHrs > 0 ? "\(days)d \(remHrs)h" : "\(days)d"
}
