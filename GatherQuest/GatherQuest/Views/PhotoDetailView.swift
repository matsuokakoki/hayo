import SwiftUI

// ⑧ Photo detail: swipe left/right, caption band, いいね / はよ reactions.
struct PhotoDetailView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var repo = GroupRepository.shared

    let groupId: String
    let photos: [SharedPhoto]
    let initialPhotoId: String?

    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            if photos.isEmpty {
                Spacer()
                Text("写真はまだありません")
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            } else {
                TabView(selection: $index) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, photo in
                        PhotoDetailPage(groupId: groupId, photo: photo)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        // Always dark, in both appearances — keeps attention on the photo.
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            if let initialPhotoId,
               let i = photos.firstIndex(where: { $0.id == initialPhotoId }) {
                index = i
            }
        }
    }
}

struct PhotoDetailPage: View {
    @ObservedObject private var repo = GroupRepository.shared
    let groupId: String
    let photo: SharedPhoto

    private var author: Member? {
        repo.members.first { $0.id == photo.userId }
    }

    private var missionTitle: String? {
        guard let missionId = photo.missionId else { return nil }
        return repo.missions.first { $0.id == missionId }?.title
    }

    var body: some View {
        ZStack {
            CachedImage(urlString: photo.imageUrl) {
                ProgressView().tint(.white)
            }
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            VStack {
                // Mission band (blue) if this was a mission photo
                if let missionTitle {
                    Text("Mission: \(missionTitle)")
                        .font(.caption.bold()).foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.75))
                }

                // Caption band
                if !photo.caption.isEmpty {
                    Text(photo.caption)
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55))
                        .padding(.top, 24)
                }

                Spacer()

                // Author + reactions
                HStack(spacing: 12) {
                    UserIconView(urlString: author?.iconUrl, size: 40)
                    Text(author?.name ?? "？")
                        .font(.subheadline.bold()).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                    Spacer()
                    reactionButton("👍", count: photo.likeCount ?? 0, field: "likeCount")
                    reactionButton("はよ", count: photo.hayoReactionCount ?? 0, field: "hayoReactionCount")
                }
                .padding(16)
            }
        }
    }

    private func reactionButton(_ label: String, count: Int, field: String) -> some View {
        let uid = repo.myUserId ?? ""
        let reacted = (field == "likeCount" ? photo.likedBy : photo.hayoBy)?
            .contains(uid) ?? false
        return Button {
            Task { try? await repo.react(groupId: groupId, photo: photo, field: field) }
        } label: {
            VStack(spacing: 0) {
                Text(label).font(.headline)
                if count > 0 {
                    Text("\(count)").font(.caption2.bold()).foregroundColor(.white)
                }
            }
            .frame(width: 54, height: 54)
            .background(Circle().fill(reacted ? Color.blue.opacity(0.7) : Color.white.opacity(0.25)))
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
        .disabled(reacted)
    }
}
