import AppKit
import Foundation

enum Actions {
    private static let queue = DispatchQueue(label: "com.leonardocruz.spywater.actions", qos: .userInitiated)

    static func openLiveSession(_ session: Session, terminal: String) {
        if session.source == .antigravity {
            focusAntigravity(title: session.displayTitle, projectName: session.projectName)
            return
        }
        if session.state == .ended {
            resume(sessionId: session.id, cwd: session.cwd, terminal: terminal)
        } else {
            focusClaudeSession(
                pid: session.pid,
                termProgram: session.termProgram,
                cwd: session.cwd,
                projectName: session.projectName,
                fallbackTerminal: terminal
            )
        }
    }

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

    static func focusClaudeSession(
        pid: Int32?,
        termProgram: String?,
        cwd: String,
        projectName: String,
        fallbackTerminal: String
    ) {
        if termProgram == "vscode" {
            let folderURL = URL(fileURLWithPath: cwd, isDirectory: true)
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
                NSWorkspace.shared.open([folderURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                activateBundle("com.microsoft.VSCode")
            }
            return
        }

        if termProgram == "ghostty" {
            activateBundle("com.mitchellh.ghostty")
            return
        }
        if termProgram == "WarpTerminal" {
            activateBundle("dev.warp.Warp-Stable")
            return
        }

        queue.async {
            let devTty = pid.flatMap { resolveDevTty(pid: $0) }

            if termProgram == "Apple_Terminal" {
                if !focusTerminalTab(devTty: devTty, projectName: projectName) {
                    DispatchQueue.main.async { activateBundle("com.apple.Terminal") }
                }
                return
            }

            if termProgram == "iTerm.app" {
                if !focusITermSession(devTty: devTty, projectName: projectName) {
                    DispatchQueue.main.async { activateBundle("com.googlecode.iterm2") }
                }
                return
            }

            // Unknown / missing TERM_PROGRAM: probe running Terminal and iTerm2
            if isAppRunning("com.apple.Terminal") && focusTerminalTab(devTty: devTty, projectName: projectName) {
                return
            }
            if isAppRunning("com.googlecode.iterm2") && focusITermSession(devTty: devTty, projectName: projectName) {
                return
            }

            let fallbackBundle = fallbackTerminal == "iterm" ? "com.googlecode.iterm2" : "com.apple.Terminal"
            DispatchQueue.main.async {
                activateBundle(fallbackBundle)
            }
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
        activateBundle(bundleId)
    }

    static func focusAntigravity(title: String? = nil, projectName: String? = nil) {
        let bundleId = "com.google.antigravity"
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate()
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }

        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanProj = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanTitle.isEmpty || !cleanProj.isEmpty else { return }

        queue.async {
            let tEsc = escapeAppleScript(cleanTitle)
            let pEsc = escapeAppleScript(cleanProj)
            let script = """
            tell application "System Events"
                if exists process "Antigravity" then
                    tell process "Antigravity"
                        repeat with w in windows
                            set wName to ""
                            try
                                set wName to name of w
                            end try
                            if ("\(tEsc)" is not "" and wName contains "\(tEsc)") or ("\(pEsc)" is not "" and wName contains "\(pEsc)") then
                                perform action "AXRaise" of w
                                return "matched"
                            end if
                        end repeat
                    end tell
                end if
            end tell
            return ""
            """
            _ = runAppleScript(script)
        }
    }

    static func openInFinder(cwd: String) {
        let url = URL(fileURLWithPath: cwd, isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Helpers

    private static func activateBundle(_ bundleId: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate()
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func isAppRunning(_ bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private static func resolveDevTty(pid: Int32) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "??", raw != "?" else { return nil }
        return raw.hasPrefix("/dev/") ? raw : "/dev/\(raw)"
    }

    private static func focusTerminalTab(devTty: String?, projectName: String) -> Bool {
        let ttyEsc = escapeAppleScript(devTty ?? "")
        let projEsc = escapeAppleScript(projectName)
        let script = """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if "\(ttyEsc)" is not "" then
                        try
                            if tty of t is "\(ttyEsc)" then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return "matched"
                            end if
                        end try
                    end if
                end repeat
            end repeat
            if "\(projEsc)" is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (name of t contains "\(projEsc)") or (custom title of t contains "\(projEsc)") then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return "matched"
                            end if
                        end try
                    end repeat
                end repeat
            end if
        end tell
        return ""
        """
        return runAppleScript(script) == "matched"
    }

    private static func focusITermSession(devTty: String?, projectName: String) -> Bool {
        let ttyEsc = escapeAppleScript(devTty ?? "")
        let projEsc = escapeAppleScript(projectName)
        let script = """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if "\(ttyEsc)" is not "" then
                            try
                                if tty of s is "\(ttyEsc)" then
                                    select t
                                    select s
                                    select w
                                    activate
                                    return "matched"
                                end if
                            end try
                        end if
                    end repeat
                end repeat
            end repeat
            if "\(projEsc)" is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if name of s contains "\(projEsc)" then
                                    select t
                                    select s
                                    select w
                                    activate
                                    return "matched"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end if
        end tell
        return ""
        """
        return runAppleScript(script) == "matched"
    }

    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }
}
