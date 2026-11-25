import Foundation

enum L10n {
    static let isEnglish: Bool = {
        let raw = ProcessInfo.processInfo.environment["SPYWATER_LANG"] ?? ""
        return raw.lowercased().hasPrefix("en")
    }()

    static func t(_ pt: String, _ en: String) -> String {
        isEnglish ? en : pt
    }
}
