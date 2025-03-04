import SwiftUI
import Photos

class PhotoPreloader: ObservableObject {
    @Published var preloadedPhotos: [UUID: UIImage] = [:]
    private var preloadQueue: DispatchQueue
    private var targetSize = CGSize(width: 600, height: 900)
    private var preloadCount = 10
    private var assets: PHFetchResult<PHAsset>?
    private var usedIndices = Set<Int>()

    init() {
        self.preloadQueue = DispatchQueue(label: "co.lessthan3.bubbles.photopreloader", qos: .utility)
    }

    func setAssets(_ assets: PHFetchResult<PHAsset>) {
        self.assets = assets
        preloadRandomPhotos()
    }

    func preloadRandomPhotos() {
        guard let assets = assets, assets.count > 0 else { return }

        preloadQueue.async { [weak self] in
            guard let self = self else { return }

            // Reset used indices if we're close to using all photos
            if Double(self.usedIndices.count) > Double(assets.count) * 0.7 {
                self.usedIndices.removeAll()
            }

            // Preload a batch of images
            var newPhotos: [UUID: UIImage] = [:]
            for _ in 0..<self.preloadCount {
                let randomIndex = self.getRandomUnusedIndex(maxIndex: assets.count - 1)
                let asset = assets.object(at: randomIndex)

                // Add to used set
                self.usedIndices.insert(randomIndex)

                // Create a photo ID
                let photoId = UUID()

                // Fetch the image
                self.fetchImage(for: asset) { image in
                    if let image = image {
                        newPhotos[photoId] = image

                        // Update main thread when we have a reasonable batch
                        if newPhotos.count == self.preloadCount / 2 {
                            DispatchQueue.main.async {
                                self.preloadedPhotos.merge(newPhotos) { _, new in new }
                            }
                        }
                    }
                }
            }

            // Update one more time to catch any remaining
            DispatchQueue.main.async {
                self.preloadedPhotos.merge(newPhotos) { _, new in new }
            }
        }
    }

    private func getRandomUnusedIndex(maxIndex: Int) -> Int {
        var randomIndex: Int
        var attempts = 0

        // Try to find an unused index
        repeat {
            randomIndex = Int.random(in: 0...maxIndex)
            attempts += 1
            // After several attempts, just use any index
            if attempts > 10 {
                break
            }
        } while usedIndices.contains(randomIndex)

        return randomIndex
    }

    func fetchImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(for: asset,
                                  targetSize: targetSize,
                                  contentMode: .aspectFill,
                                  options: options) { image, info in
            let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
            if !isDegraded {
                completion(image)
            }
        }
    }

    func getNextPhoto() -> (UUID, UIImage)? {
        guard !preloadedPhotos.isEmpty else { return nil }

        // Take the first available image
        let randomPhotoEntry = preloadedPhotos.first!

        // Remove it from the preloaded set
        preloadedPhotos.removeValue(forKey: randomPhotoEntry.key)

        // Start preloading more when we get low
        if preloadedPhotos.count < preloadCount / 2 {
            preloadRandomPhotos()
        }

        return (randomPhotoEntry.key, randomPhotoEntry.value)
    }
}
