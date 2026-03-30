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
        dlog("\n🚀 === PROFILE PHOTO UPLOAD STARTED ===")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            dlog("❌ ERROR: User not authenticated!")
            dlog("   - firebaseManager.currentUser: \(String(describing: firebaseManager.currentUser))")
            completion(.failure(NSError(domain: "ProfilePhotoService", code: -1, 
                                       userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        dlog("✅ User authenticated")
        dlog("   - User ID: \(currentUserId)")
        dlog("   - Image size: \(image.size.width) x \(image.size.height)")

        // 🛡️ IMAGE SAFETY PRE-CHECK — runs before any upload to Firebase Storage.
        // Checks: validity, perceptual hash vs known-bad content, on-device heuristics.
        // async/await wrapper so we can use the completion-handler API caller expects.
        Task { @MainActor in
            let safetyDecision = await ProfileImageSafetyGate.shared.evaluate(
                image: image,
                uploaderId: currentUserId,
                context: .profilePhoto
            )
            if safetyDecision.blocksUpload {
                self.isUploading = false
                let reason: String
                switch safetyDecision {
                case .reject(let r):  reason = r
                case .freeze(let r):  reason = "Your account is under review. \(r)"
                default:              reason = "Photo could not be uploaded."
                }
                self.error = reason
                dlog("⛔ [ProfileImageSafetyGate] Upload blocked: \(reason)")
                completion(.failure(NSError(
                    domain: "ProfilePhotoService",
                    code: -20,
                    userInfo: [NSLocalizedDescriptionKey: reason]
                )))
                return
            }
            // Safety check passed — proceed with upload on current task context
            self.performUpload(image: image, userId: currentUserId, pHash: {
                if case .allowWithAsyncScan(let h) = safetyDecision { return h }
                return ""
            }(), completion: completion)
        }
    }

    /// Internal upload method — called after safety gate approves the image.
    private func performUpload(
        image: UIImage,
        userId: String,
        pHash: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Compress image
        guard let imageData = compressImage(image) else {
            dlog("❌ ERROR: Failed to compress image")
            completion(.failure(NSError(domain: "ProfilePhotoService", code: -2,
                                       userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])))
            return
        }
        
        dlog("✅ Image compressed successfully")
        dlog("   - Compressed size: \(imageData.count / 1024)KB")
        dlog("   - Max allowed: 10240KB (10MB)")
        
        isUploading = true
        uploadProgress = 0.0
        error = nil
        
        // Create storage reference
        let fileName = "profile.jpg"
        let storageRef = storage.reference()
            .child("profile_images")
            .child(userId)
            .child(fileName)
        
        dlog("📂 Storage path: \(storageRef.fullPath)")
        dlog("   - Bucket: \(storageRef.bucket)")
        dlog("   - Full URL: gs://\(storageRef.bucket)/\(storageRef.fullPath)")
        
        // Set metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        dlog("📤 Starting upload...")
        dlog("   - Content type: image/jpeg")
        dlog("   - Metadata: \(metadata)")
        
        // Upload with progress tracking
        let uploadTask = storageRef.putData(imageData, metadata: metadata)
        
        // Observe progress
        uploadTask.observe(.progress) { [weak self] snapshot in
            guard let self = self,
                  let progress = snapshot.progress else { return }
            
            Task { @MainActor in
                self.uploadProgress = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                dlog("📤 Upload progress: \(Int(self.uploadProgress * 100))%")
            }
        }
        
        // Handle completion
        uploadTask.observe(.success) { [weak self] snapshot in
            guard let self = self else { return }
            
            dlog("✅ Upload completed successfully!")
            dlog("   - Snapshot: \(snapshot)")
            
            Task { @MainActor in
                do {
                    dlog("📥 Getting download URL...")
                    
                    // Get download URL — prefer the resized variant if the
                    // firebase/storage-resize-images extension has processed it,
                    // otherwise fall back to the original upload.
                    let urlString = await self.resizedDownloadURL(
                        userId: userId, originalRef: storageRef
                    )
                    
                    dlog("✅ Download URL retrieved: \(urlString)")
                    
                    // Update user document
                    dlog("💾 Updating Firestore user document...")
                    try await self.updateUserProfilePhoto(userId: userId, photoURL: urlString)

                    // Sync updated profile image URL to Algolia so mention/search results
                    // show the new photo immediately without any manual re-index step.
                    try? await AlgoliaSyncService.shared.syncUser(
                        userId: userId,
                        userData: ["profileImageURL": urlString]
                    )

                    // Schedule async deep scan post-upload
                    ProfileImageSafetyGate.shared.scheduleDeepScan(
                        imageURL: urlString,
                        pHash: pHash,
                        uploaderId: userId,
                        context: .profilePhoto,
                        contentId: userId
                    )
                    
                    self.isUploading = false
                    self.uploadProgress = 1.0
                    
                    dlog("✅ Profile photo uploaded: \(urlString)")
                    dlog("=== UPLOAD COMPLETED SUCCESSFULLY ===\n")
                    completion(.success(urlString))
                    
                } catch {
                    self.isUploading = false
                    self.error = error.localizedDescription
                    dlog("❌ Error after upload: \(error)")
                    dlog("   - Failed at: Getting URL or updating Firestore")
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
                    
                    dlog("\n❌ === UPLOAD FAILED ===")
                    dlog("   - Error: \(error)")
                    dlog("   - Error code: \((error as NSError).code)")
                    dlog("   - Error domain: \((error as NSError).domain)")
                    dlog("   - Localized description: \(error.localizedDescription)")
                    
                    // Check for specific Firebase Storage errors
                    let nsError = error as NSError
                    if nsError.domain == "FIRStorageErrorDomain" {
                        switch nsError.code {
                        case -13021:
                            dlog("   - ERROR TYPE: Quota exceeded")
                        case -13010:
                            dlog("   - ERROR TYPE: Object not found")
                        case -13015:
                            dlog("   - ERROR TYPE: Bucket not found")
                        case -13020:
                            dlog("   - ERROR TYPE: Project not found")
                        case -13030:
                            dlog("   - ERROR TYPE: Retry limit exceeded")
                        case -13040:
                            dlog("   - ERROR TYPE: Invalid checksum")
                        case -13000:
                            dlog("   - ERROR TYPE: Unknown error")
                        case -13002:
                            dlog("   - ERROR TYPE: Object size mismatch")
                        case -13012:
                            dlog("   - ERROR TYPE: Download size exceeded")
                        case -13016:
                            dlog("   - ERROR TYPE: Unauthorized - CHECK YOUR STORAGE RULES!")
                            dlog("   - HINT: User \(userId) doesn't have permission")
                            dlog("   - Path: profile_images/\(userId)/profile.jpg")
                        default:
                            dlog("   - ERROR TYPE: Other Firebase Storage error (code: \(nsError.code))")
                        }
                    }
                    
                    dlog("=== END UPLOAD FAILED ===\n")
                    completion(.failure(error))
                } else {
                    dlog("❌ Upload failed with no error information")
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
                dlog("✅ Deleted photo: \(item.name)")
            }
            
            // Remove photoURL from user document
            try await updateUserProfilePhoto(userId: currentUserId, photoURL: nil)

            // Clear from Algolia so search/mentions stop showing the old photo
            try? await AlgoliaSyncService.shared.syncUser(
                userId: currentUserId,
                userData: ["profileImageURL": ""]
            )

            dlog("✅ Profile photo deleted")
            
        } catch {
            dlog("❌ Error deleting profile photo: \(error)")
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
        
        dlog("✅ Updated user profile photo URL")
    }
    
    /// Attempt to fetch the resized download URL produced by the
    /// firebase/storage-resize-images extension. Falls back to the
    /// original file's URL if the extension hasn't run yet or isn't
    /// installed. Checks the two most common output path conventions:
    ///   • Same folder, size suffix: profile_images/{uid}/profile_200x200.jpg
    ///   • Resized sub-folder:       profile_images/{uid}/resized/profile.jpg
    private func resizedDownloadURL(userId: String, originalRef: StorageReference) async -> String {
        let candidates = [
            storage.reference()
                .child("profile_images")
                .child(userId)
                .child("resized")
                .child("profile.jpg"),
            storage.reference()
                .child("profile_images")
                .child(userId)
                .child("profile_200x200.jpg"),
        ]

        for candidate in candidates {
            if let url = try? await candidate.downloadURL() {
                dlog("✅ Using resized profile image: \(url.absoluteString)")
                return url.absoluteString
            }
        }

        // Fallback — extension not installed or hasn't processed yet
        if let url = try? await originalRef.downloadURL() {
            dlog("ℹ️ Using original profile image (no resized variant found)")
            return url.absoluteString
        }
        return ""
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

