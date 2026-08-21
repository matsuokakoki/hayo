import Foundation
import FirebaseStorage
import UIKit

enum StorageService {
    /// Longest-edge limits. A 12MP capture is ~3–5 MB; these keep uploads
    /// (and later downloads) small enough to feel instant.
    enum Preset {
        static let icon = CGFloat(512)    // map pins / avatars, displayed at ~50pt
        static let photo = CGFloat(1440)  // shared photos, displayed full screen
        static let thumb = CGFloat(320)   // SNAP grid cells (~110pt)
    }

    /// Uploads a full-size photo plus a small thumbnail for the grid.
    /// The grid then transfers ~20 KB per photo instead of ~200 KB.
    static func uploadPhotoWithThumbnail(_ image: UIImage,
                                         groupId: String,
                                         folder: String) async throws -> (url: String, thumbUrl: String?) {
        async let full = uploadImage(image, groupId: groupId, folder: folder)
        async let thumb = uploadImage(image, groupId: groupId, folder: "\(folder)/thumbs",
                                      maxDimension: Preset.thumb, quality: 0.6)
        return (try await full, try? await thumb)
    }

    /// Uploads a JPEG under groups/{groupId}/ and returns its download URL.
    static func uploadImage(_ image: UIImage,
                            groupId: String,
                            folder: String,
                            maxDimension: CGFloat? = nil,
                            quality: CGFloat = 0.7) async throws -> String {
        let limit = maxDimension ?? (folder == "icons" ? Preset.icon : Preset.photo)
        let resized = image.resized(maxDimension: limit)
        guard let data = resized.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "StorageService", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "画像の変換に失敗しました"])
        }
        let ref = Storage.storage().reference()
            .child("groups/\(groupId)/\(folder)/\(UUID().uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return try await ref.downloadURL().absoluteString
    }
}

extension UIImage {
    /// Scales down so the longest edge is at most `maxDimension` (never upscales).
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
