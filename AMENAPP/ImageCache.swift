//
//  ImageCache.swift
//  AMENAPP
//
//  High-performance image caching for profile pictures and post images
//  Features: Memory cache, automatic resizing, duplicate request deduplication
//

import UIKit
import SwiftUI

/// Fast, memory-efficient image cache with automatic resizing
@MainActor
class ImageCache {
    static let shared = ImageCache()

    // Memory cache for loaded images
    private let cache = NSCache<NSString, UIImage>()

    // Track in-flight loading tasks to prevent duplicate requests.
    // Key is "url_WxH" so that requests for the same URL at different sizes
    // are not incorrectly coalesced.
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    // Background queue for image resizing
    private let resizeQueue = DispatchQueue(label: "com.amen.imageResize", qos: .userInitiated)

    private init() {
        // Configure cache limits
        cache.countLimit = 150  // Cache up to 150 images
        cache.totalCostLimit = 75 * 1024 * 1024  // 75MB memory limit

        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("⚠️ Memory warning - clearing image cache")
            // Hop to MainActor to satisfy @MainActor isolation on `cache`
            Task { @MainActor [weak self] in
                self?.cache.removeAllObjects()
            }
        }
    }

    /// Load image from URL with caching and automatic resizing
    /// - Parameters:
    ///   - url: Image URL string
    ///   - size: Target size for resizing (2x for retina, e.g., 88x88 for 44pt)
    /// - Returns: Loaded and resized UIImage, or nil if loading fails
    func loadImage(url: String?, size: CGSize) async -> UIImage? {
        guard let url = url, !url.isEmpty else { return nil }

        let taskKey = "\(url)_\(Int(size.width))x\(Int(size.height))"
        let cacheKey = taskKey as NSString

        // Check cache first (instant!)
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Check if already loading this URL at this exact size — share the in-flight task.
        if let existingTask = inFlightTasks[taskKey] {
            return await existingTask.value
        }

        // Load image asynchronously
        let task = Task { () -> UIImage? in
            guard let imageURL = URL(string: url) else { return nil }

            do {
                // Download image data
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                guard let image = UIImage(data: data) else { return nil }

                // Resize on background thread to avoid blocking main thread
                let resized = await Task.detached(priority: .userInitiated) { [weak self] in
                    self?.resize(image: image, to: size)
                }.value

                guard let resized = resized else { return nil }

                // Cache the resized image.
                // Cap the cost estimate to prevent Int overflow on very large images
                // (e.g. 4K: 3840×2160×4 = ~33 MB, safely within Int range, but
                //  pathological inputs like 100K×100K would overflow without the cap).
                await MainActor.run {
                    let rawCost = Double(size.width) * Double(size.height) * 4.0
                    let cost = Int(min(rawCost, Double(self.cache.totalCostLimit > 0 ? self.cache.totalCostLimit : 75 * 1024 * 1024)))
                    self.cache.setObject(resized, forKey: cacheKey, cost: cost)
                }

                return resized
            } catch {
                return nil
            }
        }

        inFlightTasks[taskKey] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: taskKey)

        return result
    }

    /// Preload image into cache without returning it
    /// Useful for preloading images before they're needed
    func preloadImage(url: String?, size: CGSize) {
        Task {
            _ = await loadImage(url: url, size: size)
        }
    }

    /// Clear specific image from cache
    func clearImage(url: String, size: CGSize) {
        let cacheKey = "\(url)_\(Int(size.width))x\(Int(size.height))" as NSString
        cache.removeObject(forKey: cacheKey)
    }

    /// Clear all cached images
    func clearAll() {
        cache.removeAllObjects()
    }

    // MARK: - Private Helpers

    /// Resize image to target size
    nonisolated private func resize(image: UIImage, to size: CGSize) -> UIImage? {
        // Use preparingThumbnail for efficient resizing
        return image.preparingThumbnail(of: size)
    }
}

// Note: CachedAsyncImage already exists in CachedAsyncImage.swift
// Using existing implementation to avoid duplication

// MARK: - Convenience Extensions

extension ImageCache {
    /// Load profile image at standard size (44pt = 88px @2x)
    func loadProfileImage(url: String?) async -> UIImage? {
        await loadImage(url: url, size: CGSize(width: 88, height: 88))
    }

    /// Load post image at standard feed size (full width, 16:9 aspect)
    func loadPostImage(url: String?, width: CGFloat = 375) async -> UIImage? {
        let height = width * 9 / 16
        return await loadImage(url: url, size: CGSize(width: width * 2, height: height * 2))
    }
}
