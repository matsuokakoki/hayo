import SwiftUI

// ⑫ Preview & caption: confirm shot, add band caption, discard, upload.
struct PhotoPreviewView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var repo = GroupRepository.shared

    let groupId: String
    let purpose: CameraPurpose
    let image: UIImage
    let onRetake: () -> Void
    let onDone: () -> Void

    @State private var caption = ""
    @State private var editingCaption = false
    @State private var isUploading = false
    @FocusState private var captionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(purpose.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))

                // Caption band overlay
                if editingCaption || !caption.isEmpty {
                    VStack {
                        Spacer().frame(height: 60)
                        TextField("キャプションを入力", text: $caption)
                            .focused($captionFocused)
                            .multilineTextAlignment(.center)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.55))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, purpose.isCircular ? 40 : 12)

            Spacer()

            HStack {
                // Discard / retake
                Button {
                    onRetake()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title2).foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }

                Spacer()

                // Upload
                Button { upload() } label: {
                    if isUploading {
                        ProgressView().tint(.white).frame(width: 80, height: 80)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "paperplane.fill").font(.title2)
                            Text(uploadLabel).font(.caption2.bold())
                        }
                        .foregroundColor(.black)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(Color.white))
                    }
                }
                .disabled(isUploading)

                Spacer()

                // Create caption (not for departure icon)
                Button {
                    editingCaption = true
                    captionFocused = true
                } label: {
                    Image(systemName: "textformat")
                        .font(.title2).foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }
                .opacity(purpose.isCircular ? 0 : 1)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private var uploadLabel: String {
        switch purpose {
        case .departure: return "出発！"
        case .arrival: return "到着！"
        default: return "送信"
        }
    }

    private func upload() {
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                switch purpose {
                case .departure:
                    let url = try await StorageService.uploadImage(image, groupId: groupId, folder: "icons")
                    try await repo.markDeparted(groupId: groupId, iconUrl: url)
                case .arrival:
                    let url = try await StorageService.uploadImage(image, groupId: groupId, folder: "arrivals")
                    try await repo.postPhoto(groupId: groupId, imageUrl: url,
                                             caption: caption, purpose: .arrival)
                    try await repo.markArrived(groupId: groupId)
                case .mission, .snap:
                    let url = try await StorageService.uploadImage(image, groupId: groupId, folder: "photos")
                    try await repo.postPhoto(groupId: groupId, imageUrl: url,
                                             caption: caption, purpose: purpose)
                }
                onDone()
            } catch {
                app.errorMessage = "アップロードに失敗しました: \(error.localizedDescription)"
            }
        }
    }
}
