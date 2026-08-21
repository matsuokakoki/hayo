import SwiftUI
import Combine

// ⑤〜⑧ container: mission header + MAP / HOME / SNAP tabs + bottom bar.
struct MainView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var repo = GroupRepository.shared
    @StateObject private var location = LocationService.shared
    @ObservedObject private var notifications = NotificationService.shared

    let groupId: String

    @State private var tab: MainTab = .home
    @State private var cameraPurpose: CameraPurpose?
    @State private var seenPhotoIds = Set<String>()
    @State private var started = false

    /// The most recently published, still-relevant mission (for the shared header).
    private var headerMission: Mission? {
        repo.missions.filter { $0.isPublished }.max { $0.publishAt < $1.publishAt }
    }

    private var unseenPhotoCount: Int {
        repo.photos.filter { !seenPhotoIds.contains($0.id ?? "") }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Group name title
            Text(repo.group?.name ?? "…")
                .font(.title2.bold())
                .padding(.vertical, 6)

            // ⑨ shared mission header — tap to open the mission camera
            MissionHeaderView(mission: headerMission) { mission in
                if mission.isActive && !repo.cleared(mission: mission) {
                    cameraPurpose = .mission(mission)
                }
            }

            // Tab content
            ZStack {
                switch tab {
                case .home:
                    LobbyView(groupId: groupId)
                case .map:
                    GroupMapView()
                case .snap:
                    SnapView(groupId: groupId,
                             onOpenCamera: { purpose in cameraPurpose = purpose },
                             seenPhotoIds: $seenPhotoIds)
                }
            }
            .frame(maxHeight: .infinity)

            // Countdown to meet time
            if let meetTime = repo.group?.meetTime {
                MeetTimeCountdown(meetTime: meetTime)
                    .padding(.vertical, 4)
            }

            BottomNavBar(tab: $tab,
                         myStatus: repo.me?.status ?? .notDeparted,
                         unseenPhotoCount: unseenPhotoCount) {
                switch repo.me?.status {
                case .notDeparted: cameraPurpose = .departure
                case .departed: cameraPurpose = .arrival
                default: break
                }
            }
        }
        .overlay(BannerView())
        .fullScreenCover(isPresented: .init(
            get: { cameraPurpose != nil },
            set: { if !$0 { cameraPurpose = nil } }
        )) {
            if let purpose = cameraPurpose {
                CameraView(groupId: groupId, purpose: purpose,
                           headerMission: headerMission) {
                    cameraPurpose = nil
                }
            }
        }
        .onAppear { start() }
        .onDisappear { location.stop() }
        .onChange(of: repo.missions.map(\.id)) { _ in
            notifications.checkMissions(repo.missions)
        }
        // Poll so missions whose publishAt arrives without a data change still notify.
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            notifications.checkMissions(repo.missions)
        }
        .onChange(of: repo.me?.hayoCount) { newValue in
            notifications.checkHayo(myCount: newValue)
        }
        .onChange(of: allArrived) { arrived in
            if arrived { app.screen = .ranking(groupId: groupId) }
        }
    }

    private var allArrived: Bool {
        !repo.members.isEmpty && repo.members.allSatisfy { $0.status == .arrived }
    }

    private func start() {
        location.onUpdate = { loc in
            Task { @MainActor in
                GroupRepository.shared.updateLocationThrottled(groupId: groupId, location: loc)
            }
        }
        location.start()

        // onAppear fires again every time the camera cover closes;
        // listeners/notification state must be set up only once.
        guard !started else { return }
        started = true
        notifications.reset()
        repo.startListening(groupId: groupId) {
            // Group auto-deleted (10 min after everyone gathered).
            NotificationService.shared.showBanner("グループは解散しました")
            app.reset()
        }
    }
}
