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

/// In-memory cache for profile images
@MainActor
class ProfileImageCache {
    static let shared = ProfileImageCache()
    
    private var cache: [String: Image] = [:]
    private let maxCacheSize = 100  // Maximum number of images to cache
    
    private init() {}
    
    /// Get cached image for URL
    func image(for url: String) -> Image? {
        return cache[url]
    }
    
    /// Store image in cache
    func setImage(_ image: Image, for url: String) {
        // Simple LRU: remove oldest if cache is full
        if cache.count >= maxCacheSize {
            cache.removeValue(forKey: cache.keys.first ?? "")
        }
        cache[url] = image
    }
    
    /// Clear cache
    func clearCache() {
        cache.removeAll()
        print("🗑️ Profile image cache cleared")
    }
}
