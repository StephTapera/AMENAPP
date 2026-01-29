//
//  ProfilePhotoService.swift
//  AMENAPP
//
//  Created by Assistant on 1/26/26.
//
//  Service for uploading profile photos to Firebase Storage
//

import Foundation
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import UIKit
import SwiftUI
import Combine

@MainActor
class ProfilePhotoService: ObservableObject {
    static let shared = ProfilePhotoService()
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var error: String?
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared
    
    private init() {}
    
    // MARK: - Upload Profile Photo
    
    /// Upload a profile photo and update user document
    func uploadProfilePhoto(image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        print("\n🚀 === PROFILE PHOTO UPLOAD STARTED ===")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("❌ ERROR: User not authenticated!")
            print("   - firebaseManager.currentUser: \(String(describing: firebaseManager.currentUser))")
            completion(.failure(NSError(domain: "ProfilePhotoService", code: -1, 
                                       userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        print("✅ User authenticated")
        print("   - User ID: \(currentUserId)")
        print("   - Image size: \(image.size.width) x \(image.size.height)")
        
        // Compress image
        guard let imageData = compressImage(image) else {
            print("❌ ERROR: Failed to compress image")
            completion(.failure(NSError(domain: "ProfilePhotoService", code: -2,
                                       userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])))
            return
        }
        
        print("✅ Image compressed successfully")
        print("   - Compressed size: \(imageData.count / 1024)KB")
        print("   - Max allowed: 10240KB (10MB)")
        
        isUploading = true
        uploadProgress = 0.0
        error = nil
        
        // Create storage reference
        let fileName = "profile.jpg"
        let storageRef = storage.reference()
            .child("profile_images")
            .child(currentUserId)
            .child(fileName)
        
        print("📂 Storage path: \(storageRef.fullPath)")
        print("   - Bucket: \(storageRef.bucket)")
        print("   - Full URL: gs://\(storageRef.bucket)/\(storageRef.fullPath)")
        
        // Set metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        print("📤 Starting upload...")
        print("   - Content type: image/jpeg")
        print("   - Metadata: \(metadata)")
        
        // Upload with progress tracking
        let uploadTask = storageRef.putData(imageData, metadata: metadata)
        
        // Observe progress
        uploadTask.observe(.progress) { [weak self] snapshot in
            guard let self = self,
                  let progress = snapshot.progress else { return }
            
            Task { @MainActor in
                self.uploadProgress = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                print("📤 Upload progress: \(Int(self.uploadProgress * 100))%")
            }
        }
        
        // Handle completion
        uploadTask.observe(.success) { [weak self] snapshot in
            guard let self = self else { return }
            
            print("✅ Upload completed successfully!")
            print("   - Snapshot: \(snapshot)")
            
            Task { @MainActor in
                do {
                    print("📥 Getting download URL...")
                    
                    // Get download URL
                    let downloadURL = try await storageRef.downloadURL()
                    let urlString = downloadURL.absoluteString
                    
                    print("✅ Download URL retrieved: \(urlString)")
                    
                    // Update user document
                    print("💾 Updating Firestore user document...")
                    try await self.updateUserProfilePhoto(userId: currentUserId, photoURL: urlString)
                    
                    self.isUploading = false
                    self.uploadProgress = 1.0
                    
                    print("✅ Profile photo uploaded: \(urlString)")
                    print("=== UPLOAD COMPLETED SUCCESSFULLY ===\n")
                    completion(.success(urlString))
                    
                } catch {
                    self.isUploading = false
                    self.error = error.localizedDescription
                    print("❌ Error after upload: \(error)")
                    print("   - Failed at: Getting URL or updating Firestore")
                    completion(.failure(error))
                }
            }
        }
        
        // Handle failure
        uploadTask.observe(.failure) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.isUploading = false
                
                if let error = snapshot.error {
                    self.error = error.localizedDescription
                    
                    print("\n❌ === UPLOAD FAILED ===")
                    print("   - Error: \(error)")
                    print("   - Error code: \((error as NSError).code)")
                    print("   - Error domain: \((error as NSError).domain)")
                    print("   - Localized description: \(error.localizedDescription)")
                    
                    // Check for specific Firebase Storage errors
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" {
                        switch nsError.code {
                        case -13021:
                            print("   - ERROR TYPE: Quota exceeded")
                        case -13010:
                            print("   - ERROR TYPE: Object not found")
                        case -13015:
                            print("   - ERROR TYPE: Bucket not found")
                        case -13020:
                            print("   - ERROR TYPE: Project not found")
                        case -13030:
                            print("   - ERROR TYPE: Retry limit exceeded")
                        case -13040:
                            print("   - ERROR TYPE: Invalid checksum")
                        case -13000:
                            print("   - ERROR TYPE: Unknown error")
                        case -13002:
                            print("   - ERROR TYPE: Object size mismatch")
                        case -13012:
                            print("   - ERROR TYPE: Download size exceeded")
                        case -13016:
                            print("   - ERROR TYPE: Unauthorized - CHECK YOUR STORAGE RULES!")
                            print("   - HINT: User \(currentUserId) doesn't have permission")
                            print("   - Path: profile_images/\(currentUserId)/profile.jpg")
                        default:
                            print("   - ERROR TYPE: Other Firebase Storage error (code: \(nsError.code))")
                        }
                    }
                    
                    print("=== END UPLOAD FAILED ===\n")
                    completion(.failure(error))
                } else {
                    print("❌ Upload failed with no error information")
                }
            }
        }
    }
    
    // MARK: - Async/Await Version
    
    /// Upload profile photo using async/await
    func uploadProfilePhoto(image: UIImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            uploadProfilePhoto(image: image) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - Delete Profile Photo
    
    /// Delete current profile photo
    func deleteProfilePhoto() async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "ProfilePhotoService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Delete all photos in user's folder
        let storageRef = storage.reference()
            .child("profile_images")
            .child(currentUserId)
        
        do {
            let result = try await storageRef.listAll()
            
            for item in result.items {
                try await item.delete()
                print("✅ Deleted photo: \(item.name)")
            }
            
            // Remove photoURL from user document
            try await updateUserProfilePhoto(userId: currentUserId, photoURL: nil)
            
            print("✅ Profile photo deleted")
            
        } catch {
            print("❌ Error deleting profile photo: \(error)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    /// Update user document with new photo URL
    private func updateUserProfilePhoto(userId: String, photoURL: String?) async throws {
        let updateData: [String: Any]
        
        if let photoURL = photoURL {
            updateData = [
                "profileImageURL": photoURL,
                "updatedAt": Date()
            ]
        } else {
            updateData = [
                "profileImageURL": FieldValue.delete(),
                "updatedAt": Date()
            ]
        }
        
        try await db.collection("users").document(userId).updateData(updateData)
        
        print("✅ Updated user profile photo URL")
    }
    
    /// Compress image to reduce file size
    private func compressImage(_ image: UIImage) -> Data? {
        let maxWidth: CGFloat = 800
        let maxHeight: CGFloat = 800
        
        var actualWidth = image.size.width
        var actualHeight = image.size.height
        var imgRatio = actualWidth / actualHeight
        let maxRatio = maxWidth / maxHeight
        
        // Resize if needed
        if actualHeight > maxHeight || actualWidth > maxWidth {
            if imgRatio < maxRatio {
                imgRatio = maxHeight / actualHeight
                actualWidth = imgRatio * actualWidth
                actualHeight = maxHeight
            } else if imgRatio > maxRatio {
                imgRatio = maxWidth / actualWidth
                actualHeight = imgRatio * actualHeight
                actualWidth = maxWidth
            } else {
                actualHeight = maxHeight
                actualWidth = maxWidth
            }
        }
        
        let rect = CGRect(x: 0.0, y: 0.0, width: actualWidth, height: actualHeight)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        image.draw(in: rect)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Compress to JPEG with quality
        return img?.jpegData(compressionQuality: 0.8)
    }
}

