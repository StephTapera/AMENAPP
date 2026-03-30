//
//  ProfileImageCache.swift
//  AMENAPP
//
//  Created by Steph on 1/26/26.
//
//  Simple in-memory cache for profile images to speed up loading
//

import Foundation
import SwiftUI
import UIKit

/// In-memory cache for profile images backed by NSCache for automatic memory-pressure eviction.
class ProfileImageCache {
    static let shared = ProfileImageCache()

    // NSCache is thread-safe and automatically evicts entries under memory pressure.
    // We wrap SwiftUI Image in a trivial box because NSCache requires AnyObject values.
    private final class ImageBox {
        let image: Image
        init(_ image: Image) { self.image = image }
    }

    private let cache = NSCache<NSString, ImageBox>()

    private init() {
        cache.countLimit = 150  // max 150 profile images
        // Register for memory warnings so the cache is cleared immediately
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
    }

    /// Get cached image for URL.
    func image(for url: String) -> Image? {
        cache.object(forKey: url as NSString)?.image
    }

    /// Store image in cache.
    func setImage(_ image: Image, for url: String) {
        cache.setObject(ImageBox(image), forKey: url as NSString)
    }

    /// Clear all cached images.
    func clearCache() {
        cache.removeAllObjects()
    }
}
