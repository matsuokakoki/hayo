import SwiftUI

// ⑦ SNAP: mission icons strip (green dot = active/unread, blue check = cleared),
// photo feed, free-shot camera button.
struct SnapView: View {
    @ObservedObject private var repo = GroupRepository.shared
    let groupId: String
    let onOpenCamera: (CameraPurpose) -> Void
    @Binding var seenPhotoIds: Set<String>

    @State private var detailPhoto: SharedPhoto?
    @State private var missionDetail: Mission?

    private var visibleMissions: [Mission] {
        repo.missions.filter { $0.isPublished }
    }

    private var feedPhotos: [SharedPhoto] {
        repo.photos.filter { $0.photoType != "arrival" }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Missions strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(visibleMissions) { mission in
                        MissionChip(mission: mission,
                                    cleared: repo.cleared(mission: mission)) {
                            if mission.isActive && !repo.cleared(mission: mission) {
                                // Still open: shoot the mission photo.
                                onOpenCamera(.mission(mission))
                            } else {
                                // Cleared (or expired): browse everyone's cleared photos.
                                missionDetail = mission
                            }
                        }
                    }
                    if visibleMissions.isEmpty {
                        Text("ミッションはまだありません")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            // Mission gallery: cleared photos for the tapped mission.
            .fullScreenCover(item: $missionDetail) { mission in
                PhotoDetailView(groupId: groupId,
                                photos: repo.photos.filter {
                                    $0.missionId == mission.id && $0.isCleared
                                },
                                initialPhotoId: nil)
            }

            Divider()

            // Photo feed
            if feedPhotos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("Photo Share").font(.headline)
                    Text("写真を撮って自由にシェアしよう")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                        ForEach(feedPhotos) { photo in
                            PhotoThumb(photo: photo)
                                .onTapGesture { detailPhoto = photo }
                                .onAppear {
                                    if let id = photo.id { seenPhotoIds.insert(id) }
                                }
                        }
                    }
                    .padding(4)
                }
            }

            // SNAP camera button
            Button {
                onOpenCamera(.snap)
            } label: {
                ZStack {
                    Circle().fill(Color.blue).frame(width: 64, height: 64)
                    Image(systemName: "camera.fill")
                        .font(.title2).foregroundColor(.white)
                }
            }
            .padding(.vertical, 10)
        }
        .fullScreenCover(item: $detailPhoto) { photo in
            PhotoDetailView(groupId: groupId,
                            photos: feedPhotos,
                            initialPhotoId: photo.id)
        }
    }
}

struct MissionChip: View {
    @ObservedObject private var repo = GroupRepository.shared
    let mission: Mission
    let cleared: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(mission.title)
                                    .font(.system(size: 9))
                                    .multilineTextAlignment(.center)
                                    .padding(6)
                            )
                        if cleared {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .background(Circle().fill(Color.white))
                        }
                    }
                    Text(mission.isActive ? "残り\(max(0, Int(mission.expiresAt.timeIntervalSinceNow)))秒" : " ")
                        .font(.system(size: 9)).foregroundColor(.red)
                }
                // Green dot = active and not yet cleared (unread).
                if mission.isActive && !cleared {
                    Circle().fill(Color.green).frame(width: 14, height: 14)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PhotoThumb: View {
    let photo: SharedPhoto

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Prefer the small thumbnail; old posts fall back to the full image.
            CachedImage(urlString: photo.thumbUrl ?? photo.imageUrl, targetPoints: 160) {
                Color(.systemGray5)
            }
            .frame(minWidth: 110, minHeight: 110)
            .aspectRatio(1, contentMode: .fill)
            .clipped()

            if photo.isCleared {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .background(Circle().fill(Color.white))
                    .padding(4)
            }
        }
    }
}
