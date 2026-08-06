import SwiftUI
import FirebaseFirestore

// ⑤ Lobby (HOME): map preview, participant list with はよ buttons.
struct LobbyView: View {
    @ObservedObject private var repo = GroupRepository.shared
    let groupId: String

    var body: some View {
        VStack(spacing: 0) {
            if let group = repo.group {
                // Tap -> open the destination in the Google Maps app (template ⑤).
                Button { openInGoogleMaps(group) } label: {
                    StaticMapPreview(coordinate: group.destinationCoordinate)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                Text("タッチしてGoogleMapsで開く")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }

            HStack {
                Text("参加者").font(.headline)
                Spacer()
                Text("出発時間").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(repo.members) { member in
                        MemberRow(member: member, groupId: groupId)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }

    private func openInGoogleMaps(_ group: MeetGroup) {
        let lat = group.destination.latitude
        let lng = group.destination.longitude
        if let url = URL(string: "comgooglemaps://?q=\(lat),\(lng)&zoom=15"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)") {
            UIApplication.shared.open(url)
        }
    }
}

struct MemberRow: View {
    @ObservedObject private var repo = GroupRepository.shared
    let member: Member
    let groupId: String
    @State private var pressing = false

    /// はよ is enabled when the member is past their planned departure but hasn't departed.
    private var hayoEnabled: Bool {
        member.status == .notDeparted
            && Date() > member.expectedDepartureTime
            && member.id != repo.myUserId
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                UserIconView(urlString: member.iconUrl)
                statusDot
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.subheadline.bold())
                Text(statusLabel).font(.caption2).foregroundColor(.secondary)
            }

            Spacer()

            // Before departure: planned time. After: the actual time 出発 was pressed.
            Text((member.status == .notDeparted
                  ? member.expectedDepartureTime
                  : (member.departureTime ?? member.expectedDepartureTime))
                .formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit())
                .foregroundColor(member.status == .notDeparted ? .primary : .green)

            Button {
                pressHayo()
            } label: {
                Text("はよ")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(hayoEnabled ? Color.orange : Color(.systemGray4)))
            }
            .disabled(!hayoEnabled || pressing)

            Text("×\(member.hayoCount)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundColor(member.hayoCount > 0 ? .orange : .secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var statusLabel: String {
        switch member.status {
        case .notDeparted: return "未出発"
        case .departed: return "移動中"
        case .arrived: return "到着済み"
        }
    }

    @ViewBuilder private var statusDot: some View {
        Circle()
            .fill(member.status == .arrived ? Color.blue :
                  (member.status == .departed ? Color.green : Color(.systemGray3)))
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    private func pressHayo() {
        guard let target = member.id else { return }
        pressing = true
        Task {
            defer { pressing = false }
            try? await repo.pressHayo(groupId: groupId, targetUserId: target)
        }
    }
}
