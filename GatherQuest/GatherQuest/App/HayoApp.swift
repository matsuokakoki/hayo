import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import GoogleMaps
import UserNotifications

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        GMSServices.provideAPIKey("AIzaSyAvqFiM5KBtgi4hv72vPD8NnUpjTi0nK8Y")
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    // Show local notifications immediately even while the app is in the foreground
    // (without this they pile up silently and appear all at once later).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - App

@main
struct HayoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .task { await app.signIn() }
        }
    }
}

// MARK: - Navigation state

enum AppScreen: Equatable {
    case start
    case createGroup
    case inviteCode(groupId: String, code: String)
    case profileEntry(groupId: String)
    case main(groupId: String)
    case ranking(groupId: String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var screen: AppScreen = .start
    @Published var userId: String?
    @Published var errorMessage: String?

    func signIn() async {
        do {
            if let user = Auth.auth().currentUser {
                userId = user.uid
            } else {
                let result = try await Auth.auth().signInAnonymously()
                userId = result.user.uid
            }
        } catch {
            errorMessage = "サインインに失敗しました: \(error.localizedDescription)"
        }
    }

    /// Called on 終了 or when the group disappears (auto-deleted).
    func reset() {
        screen = .start
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            switch app.screen {
            case .start:
                StartView()
            case .createGroup:
                CreateGroupView()
            case .inviteCode(let groupId, let code):
                InviteCodeView(groupId: groupId, code: code)
            case .profileEntry(let groupId):
                ProfileEntryView(groupId: groupId)
            case .main(let groupId):
                MainView(groupId: groupId)
            case .ranking(let groupId):
                RankingView(groupId: groupId)
            }
        }
        .alert("エラー", isPresented: .init(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}
