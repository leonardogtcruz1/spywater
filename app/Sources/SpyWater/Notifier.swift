import AppKit
import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter?
    var onPermissionAction: ((UUID, Bool) -> Void)?
    var onOpenMainWindow: (() -> Void)?

    func setup() {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app"
        else {
            return
        }

        let nc = UNUserNotificationCenter.current()
        self.center = nc
        nc.delegate = self

        let allowAction = UNNotificationAction(identifier: "ALLOW", title: "Permitir", options: [])
        let denyAction = UNNotificationAction(identifier: "DENY", title: "Negar", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: "PERMISSION",
            actions: [allowAction, denyAction],
            intentIdentifiers: [],
            options: []
        )
        nc.setNotificationCategories([category])
        nc.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyPending(_ req: PendingRequest, projectName: String, summary: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["pendingId": req.id.uuidString]

        switch req.kind {
        case .permission:
            content.title = "Permissão — \(projectName)"
            content.body = summary
            content.categoryIdentifier = "PERMISSION"
        case .question:
            content.title = "Claude tem uma pergunta — \(projectName)"
            content.body = "Abra o SpyWater para responder."
        case .plan:
            content.title = "Plano pronto — \(projectName)"
            content.body = "Abra o SpyWater para aprovar ou revisar."
        }

        let request = UNNotificationRequest(
            identifier: "pending-\(req.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    func notifyYourTurn(session: Session) {
        guard let center else { return }
        guard UserDefaults.standard.bool(forKey: "notifyYourTurn") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sua vez — \(session.projectName)"
        content.body = session.displayTitle
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "turn-\(session.id)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    func removePendingNotification(id: UUID) {
        center?.removeDeliveredNotifications(withIdentifiers: ["pending-\(id.uuidString)"])
        center?.removePendingNotificationRequests(withIdentifiers: ["pending-\(id.uuidString)"])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let pendingId = (userInfo["pendingId"] as? String).flatMap(UUID.init(uuidString:))

        DispatchQueue.main.async {
            if let pendingId {
                if response.actionIdentifier == "ALLOW" {
                    self.onPermissionAction?(pendingId, true)
                } else if response.actionIdentifier == "DENY" {
                    self.onPermissionAction?(pendingId, false)
                } else {
                    self.onOpenMainWindow?()
                }
            } else {
                self.onOpenMainWindow?()
            }
        }
        completionHandler()
    }
}
