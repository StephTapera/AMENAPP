import Foundation
import AVFoundation
import Photos
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

protocol CreatorMediaImportServicing {
    func importAssets(
        localIdentifiers: [String],
        projectID: String,
        onProgress: ((Double, String) -> Void)?
    ) async throws -> [CreatorAsset]
}

final class CreatorMediaImportService: CreatorMediaImportServicing {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let sceneService: CreatorSceneServicing = CreatorSceneService()

    func importAssets(
        localIdentifiers: [String],
        projectID: String,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> [CreatorAsset] {
        let ownerID = try requireOwnerID()
        try await requestPhotoAccessIfNeeded()

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var imported: [CreatorAsset] = []

        let total = max(assets.count, 1)

        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            let assetType: CreatorAssetType = asset.mediaType == .video ? .video : .image
            let assetRef = db.collection("users")
                .document(ownerID)
                .collection("creatorAssets")
                .document()

            let fileName = "\(assetRef.documentID).\(assetType == .video ? "mov" : "jpg")"
            let storagePath = "creator/users/\(ownerID)/projects/\(projectID)/assets/originals/\(fileName)"

            let fileURL = try await exportAssetToTempFile(asset: asset, fileName: fileName)
            let downloadURL = try await uploadFile(
                fileURL: fileURL,
                storagePath: storagePath,
                onProgress: { progress in
                    let overall = (Double(index) + progress) / Double(total)
                    onProgress?(overall, "Uploading")
                }
            )

            var thumbnailURL: URL? = nil
            if assetType == .video {
                let thumbnailPath = "creator/users/\(ownerID)/projects/\(projectID)/thumbnails/\(assetRef.documentID).jpg"
                if let thumbnailFileURL = try? await generateVideoThumbnail(from: fileURL, assetID: assetRef.documentID) {
                    thumbnailURL = try? await uploadFile(fileURL: thumbnailFileURL, storagePath: thumbnailPath)
                    try? FileManager.default.removeItem(at: thumbnailFileURL)
                }
            }

            let creatorAsset = CreatorAsset(
                id: assetRef.documentID,
                ownerID: ownerID,
                projectID: projectID,
                type: assetType,
                localIdentifier: asset.localIdentifier,
                storagePath: storagePath,
                downloadURL: downloadURL.absoluteString,
                thumbnailURL: assetType == .image ? downloadURL.absoluteString : thumbnailURL?.absoluteString,
                proxyURL: nil,
                durationMs: asset.mediaType == .video ? Int(asset.duration * 1000) : nil,
                width: asset.pixelWidth,
                height: asset.pixelHeight,
                fileSizeBytes: nil,
                mimeType: assetType == .video ? "video/quicktime" : "image/jpeg",
                checksum: nil,
                source: .device,
                moderationStatus: .pending,
                authenticityStatus: .unverified,
                createdAt: Date()
            )

            let assetData = try CreatorFirestoreCoder.encode(creatorAsset)
            try await assetRef.setData(assetData)
            let projectRef = db.collection("users")
                .document(ownerID)
                .collection("creatorProjects")
                .document(projectID)

            try await projectRef.updateData(["assetIDs": FieldValue.arrayUnion([assetRef.documentID])])

            if let scene = try? await sceneService.createScene(projectID: projectID, assetID: assetRef.documentID, orderIndex: index) {
                try await projectRef.updateData(["sceneIDs": FieldValue.arrayUnion([scene.id])])
            }

            imported.append(creatorAsset)
            onProgress?(Double(index + 1) / Double(total), "Processing")

            try? FileManager.default.removeItem(at: fileURL)
        }

        onProgress?(1.0, "Done")

        return imported
    }

    private func requestPhotoAccessIfNeeded() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if newStatus == .authorized || newStatus == .limited {
                return
            }
            throw CreatorServiceError.permissionDenied
        default:
            throw CreatorServiceError.permissionDenied
        }
    }

    private func exportAssetToTempFile(asset: PHAsset, fileName: String) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        if asset.mediaType == .video {
            let avAsset = try await requestAVAsset(for: asset)
            guard let urlAsset = avAsset as? AVURLAsset else {
                throw CreatorServiceError.invalidState
            }
            try FileManager.default.copyItem(at: urlAsset.url, to: tempURL)
            return tempURL
        }

        let data = try await requestImageData(for: asset)
        try data.write(to: tempURL, options: [.atomic])
        return tempURL
    }

    private func requestImageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) { data, _, _, info in
                if let info, let error = info[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: CreatorServiceError.invalidState)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func requestAVAsset(for asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, info in
                if let info, let error = info[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let avAsset else {
                    continuation.resume(throwing: CreatorServiceError.invalidState)
                    return
                }
                continuation.resume(returning: avAsset)
            }
        }
    }

    private func generateVideoThumbnail(from fileURL: URL, assetID: String) async throws -> URL {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        let image = UIImage(cgImage: cgImage)
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw CreatorServiceError.invalidState
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(assetID)_thumb.jpg")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        try data.write(to: tempURL, options: [.atomic])
        return tempURL
    }

    private func uploadFile(
        fileURL: URL,
        storagePath: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let ref = storage.reference(withPath: storagePath)
        let metadata = StorageMetadata()
        metadata.cacheControl = "public,max-age=3600"

        return try await withCheckedThrowingContinuation { continuation in
            let task = ref.putFile(from: fileURL, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                ref.downloadURL { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        continuation.resume(throwing: CreatorServiceError.invalidState)
                        return
                    }
                    continuation.resume(returning: url)
                }
            }

            task.observe(.progress) { snapshot in
                guard let progress = snapshot.progress?.fractionCompleted else { return }
                onProgress?(progress)
            }

        }
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
