//
//  NotificationImageCache.swift
//  AMENAPP
//
//  Created by Claude on 2/9/26.
//
//  Instagram-level image caching for notifications (fast profile photo loads)

import SwiftUI
import Combine

/// High-performance image cache specifically optimized for notification profile photos
/// Loads images as fast as Instagram/Threads
@MainActor
final class NotificationImageCache: ObservableObject {
    
    static let shared = NotificationImageCache()
    
    // MARK: - Cache Storage
    
    /// In-memory cache for instant access (most recent 200 images)
    private var memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200  // Keep 200 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB max
        return cache
    }()
    
    /// Currently loading URLs to prevent duplicate requests
    private var loadingURLs: Set<String> = []
    
    /// Completion handlers waiting for image loads
    private var waitingHandlers: [String: [(UIImage?) -> Void]] = [:]
    
    private init() {
        print("✅ NotificationImageCache initialized")
    }
    
    // MARK: - Load Image
    
    /// Load image from cache or network (Instagram-fast)
    func loadImage(from urlString: String?) async -> UIImage? {
        guard let urlString = urlString, !urlString.isEmpty else {
            return nil
        }
        
        // 1. Check memory cache first (instant)
        if let cached = memoryCache.object(forKey: urlString as NSString) {
            return cached
        }
        
        // 2. Check disk cache (fast)
        if let diskCached = await loadFromDisk(urlString) {
            // Store in memory cache for next time
            memoryCache.setObject(diskCached, forKey: urlString as NSString)
            return diskCached
        }
        
        // 3. Download from network (slower)
        return await downloadImage(from: urlString)
    }
    
    // MARK: - Synchronous Check (for instant display)
    
    /// Check if image is already in memory cache (no async needed)
    func cachedImage(for urlString: String?) -> UIImage? {
        guard let urlString = urlString, !urlString.isEmpty else {
            return nil
        }
        return memoryCache.object(forKey: urlString as NSString)
    }
    
    // MARK: - Disk Cache
    
    private func diskCachePath(for urlString: String) -> URL? {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        // Create notification images subdirectory
        let notificationImagesDir = cacheDir.appendingPathComponent("NotificationImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: notificationImagesDir, withIntermediateDirectories: true)
        
        // Use URL hash as filename
        let filename = urlString.hashValue.description + ".jpg"
        return notificationImagesDir.appendingPathComponent(filename)
    }
    
    private func loadFromDisk(_ urlString: String) async -> UIImage? {
        guard let path = diskCachePath(for: urlString) else {
            return nil
        }
        
        return await Task.detached {
            guard let data = try? Data(contentsOf: path),
                  let image = UIImage(data: data) else {
                return nil
            }
            return image
        }.value
    }
    
    private func saveToDisk(_ image: UIImage, for urlString: String) async {
        guard let path = diskCachePath(for: urlString),
              let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        
        await Task.detached {
            try? data.write(to: path)
        }.value
    }
    
    // MARK: - Network Download
    
    private func downloadImage(from urlString: String) async -> UIImage? {
        // Prevent duplicate requests
        guard !loadingURLs.contains(urlString) else {
            // Wait for existing request
            return await withCheckedContinuation { continuation in
                waitingHandlers[urlString, default: []].append { image in
                    continuation.resume(returning: image)
                }
            }
        }
        
        loadingURLs.insert(urlString)
        
        guard let url = URL(string: urlString) else {
            loadingURLs.remove(urlString)
            notifyWaitingHandlers(for: urlString, with: nil)
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            guard let image = UIImage(data: data) else {
                loadingURLs.remove(urlString)
                notifyWaitingHandlers(for: urlString, with: nil)
                return nil
            }
            
            // Cache in memory
            memoryCache.setObject(image, forKey: urlString as NSString)
            
            // Cache on disk (async, don't wait)
            Task {
                await saveToDisk(image, for: urlString)
            }
            
            loadingURLs.remove(urlString)
            notifyWaitingHandlers(for: urlString, with: image)
            
            return image
            
        } catch {
            print("⚠️ Failed to download notification image: \(error.localizedDescription)")
            loadingURLs.remove(urlString)
            notifyWaitingHandlers(for: urlString, with: nil)
            return nil
        }
    }
    
    private func notifyWaitingHandlers(for urlString: String, with image: UIImage?) {
        let handlers = waitingHandlers[urlString] ?? []
        waitingHandlers[urlString] = nil
        
        for handler in handlers {
            handler(image)
        }
    }
    
    // MARK: - Preload Images (Instagram strategy)
    
    /// Preload images for upcoming notifications (load while user scrolls)
    func preloadImages(for notifications: [AppNotification]) {
        Task {
            for notification in notifications.prefix(20) {  // Preload next 20
                if let urlString = notification.actorProfileImageURL,
                   !urlString.isEmpty,
                   memoryCache.object(forKey: urlString as NSString) == nil {
                    _ = await loadImage(from: urlString)
                }
            }
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear memory cache (useful when memory warning)
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        print("🧹 Cleared notification image memory cache")
    }
    
    /// Clear disk cache (useful for debugging or settings)
    func clearDiskCache() async {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        let notificationImagesDir = cacheDir.appendingPathComponent("NotificationImages", isDirectory: true)
        
        await Task.detached {
            try? FileManager.default.removeItem(at: notificationImagesDir)
        }.value
        
        print("🧹 Cleared notification image disk cache")
    }
    
    /// Get cache size (for settings display)
    func cacheSize() async -> Int64 {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        let notificationImagesDir = cacheDir.appendingPathComponent("NotificationImages", isDirectory: true)
        
        return await Task.detached {
            guard let enumerator = FileManager.default.enumerator(at: notificationImagesDir, includingPropertiesForKeys: [.fileSizeKey]) else {
                return 0
            }
            
            var totalSize: Int64 = 0
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
            return totalSize
        }.value
    }
}

// MARK: - Cached Profile Image View

/// SwiftUI view that displays cached profile image with instant fallback
struct CachedNotificationProfileImage: View {
    let imageURL: String?
    let size: CGFloat
    let fallbackName: String?
    
    @StateObject private var cache = NotificationImageCache.shared
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(imageURL: String?, size: CGFloat = 40, fallbackName: String? = nil) {
        self.imageURL = imageURL
        self.size = size
        self.fallbackName = fallbackName
    }
    
    var body: some View {
        Group {
            if let image = image {
                // Display loaded image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if isLoading {
                // Loading state
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                    )
            } else {
                // Fallback to initials
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.2, blue: 0.5),
                                Color(red: 0.4, green: 0.3, blue: 0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
        }
        .task {
            await loadImage()
        }
        .onChange(of: imageURL) { _ in
            Task {
                await loadImage()
            }
        }
    }
    
    private var initials: String {
        guard let name = fallbackName else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1).uppercased()
            let last = components[1].prefix(1).uppercased()
            return "\(first)\(last)"
        } else if let first = components.first {
            return String(first.prefix(1).uppercased())
        }
        return "?"
    }
    
    private func loadImage() async {
        // 1. Check if already in memory (instant)
        if let cached = cache.cachedImage(for: imageURL) {
            await MainActor.run {
                self.image = cached
            }
            return
        }
        
        // 2. Load from cache or network
        await MainActor.run {
            isLoading = true
        }
        
        let loaded = await cache.loadImage(from: imageURL)
        
        await MainActor.run {
            self.image = loaded
            isLoading = false
        }
    }
}
