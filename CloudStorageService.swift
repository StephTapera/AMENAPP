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
    private let storage = Storage.storage()
    
    private init() {}
    
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
        
        print("📤 [CLOUD STORAGE] Uploading \(type.folder) to: \(path)")
        
        let storageRef = storage.reference().child(path)
        
        // Set metadata for better performance
        let metadata = StorageMetadata()
        metadata.contentType = type.contentType
        metadata.cacheControl = "public, max-age=31536000" // Cache for 1 year
        
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = storageRef.putData(data, metadata: metadata)
            
            // Track upload progress
            uploadTask.observe(.progress) { snapshot in
                guard let progress = snapshot.progress else { return }
                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                progressHandler?(percentComplete)
                print("📊 Upload progress: \(Int(percentComplete * 100))%")
            }
            
            // Handle completion
            uploadTask.observe(.success) { _ in
                storageRef.downloadURL { url, error in
                    if let error = error {
                        print("❌ [CLOUD STORAGE] Failed to get download URL: \(error)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let downloadURL = url?.absoluteString else {
                        let error = NSError(domain: "CloudStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "No download URL"])
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    print("✅ [CLOUD STORAGE] Upload successful: \(downloadURL)")
                    continuation.resume(returning: downloadURL)
                }
            }
            
            uploadTask.observe(.failure) { snapshot in
                if let error = snapshot.error {
                    print("❌ [CLOUD STORAGE] Upload failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Upload image with compression
    func uploadImage(
        image: UIImage,
        userId: String,
        compressionQuality: CGFloat = 0.7,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            throw NSError(domain: "CloudStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
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
        print("✅ [CLOUD STORAGE] File deleted: \(url)")
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
