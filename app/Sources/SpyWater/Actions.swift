import AppKit
import Foundation

enum Actions {
    static func resume(sessionId: String, cwd: String, terminal: String) {
        let fm = FileManager.default
        let tmpDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".spywater/tmp", isDirectory: true)
        try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let safeId = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !safeId.isEmpty else { return }

        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/zsh -l
        cd '\(escapedCwd)' && claude --resume '\(safeId)'
        """

        let scriptURL = tmpDir.appendingPathComponent("resume-\(safeId).command")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            return
        }

        let preferredBundleId = terminal == "iterm" ? "com.googlecode.iterm2" : "com.apple.Terminal"
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredBundleId)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")

        if let appURL {
            NSWorkspace.shared.open([scriptURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(scriptURL)
        }
    }

    static func focusTerminal(termProgram: String?) {
        let bundleId: String? = {
            switch termProgram {
            case "Apple_Terminal": return "com.apple.Terminal"
            case "iTerm.app": return "com.googlecode.iterm2"
            case "ghostty": return "com.mitchellh.ghostty"
            case "WarpTerminal": return "dev.warp.Warp-Stable"
            case "vscode": return "com.microsoft.VSCode"
            default: return nil
            }
        }()

        guard let bundleId else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
    }

    static func openInFinder(cwd: String) {
        let url = URL(fileURLWithPath: cwd, isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
