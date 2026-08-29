import SwiftUI

/// Artwork caching for the grids.
///
/// kvf.fo sends ETag and Last-Modified but no Cache-Control, so URLSession has no
/// freshness lifetime to work from and revalidates every image on every launch —
/// which is why tiles visibly reloaded. Programme artwork does not change under a
/// given URL, so cached bytes are used outright when present.
actor ImageLoader {
    static let shared = ImageLoader()

    private let decoded = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        // Bounded by bytes rather than count, so a few large images cannot squeeze
        // out the rest of the grid.
        decoded.totalCostLimit = 64 << 20
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = decoded.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }

        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            // Bytes on disk win over a round trip: the artwork behind a URL is fixed.
            request.cachePolicy = .returnCacheDataElseLoad

            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let image = UIImage(data: data)
            else { return nil }

            decoded.setObject(image, forKey: url as NSURL, cost: data.count)
            return image
        }

        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }
}

/// Drop-in for AsyncImage that goes through ImageLoader.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await ImageLoader.shared.image(for: url)
        }
    }
}
