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
class ProfileImageCache {
    static let shared = ProfileImageCache()
    
    private var cache: [String: Image] = [:]
    private let maxCacheSize = 100  // Maximum number of images to cache
    private let lock = NSLock()  // Thread-safe access
    
    private init() {}
    
    /// Get cached image for URL (thread-safe)
    func image(for url: String) -> Image? {
        lock.lock()
        defer { lock.unlock() }
        return cache[url]
    }
    
    /// Store image in cache (thread-safe)
    func setImage(_ image: Image, for url: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Simple LRU: remove oldest if cache is full
        if cache.count >= maxCacheSize {
            cache.removeValue(forKey: cache.keys.first ?? "")
        }
        cache[url] = image
    }
    
    /// Clear cache (thread-safe)
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        print("🗑️ Profile image cache cleared")
    }
}
