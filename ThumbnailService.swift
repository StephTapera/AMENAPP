//
//  ThumbnailService.swift
//  AMENAPP
//
//  P0 FIX: Generate thumbnails for feed display (400x400px max)
//  Reduces bandwidth from 4MB full-res to 50KB thumbnails (80x reduction)
//

import Foundation
import UIKit
import CryptoKit

@MainActor
class ThumbnailService {
    static let shared = ThumbnailService()
    
    // Maximum thumbnail size (400x400px is optimal for feeds)
    private let maxThumbnailSize = CGSize(width: 400, height: 400)
    
    // JPEG compression quality (0.7 balances quality vs size)
    private let compressionQuality: CGFloat = 0.7
    
    private init() {}
    
    // MARK: - Thumbnail Generation
    
    /// Generate thumbnail from image data
    /// - Parameter imageData: Original image data
    /// - Returns: Thumbnail image data (JPEG, 50-100KB typical size)
    func generateThumbnail(from imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else {
            print("❌ [THUMBNAIL] Failed to load image from data")
            return nil
        }
        
        // Calculate scale to fit within maxThumbnailSize
        let scale = min(
            maxThumbnailSize.width / image.size.width,
            maxThumbnailSize.height / image.size.height
        )
        
        // If image is already smaller than thumbnail size, just compress it
        if scale >= 1.0 {
            return image.jpegData(compressionQuality: compressionQuality)
        }
        
        // Calculate new size maintaining aspect ratio
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        
        // Render thumbnail using high-quality downsampling
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Compress to JPEG
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: compressionQuality) else {
            print("❌ [THUMBNAIL] Failed to compress thumbnail")
            return nil
        }
        
        let originalSize = imageData.count / 1024 // KB
        let thumbnailSize = thumbnailData.count / 1024 // KB
        let reduction = Double(originalSize) / Double(max(thumbnailSize, 1))
        
        print("✅ [THUMBNAIL] Generated: \(originalSize)KB → \(thumbnailSize)KB (\(String(format: "%.1f", reduction))x reduction)")
        
        return thumbnailData
    }
    
    // MARK: - Image Deduplication
    
    /// Calculate SHA256 hash of image data for deduplication
    /// - Parameter imageData: Image data to hash
    /// - Returns: SHA256 hash string
    func calculateImageHash(_ imageData: Data) -> String {
        let hash = SHA256.hash(data: imageData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Check if image is duplicate based on hash
    /// - Parameters:
    ///   - imageData: Image data to check
    ///   - existingHashes: Set of existing image hashes
    /// - Returns: True if duplicate, false if unique
    func isDuplicate(_ imageData: Data, existingHashes: Set<String>) -> Bool {
        let hash = calculateImageHash(imageData)
        return existingHashes.contains(hash)
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
