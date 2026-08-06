import SwiftUI

// MARK: - ⑨ Mission header (shared red band with countdown)

struct MissionHeaderView: View {
    let mission: Mission?

    var body: some View {
        if let mission, mission.isPublished {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Int(mission.expiresAt.timeIntervalSince(context.date))
                HStack {
                    Text("📸 \(mission.title)")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    Text(remaining > 0
                         ? String(format: "%02d:%02d", remaining / 60, remaining % 60)
                         : "時間切れ")
                        .font(.subheadline.monospacedDigit().bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(remaining > 0 ? Color.red.opacity(0.85) : Color.gray)
            }
        }
    }
}

// MARK: - In-app notification banner

struct BannerView: View {
    @ObservedObject var notifications = NotificationService.shared

    var body: some View {
        VStack {
            if let banner = notifications.banner {
                Text(banner.text)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
            Spacer()
        }
        .animation(.spring(), value: notifications.banner)
        .allowsHitTesting(false)
    }
}

// MARK: - Circular async user icon

struct UserIconView: View {
    let urlString: String?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color(.systemGray4)
                    }
                }
            } else {
                ZStack {
                    Color(.systemGray4)
                    Image(systemName: "person.fill").foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Bottom navigation (MAP / 出発・到着 / Photo chat)

enum MainTab { case map, home, snap }

struct BottomNavBar: View {
    @Binding var tab: MainTab
    let myStatus: MemberStatus
    let unseenPhotoCount: Int
    let onCenterAction: () -> Void

    /// 出発/到着 label shown only while on the HOME tab.
    var centerLabel: String {
        switch myStatus {
        case .notDeparted: return "出発"
        case .departed: return "到着"
        case .arrived: return "到着済"
        }
    }

    var body: some View {
        HStack {
            navButton("map.fill", "MAP", isActive: tab == .map) { tab = .map }
            Spacer()

            // Center slot: 出発/到着 on HOME, HOME button elsewhere (per template ⑤〜⑧).
            if tab == .home {
                Button(action: onCenterAction) {
                    Text(centerLabel)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(width: 96, height: 52)
                        .background(Capsule().fill(myStatus == .arrived ? Color.gray : Color.blue))
                }
                .disabled(myStatus == .arrived)
            } else {
                Button { tab = .home } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "house.fill").font(.title3)
                        Text("HOME").font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 96, height: 52)
                    .background(Capsule().fill(Color.blue))
                }
            }

            Spacer()
            ZStack(alignment: .topTrailing) {
                navButton("photo.on.rectangle.angled", "フォト", isActive: tab == .snap) { tab = .snap }
                if unseenPhotoCount > 0 {
                    Text("\(unseenPhotoCount)")
                        .font(.caption2.bold()).foregroundColor(.white)
                        .padding(5).background(Circle().fill(Color.red))
                        .offset(x: 10, y: -6)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .background(.thinMaterial)
    }

    private func navButton(_ icon: String, _ label: String, isActive: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2)
            }
            .foregroundColor(isActive ? .blue : .secondary)
        }
    }
}

// MARK: - Countdown to meet time

struct MeetTimeCountdown: View {
    let meetTime: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let diff = Int(meetTime.timeIntervalSince(context.date))
            let overdue = diff < 0
            let s = abs(diff)
            Text(String(format: "%@%02d:%02d:%02d", overdue ? "+" : "", s / 3600, (s / 60) % 60, s % 60))
                .font(.headline.monospacedDigit())
                .foregroundColor(overdue ? .red : .primary)
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)))
        }
    }
}

// MARK: - Mission clear badges (ranking rows)

struct ClearBadges: View {
    let cleared: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(i < cleared ? .blue : Color(.systemGray4))
            }
        }
    }
}
