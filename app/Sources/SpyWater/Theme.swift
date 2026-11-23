import SwiftUI

enum Theme {
    static let bgTop = Color(red: 0.04, green: 0.07, blue: 0.13)
    static let bgBottom = Color(red: 0.06, green: 0.10, blue: 0.19)
    static let cardSurface = Color.white.opacity(0.055)
    static let cardSurfaceElevated = Color.white.opacity(0.085)
    static let insetSurface = Color.black.opacity(0.32)
    static let cardBorder = Color.white.opacity(0.11)

    static let aqua = Color(red: 0.22, green: 0.78, blue: 0.98)
    static let teal = Color(red: 0.18, green: 0.85, blue: 0.76)
    static let violet = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let coral = Color(red: 0.99, green: 0.44, blue: 0.52)
    static let amber = Color(red: 0.99, green: 0.75, blue: 0.25)
    static let emerald = Color(red: 0.20, green: 0.84, blue: 0.58)

    static var bgGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [aqua, violet], startPoint: .leading, endPoint: .trailing)
    }

    static func usageColor(for pct: Double) -> Color {
        if pct >= 85 { return coral }
        if pct >= 60 { return amber }
        return emerald
    }

    static func usageGradient(for pct: Double) -> LinearGradient {
        if pct >= 85 {
            return LinearGradient(colors: [amber, coral], startPoint: .leading, endPoint: .trailing)
        }
        if pct >= 60 {
            return LinearGradient(colors: [emerald, amber], startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [teal, aqua], startPoint: .leading, endPoint: .trailing)
    }
}
