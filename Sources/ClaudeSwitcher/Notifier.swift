import ClaudeSwitcherCore
import Foundation
@preconcurrency import UserNotifications

/// Posts "account is full" / "account is back" notifications. No-ops outside an app bundle
/// (UNUserNotificationCenter traps there), e.g. when run from `.build/debug`.
@MainActor
final class Notifier {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    }

    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ alert: UsageAlert, snapshot: Snapshot) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        switch alert {
        case .full(let account, let percent):
            content.title = "Account \(account.label) is at \(percent)%"
            content.body = snapshot.next == account
                ? "New sessions still start on \(account.label). Switch to keep going."
                : "New sessions now start on \(snapshot.next.label)."
        case .available(let account):
            content.title = "Account \(account.label) is available again"
            content.body = "Its usage limit has reset."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        // Deliver once allowed; if the user hasn't been asked yet, ask and deliver on yes.
        // (Completion handlers, not async: UNNotificationSettings isn't Sendable, and older
        // Swift 6 compilers reject sending it across actors.)
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { center.add(request) }
                }
            default:
                break
            }
        }
    }
}
