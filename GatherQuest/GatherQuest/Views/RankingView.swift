import SwiftUI

// ⑩ Arrival ranking: order, time diff vs meet time, mission badges,
// 終了 (immediate dissolve) + arrival photos.
struct RankingView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var repo = GroupRepository.shared
    let groupId: String

    @State private var showArrivalPhotos = false

    private var arrivalPhotos: [SharedPhoto] {
        repo.photos.filter { $0.photoType == "arrival" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(repo.group?.name ?? "")
                .font(.title2.bold())
                .padding(.top, 8)

            Text("到着ランキング")
                .font(.largeTitle.weight(.heavy))
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(repo.ranking()) { entry in
                        HStack(spacing: 14) {
                            Text("\(entry.rank).")
                                .font(.title2.bold())
                                .frame(width: 40, alignment: .leading)

                            UserIconView(urlString: entry.member.iconUrl, size: 52)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.member.name).font(.subheadline.bold())
                                Text(entry.diffLabel)
                                    .font(.headline.monospacedDigit())
                                    .foregroundColor(entry.diffSeconds <= 0 ? .blue : .red)
                            }

                            Spacer()

                            ClearBadges(cleared: entry.clearedCount, total: entry.totalMissions)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }

            Text("全員集合10分後にグループは自動解散します")
                .font(.caption).foregroundColor(.secondary)
                .padding(.bottom, 8)

            HStack(spacing: 20) {
                Button {
                    // Immediate dissolve for this device; server cleanup deletes data.
                    repo.stopListening()
                    LocationService.shared.stop()
                    app.reset()
                } label: {
                    Text("終了")
                        .font(.headline).foregroundColor(.white)
                        .frame(width: 180, height: 54)
                        .background(Capsule().fill(Color.blue))
                }

                Button { showArrivalPhotos = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "photo.stack")
                        Text("到着写真").font(.caption2)
                    }
                    .foregroundColor(.primary)
                    .frame(width: 76, height: 54)
                    .background(Capsule().fill(Color(.systemGray5)))
                }
            }
            .padding(.bottom, 20)
        }
        .fullScreenCover(isPresented: $showArrivalPhotos) {
            PhotoDetailView(groupId: groupId, photos: arrivalPhotos, initialPhotoId: nil)
        }
    }
}
