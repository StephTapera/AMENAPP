//
//  ImageCompressor.swift
//  AMENAPP
//
//  Image compression and optimization for messaging
//

import UIKit
import SwiftUI
import Combine

struct ImageCompressor {
    
    // MARK: - Main Compression
    
    /// Compress an image to target size with max dimensions
    /// - Parameters:
    ///   - image: The image to compress
    ///   - maxSizeMB: Maximum file size in megabytes (default 1MB)
    ///   - maxDimension: Maximum width or height in pixels (default 1920)
    /// - Returns: Compressed image data
    static func compress(_ image: UIImage, maxSizeMB: Double = 1.0, maxDimension: CGFloat = 1920) -> Data? {
        // Resize if needed
        let resized = resize(image, maxDimension: maxDimension)
        
        // Compress to target size
        var compression: CGFloat = 0.9
        var imageData = resized.jpegData(compressionQuality: compression)
        
        let maxBytes = Int(maxSizeMB * 1024 * 1024)
        
        // Reduce quality until under size limit
        while let data = imageData, data.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = resized.jpegData(compressionQuality: compression)
        }
        
        return imageData
    }
    
    // MARK: - Resize
    
    /// Resize image to fit within max dimension while maintaining aspect ratio
    /// - Parameters:
    ///   - image: Image to resize
    ///   - maxDimension: Maximum width or height
    /// - Returns: Resized image
    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        // Check if resizing needed
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        // Render resized image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate a thumbnail from an image
    /// - Parameters:
    ///   - image: Source image
    ///   - size: Desired thumbnail size (default 200x200)
    /// - Returns: Thumbnail image
    static func generateThumbnail(_ image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let dimension = max(size.width, size.height)
        return resize(image, maxDimension: dimension)
    }
    
    // MARK: - Batch Processing
    
    /// Compress multiple images
    /// - Parameters:
    ///   - images: Array of images to compress
    ///   - maxSizeMB: Maximum file size per image
    ///   - maxDimension: Maximum dimension per image
    /// - Returns: Array of compressed image data
    static func compressMultiple(_ images: [UIImage], maxSizeMB: Double = 1.0, maxDimension: CGFloat = 1920) -> [Data] {
        return images.compactMap { compress($0, maxSizeMB: maxSizeMB, maxDimension: maxDimension) }
    }
    
    // MARK: - Format Conversion
    
    /// Convert image to PNG data
    /// - Parameter image: Image to convert
    /// - Returns: PNG data
    static func toPNG(_ image: UIImage) -> Data? {
        return image.pngData()
    }
    
    /// Convert image to JPEG with quality
    /// - Parameters:
    ///   - image: Image to convert
    ///   - quality: JPEG quality (0.0 to 1.0)
    /// - Returns: JPEG data
    static func toJPEG(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
        return image.jpegData(compressionQuality: quality)
    }
    
    // MARK: - Size Estimation
    
    /// Estimate the file size of an image
    /// - Parameter image: Image to estimate
    /// - Returns: Estimated size in bytes
    static func estimateSize(_ image: UIImage) -> Int {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            return 0
        }
        return data.count
    }
    
    /// Check if image needs compression
    /// - Parameters:
    ///   - image: Image to check
    ///   - maxSizeMB: Maximum allowed size
    /// - Returns: True if compression needed
    static func needsCompression(_ image: UIImage, maxSizeMB: Double = 1.0) -> Bool {
        let sizeInBytes = estimateSize(image)
        let maxBytes = Int(maxSizeMB * 1024 * 1024)
        return sizeInBytes > maxBytes
    }
}

// MARK: - SwiftUI Extensions

extension Image {
    /// Initialize from compressed image data
    init?(compressedData: Data) {
        guard let uiImage = UIImage(data: compressedData) else {
            return nil
        }
        self = Image(uiImage: uiImage)
    }
}

extension UIImage {
    /// Get compressed version of this image
    func compressed(maxSizeMB: Double = 1.0, maxDimension: CGFloat = 1920) -> Data? {
        return ImageCompressor.compress(self, maxSizeMB: maxSizeMB, maxDimension: maxDimension)
    }
    
    /// Get thumbnail of this image
    func thumbnail(size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        return ImageCompressor.generateThumbnail(self, size: size)
    }
    
    /// Get size in megabytes
    var sizeInMB: Double {
        let bytes = ImageCompressor.estimateSize(self)
        return Double(bytes) / (1024 * 1024)
    }
}

// MARK: - Progress Tracking

class ImageCompressionProgress: ObservableObject {
    @Published var currentImage: Int = 0
    @Published var totalImages: Int = 0
    @Published var isCompressing: Bool = false
    
    var progress: Double {
        guard totalImages > 0 else { return 0 }
        return Double(currentImage) / Double(totalImages)
    }
}

// MARK: - Async Compression

extension ImageCompressor {
    /// Compress image asynchronously
    static func compressAsync(_ image: UIImage, maxSizeMB: Double = 1.0, maxDimension: CGFloat = 1920) async -> Data? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let compressed = compress(image, maxSizeMB: maxSizeMB, maxDimension: maxDimension)
                continuation.resume(returning: compressed)
            }
        }
    }
    
    /// Compress multiple images asynchronously with progress
    static func compressMultipleAsync(
        _ images: [UIImage],
        maxSizeMB: Double = 1.0,
        maxDimension: CGFloat = 1920,
        progress: ImageCompressionProgress? = nil
    ) async -> [Data] {
        await MainActor.run {
            progress?.totalImages = images.count
            progress?.currentImage = 0
            progress?.isCompressing = true
        }
        
        var compressedData: [Data] = []
        
        for (index, image) in images.enumerated() {
            if let data = await compressAsync(image, maxSizeMB: maxSizeMB, maxDimension: maxDimension) {
                compressedData.append(data)
            }
            
            await MainActor.run {
                progress?.currentImage = index + 1
            }
        }
        
        await MainActor.run {
            progress?.isCompressing = false
        }
        
        return compressedData
    }
}
