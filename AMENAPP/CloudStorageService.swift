//
//  CloudStorageService.swift
//  AMENAPP
//
//  Cloud Storage service for uploading post media files
//

import Foundation
import FirebaseStorage
import UIKit

enum MediaType {
    case image
    case video
    case audio
    
    var folder: String {
        switch self {
        case .image: return "images"
        case .video: return "videos"
        case .audio: return "audio"
        }
    }
}

class CloudStorageService {
    static let shared = CloudStorageService()
    private lazy var storage = Storage.storage()

    // P2-7: Retained so uploads can be cancelled mid-flight.
    private var currentUploadTask: StorageUploadTask?

    private init() {}

    /// Cancels the in-flight upload, if any.
    func cancelUpload() {
        currentUploadTask?.cancel()
        currentUploadTask = nil
    }
    
    /// Upload media file to Cloud Storage
    /// - Parameters:
    ///   - data: Media file data
    ///   - type: Type of media (image/video/audio)
    ///   - userId: User ID for organizing files
    /// - Returns: Public URL of uploaded file
    func uploadMedia(
        data: Data,
        type: MediaType,
        userId: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        
        let fileName = "\(UUID().uuidString).\(type.fileExtension)"
        let path = "posts/\(userId)/\(type.folder)/\(fileName)"
        
        dlog("📤 [CLOUD STORAGE] Uploading \(type.folder) to: \(path)")
        
        let storageRef = storage.reference().child(path)
        
        // Set metadata for better performance
        let metadata = StorageMetadata()
        metadata.contentType = type.contentType
        metadata.cacheControl = "public, max-age=31536000" // Cache for 1 year
        
        // P2-8: Reject files that exceed the 25MB upload limit.
        let maxSizeBytes: Int = 25 * 1024 * 1024
        if data.count > maxSizeBytes {
            throw NSError(
                domain: "CloudStorageService",
                code: 413,
                userInfo: [NSLocalizedDescriptionKey: "File size exceeds 25MB limit."]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = storageRef.putData(data, metadata: metadata)
            // P2-7: Retain the task so callers can cancel via cancelUpload().
            currentUploadTask = uploadTask
            
            // Track upload progress
            uploadTask.observe(.progress) { snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                progressHandler?(percentComplete)
                dlog("📊 Upload progress: \(Int(percentComplete * 100))%")
            }
            
            // Handle completion
            uploadTask.observe(.success) { [weak self] _ in
                self?.currentUploadTask = nil
                storageRef.downloadURL { url, error in
                    if let error = error {
                        dlog("❌ [CLOUD STORAGE] Failed to get download URL: \(error)")
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let downloadURL = url?.absoluteString else {
                        let error = NSError(domain: "CloudStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No download URL"])
                        continuation.resume(throwing: error)
                        return
                    }

                    dlog("✅ [CLOUD STORAGE] Upload successful: \(downloadURL)")
                    continuation.resume(returning: downloadURL)
                }
            }

            uploadTask.observe(.failure) { [weak self] snapshot in
                self?.currentUploadTask = nil
                if let error = snapshot.error {
                    dlog("❌ [CLOUD STORAGE] Upload failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Upload image with compression.
    /// Uses ImageCompressor: resizes to ≤1920px then compresses to ≤1MB JPEG.
    /// Raw 5MB+ phone photos become ~300–500KB — critical for storage cost control.
    func uploadImage(
        image: UIImage,
        userId: String,
        compressionQuality: CGFloat = 0.75,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        // ✅ FIX: Run dimension resize (max 1920px) + quality compression before upload.
        // Previously only jpegData(compressionQuality:) was called — no resize.
        // A 4032×3024 photo at quality 0.7 is still ~3MB.
        guard let imageData = await ImageCompressor.compressAsync(
            image,
            maxSizeMB: 1.0,
            maxDimension: 1920
        ) else {
            throw NSError(domain: "CloudStorage", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
        }

        return try await uploadMedia(
            data: imageData,
            type: .image,
            userId: userId,
            progressHandler: progressHandler
        )
    }
    
    /// Delete media file from Cloud Storage
    func deleteMedia(url: String) async throws {
        guard let storageRef = Storage.storage().reference(forURL: url) as StorageReference? else {
            throw NSError(domain: "CloudStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        try await storageRef.delete()
        dlog("✅ [CLOUD STORAGE] File deleted: \(url)")
    }
    
    /// Get file size from Cloud Storage
    func getFileSize(url: String) async throws -> Int64 {
        guard let storageRef = Storage.storage().reference(forURL: url) as StorageReference? else {
            throw NSError(domain: "CloudStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let metadata = try await storageRef.getMetadata()
        return metadata.size
    }
}

// MARK: - Media Type Extensions

extension MediaType {
    var fileExtension: String {
        switch self {
        case .image: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        }
    }
    
    var contentType: String {
        switch self {
        case .image: return "image/jpeg"
        case .video: return "video/mp4"
        case .audio: return "audio/mp4"
        }
    }
}
