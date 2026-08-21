import SwiftUI
import FirebaseFirestore

// ④ Profile entry: destination confirmation, name, expected departure time.
struct ProfileEntryView: View {
    @EnvironmentObject var app: AppState
    let groupId: String

    @State private var group: MeetGroup?
    @State private var name = ""
    @State private var departureTime = Date().addingTimeInterval(15 * 60)
    @State private var isJoining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(group?.name ?? "…")
                .font(.title.bold())
                .frame(maxWidth: .infinity)

            if let group {
                Button { openInGoogleMaps(group) } label: {
                    StaticMapPreview(coordinate: group.destinationCoordinate)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text("タッチしてGoogleMapsで開く")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack {
                    Text("集合時間").font(.headline)
                    Spacer()
                    Text(group.meetTime.formatted(date: .omitted, time: .shortened))
                        .font(.title3.bold())
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            Text("あなたの名前は?").font(.headline)
            TextField("名前を入力", text: $name)
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))

            Text("出発予定時刻").font(.headline)
            DatePicker("", selection: $departureTime, in: Date()..., displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .clipped()

            Spacer()

            HStack {
                Spacer()
                Button { join() } label: {
                    if isJoining {
                        ProgressView().frame(width: 220, height: 56)
                    } else {
                        Text("グループに参加")
                            .font(.headline).foregroundColor(.white)
                            .frame(width: 220, height: 56)
                            .background(Capsule().fill(name.isEmpty ? Color.gray : Color.blue))
                    }
                }
                .disabled(name.isEmpty || isJoining)
                Spacer()
            }
        }
        .padding(24)
        .task {
            group = try? await GroupRepository.shared.fetchGroup(groupId)
        }
    }

    private func openInGoogleMaps(_ group: MeetGroup) {
        let lat = group.destination.latitude
        let lng = group.destination.longitude
        // Google Maps app via URL scheme; fall back to web.
        if let url = URL(string: "comgooglemaps://?q=\(lat),\(lng)&zoom=15"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)") {
            UIApplication.shared.open(url)
        }
    }

    private func join() {
        isJoining = true
        Task {
            defer { isJoining = false }
            do {
                try await GroupRepository.shared.joinGroup(groupId, name: name,
                                                          expectedDeparture: departureTime)
                app.screen = .main(groupId: groupId)
            } catch {
                app.errorMessage = error.localizedDescription
            }
        }
    }
}
