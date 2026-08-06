import Foundation
import FirebaseStorage
import UIKit

enum StorageService {
    /// Uploads a JPEG under groups/{groupId}/ and returns its download URL.
    static func uploadImage(_ image: UIImage, groupId: String, folder: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.6) else {
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
