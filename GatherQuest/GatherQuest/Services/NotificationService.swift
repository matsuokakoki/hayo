import Foundation
import UserNotifications
import Combine

/// In-app banner + local (non-APNs) notifications.
/// Priority per the risk-hedging policy: Firestore-driven local notifications first; FCM later.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    @Published var banner: Banner?

    private var knownMissionIds = Set<String>()
    private var lastHayoCount: Int?

    func showBanner(_ text: String) {
        banner = Banner(text: text)
        postLocal(title: "hayo", body: text)
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { banner = nil }
        }
    }

    /// Detect newly published missions -> banner + local notification.
    func checkMissions(_ missions: [Mission]) {
        for m in missions where m.isPublished {
            guard let id = m.id, !knownMissionIds.contains(id) else { continue }
            knownMissionIds.insert(id)
            showBanner("📸 ミッション: \(m.title)（2分以内！）")
        }
    }

    /// Detect increments of my own hayoCount -> banner.
    func checkHayo(myCount: Int?) {
        guard let myCount else { return }
        if let last = lastHayoCount, myCount > last {
            showBanner("🔥 「はよ」が届きました ×\(myCount)")
        }
        lastHayoCount = myCount
    }

    private func postLocal(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func reset() {
        knownMissionIds = []
        lastHayoCount = nil
        banner = nil
    }
}
