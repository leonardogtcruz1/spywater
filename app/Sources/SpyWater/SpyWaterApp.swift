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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("SpyWater", id: "main") {
            DashboardView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(.dark)
                .onAppear {
                    store.onOpenMainWindow = {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
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
