import SwiftUI
import UIKit
import ImageIO

/// Shared image loader with an in-memory cache and on-disk HTTP caching.
///
/// SwiftUI's `AsyncImage` re-downloads and re-decodes every time a view
/// reappears, which is why the SNAP grid and map pins felt slow. This keeps
/// decoded images in memory and lets URLCache serve repeat requests from disk.
actor ImageLoader {
    static let shared = ImageLoader()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        c.totalCostLimit = 80 * 1024 * 1024 // ~80 MB
        return c
    }()

    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// `targetPoints` downsamples at decode time — a 110pt thumbnail never
    /// holds a full-resolution bitmap in memory.
    func image(for urlString: String, targetPoints: CGFloat?) async -> UIImage? {
        let key = cacheKey(urlString, targetPoints)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let url = URL(string: urlString) else { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            let image = Self.decode(data, targetPoints: targetPoints)
            if let image { await self?.store(image, key: key) }
            return image
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func store(_ image: UIImage, key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func cacheKey(_ urlString: String, _ targetPoints: CGFloat?) -> String {
        targetPoints.map { "\(urlString)#\(Int($0))" } ?? urlString
    }

    private static func decode(_ data: Data, targetPoints: CGFloat?) -> UIImage? {
        guard let targetPoints else { return UIImage(data: data) }
        let maxPixels = targetPoints * UIScreen.main.scale
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return UIImage(data: data) }
        return UIImage(cgImage: cgImage)
    }
}

/// Drop-in replacement for `AsyncImage` that uses `ImageLoader`.
struct CachedImage<Placeholder: View>: View {
    let urlString: String?
    var targetPoints: CGFloat? = nil
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: urlString) {
            guard let urlString else { return }
            image = await ImageLoader.shared.image(for: urlString, targetPoints: targetPoints)
        }
    }
}
