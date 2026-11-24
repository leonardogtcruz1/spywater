import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct SpyWaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SessionStore()
    @StateObject private var missionEngine = MissionEngine()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("SpyWater", id: "main") {
            DashboardView()
                .environmentObject(store)
                .environmentObject(missionEngine)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(.dark)
                .onAppear {
                    store.onOpenMainWindow = {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    missionEngine.onMissionCompleted = { title in
                        store.notifier.notifyMissionCompleted(title: title)
                    }
                    store.server.onDebugStartMission = { body, reply in
                        guard let goal = body.nonEmptyStr("goal"),
                              let path = body.nonEmptyStr("projectPath")
                        else {
                            reply(nil)
                            return
                        }
                        let maxWorkers = body.int("maxWorkers") ?? 3
                        let modeStr = body.nonEmptyStr("permissionMode") ?? "autonomous"
                        let mode = MissionPermissionMode(rawValue: modeStr) ?? .autonomous
                        let mission = missionEngine.startMission(
                            goal: goal,
                            projectPath: path,
                            maxWorkers: maxWorkers,
                            permissionMode: mode
                        )
                        reply(mission.id.uuidString)
                    }
                    store.server.onDebugGetMissions = { reply in
                        let items: [[String: Any]] = missionEngine.missions.map { m in
                            [
                                "id": m.id.uuidString,
                                "status": m.status.rawValue,
                                "title": m.title,
                                "completedCount": m.completedCount,
                                "totalCount": m.tasks.count,
                                "errorMessage": m.errorMessage ?? "",
                                "tasks": m.tasks.map { t in
                                    [
                                        "id": t.id,
                                        "status": t.status.rawValue,
                                        "attempts": t.attempts
                                    ]
                                }
                            ]
                        }
                        reply(items)
                    }
                }
        }
        .defaultSize(width: 900, height: 650)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        } label: {
            Label("\(store.attentionCount)", systemImage: store.attentionCount > 0 ? "exclamationmark.bubble.fill" : "eye")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
