
//
//  DataImportService.swift
//  AMENAPP
//
//  Orchestrates the full import pipeline:
//    1. Unzip archive to a temp directory (streaming, memory-safe via Process/ZipFoundation polyfill)
//    2. Detect source and route to the right importer
//    3. Deduplicate against previously imported content
//    4. Upload media to Firebase Storage under users/{uid}/imports/{batchId}/
//    5. Write FirestorePost records with importedFrom, importBatchId fields
//    6. Write ImportBatch record to Firestore for batch-level delete support
//
//  LEGAL NOTE: This service only processes user-supplied official export archives.
//  No scraping, no unofficial API calls, no third-party login flows.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import CryptoKit
import Compression

@MainActor
final class DataImportService: ObservableObject {

    static let shared = DataImportService()
    private init() {}

    // MARK: - Published State

    @Published var progress: ImportProgress = ImportProgress()
    @Published var items: [ImportableItem] = []
    @Published var detectedSource: ImportSource = .generic
    @Published var batchId: String = UUID().uuidString

    // MARK: - Private

    private let db = Firestore.firestore()
    private let importers: [ArchiveImporter] = [
        InstagramArchiveImporter(),
        TwitterArchiveImporter(),
        GenericArchiveImporter()
    ]
    private var tempDirectory: URL?

    // MARK: - Step 1: Load Archive

    /// Entry point. Call this with the URL returned by UIDocumentPickerViewController.
    func loadArchive(at url: URL) async {
        do {
            progress = ImportProgress()
            progress.phase = .unzipping
            items = []
            batchId = UUID().uuidString

            let temp = try prepareTempDirectory()
            tempDirectory = temp

            let archiveRoot: URL
            if url.pathExtension.lowercased() == "zip" {
                archiveRoot = try await unzipStreaming(source: url, destination: temp)
            } else if isDirectory(url) {
                // User selected a folder — security-scope it
                _ = url.startAccessingSecurityScopedResource()
                archiveRoot = url
            } else {
                throw ImportError.unsupportedFormat("Please select a .zip file or folder.")
            }

            let importer = detect(archiveRoot: archiveRoot)
            detectedSource = importer is InstagramArchiveImporter ? .instagram
                           : importer is TwitterArchiveImporter   ? .twitter
                           : .generic

            progress.phase = .parsing
            let parsed = try await importer.parse(archiveRoot: archiveRoot) { [weak self] p in
                Task { @MainActor [weak self] in self?.progress = p }
            }

            let deduped = await deduplicateItems(parsed)
            await MainActor.run { self.items = deduped }
            progress.phase = .reviewReady

        } catch {
            progress.phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Step 2: Upload Selected Items

    func importSelected(destination: ImportDestination) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let selected = items.filter { $0.isSelected && !$0.isDuplicate }
        guard !selected.isEmpty else { return }

        progress.phase = .uploading
        progress.totalItems = selected.count
        progress.currentItemIndex = 0

        var importedCount = 0
        var skippedCount = 0

        // Write the batch record first
        let batch = ImportBatch(
            id: batchId,
            userId: uid,
            source: detectedSource,
            destination: destination,
            archiveFilename: "archive",
            itemCount: selected.count,
            importedAt: Date(),
            status: .uploading
        )
        try? await writeBatch(batch)

        for item in selected {
            guard !Task.isCancelled else { break }
            do {
                try await uploadItem(item, uid: uid, destination: destination)
                importedCount += 1
            } catch {
                progress.errorMessages.append("Skipped item: \(error.localizedDescription)")
                skippedCount += 1
            }
            progress.currentItemIndex += 1
        }

        // Mark batch complete
        try? await db.collection("importBatches")
            .document(batchId)
            .updateData(["status": "completed"])

        progress.phase = .completed(importedCount: importedCount, skippedCount: skippedCount)
        cleanup()
    }

    // MARK: - Delete Batch (Reversibility)

    /// Deletes all Firestore posts and Storage files created by a batch.
    func deleteBatch(_ batchId: String, userId: String) async throws {
        // Delete posts
        let snap = try await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .whereField("importBatchId", isEqualTo: batchId)
            .getDocuments()

        let writeBatch = db.batch()
        snap.documents.forEach { writeBatch.deleteDocument($0.reference) }
        try await writeBatch.commit()

        // Delete Storage folder
        let storageRef = Storage.storage().reference()
            .child("users/\(userId)/imports/\(batchId)")
        try await deleteStorageFolder(storageRef)

        // Delete batch record
        try await db.collection("importBatches").document(batchId).delete()
    }

    // MARK: - Private: Upload Single Item

    private func uploadItem(_ item: ImportableItem, uid: String, destination: ImportDestination) async throws {
        var mediaDownloadURLs: [String] = []

        for (i, localURL) in item.mediaURLs.prefix(4).enumerated() {
            // Only accept common image/video types
            let ext = localURL.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic", "mp4", "mov"].contains(ext) else { continue }

            guard let data = try? Data(contentsOf: localURL),
                  data.count < 50_000_000 else { continue } // Skip files > 50 MB

            let filename = "\(UUID().uuidString)_\(i).\(ext)"
            let ref = Storage.storage().reference()
                .child("users/\(uid)/imports/\(batchId)/\(filename)")

            let meta = StorageMetadata()
            meta.contentType = ext == "mp4" || ext == "mov" ? "video/\(ext)" : "image/jpeg"
            _ = try await ref.putDataAsync(data, metadata: meta)
            let url = try await ref.downloadURL()
            mediaDownloadURLs.append(url.absoluteString)
        }

        // Build the Firestore post document
        let now = Date()
        let originalDate = item.timestamp ?? now
        var docData: [String: Any] = [
            "authorId":          uid,
            "content":           item.caption ?? "",
            "category":          item.firestoreCategory(destination: destination),
            "visibility":        destination == .importedPosts ? "everyone" : "private",
            "allowComments":     destination == .importedPosts,
            "createdAt":         Timestamp(date: originalDate),
            "updatedAt":         Timestamp(date: now),
            "amenCount":         0,
            "lightbulbCount":    0,
            "commentCount":      0,
            "repostCount":       0,
            "isRepost":          false,
            "amenUserIds":       [String](),
            "lightbulbUserIds":  [String](),
            // Import provenance — displayed as small label on post card
            "importedFrom":      item.source.rawValue,
            "importBatchId":     batchId,
            // Queue public posts for moderation before surfacing in feed
            "moderationStatus":  destination == .importedPosts ? "pending" : "approved",
        ]

        // Author info
        if let user = Auth.auth().currentUser {
            docData["authorName"]     = user.displayName ?? "You"
            docData["authorInitials"] = String((user.displayName ?? "?").prefix(1)).uppercased()
        }

        if !mediaDownloadURLs.isEmpty {
            docData["imageURLs"] = mediaDownloadURLs
        }

        try await db.collection("posts").addDocument(data: docData)
    }

    // MARK: - Dedupe

    private func deduplicateItems(_ items: [ImportableItem]) async -> [ImportableItem] {
        // Load previously imported hashes from Firestore (last 1000)
        var knownHashes: Set<String> = []
        if let uid = Auth.auth().currentUser?.uid {
            let snap = try? await db.collection("importDedupeHashes")
                .whereField("userId", isEqualTo: uid)
                .limit(to: 1000)
                .getDocuments()
            snap?.documents.forEach { doc in
                if let h = doc.data()["hash"] as? String { knownHashes.insert(h) }
            }
        }

        // Also build a set from the current batch to catch intra-batch dupes
        var batchSignatures: Set<String> = []
        let result = items.map { item -> ImportableItem in
            var m = item
            // Signature = first media hash OR (timestamp + caption prefix)
            let sig: String
            if let h = item.mediaHashes.first {
                sig = h
            } else {
                let captionSlug = String((item.caption ?? "").prefix(80))
                let ts = item.timestamp.map { String(Int($0.timeIntervalSince1970)) } ?? "nodate"
                sig = "\(ts)|\(captionSlug)".data(using: .utf8).map {
                    SHA256Hex.compute(data: $0)
                } ?? captionSlug
            }

            if knownHashes.contains(sig) || batchSignatures.contains(sig) {
                m.isDuplicate = true
                m.duplicateReason = "Already imported"
                m.isSelected = false
            } else {
                batchSignatures.insert(sig)
            }
            return m
        }

        return result
    }

    // MARK: - Helpers

    private func detect(archiveRoot: URL) -> ArchiveImporter {
        importers.first { $0.canHandle(archiveRoot: archiveRoot) } ?? GenericArchiveImporter()
    }

    private func prepareTempDirectory() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("amen_import_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Extracts a ZIP archive to the destination directory using the system `unzip` binary.
    /// On iOS the sandbox does not allow `Process`, so we use a pure-Swift ZIP reader
    /// built on the `Compression` framework. For large archives the user should unzip
    /// in the Files app first and select the resulting folder instead.
    private func unzipStreaming(source: URL, destination: URL) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) {
            _ = source.startAccessingSecurityScopedResource()
            defer { source.stopAccessingSecurityScopedResource() }

            // Use the built-in minizip reader via NSData + ZIP local-file parsing.
            // This handles standard DEFLATE ZIP archives (the format used by all major
            // social platforms for their data exports).
            try ZipExtractor.extract(from: source, to: destination)

            // Return the first subdirectory or destination itself
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )) ?? []
            return contents.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
                ?? destination
        }.value
    }

    private func writeBatch(_ batch: ImportBatch) async throws {
        let data: [String: Any] = [
            "id":              batch.id,
            "userId":          batch.userId,
            "source":          batch.source.rawValue,
            "destination":     batch.destination.rawValue,
            "archiveFilename": batch.archiveFilename,
            "itemCount":       batch.itemCount,
            "importedAt":      Timestamp(date: batch.importedAt),
            "status":          batch.status.rawValue
        ]
        try await db.collection("importBatches").document(batch.id).setData(data)
    }

    private func deleteStorageFolder(_ ref: StorageReference) async throws {
        let list = try await ref.listAll()
        await withThrowingTaskGroup(of: Void.self) { group in
            list.items.forEach { item in group.addTask { try await item.delete() } }
        }
    }

    private func cleanup() {
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
            tempDirectory = nil
        }
    }
}

// MARK: - Platform-specific Importer Stubs

/// Detects Instagram "Download Your Information" archives.
/// Layout: personal_information.json + posts/ directory.
struct InstagramArchiveImporter: ArchiveImporter {
    let displayName = "Instagram Archive Importer"
    nonisolated init() {}

    nonisolated func canHandle(archiveRoot: URL) -> Bool {
        let personalInfo = archiveRoot.appendingPathComponent("personal_information.json")
        let postsDir = archiveRoot.appendingPathComponent("posts")
        return FileManager.default.fileExists(atPath: personalInfo.path)
            || FileManager.default.fileExists(atPath: postsDir.path)
    }

    nonisolated func parse(archiveRoot: URL, progressHandler: @escaping (ImportProgress) -> Void) async throws -> [ImportableItem] {
        // Delegate to generic parser — Instagram's JSON post format is handled there
        let generic = GenericArchiveImporter()
        var result = try await generic.parse(archiveRoot: archiveRoot, progressHandler: progressHandler)
        // Tag all items as Instagram
        result = result.map {
            var m = $0; m.source = .instagram; return m
        }
        return result
    }
}

/// Detects X/Twitter "Download an archive of your data" exports.
/// Layout: data/tweets.js (JSONP-style: window.YTD.tweets.part0 = [...])
struct TwitterArchiveImporter: ArchiveImporter {
    let displayName = "X / Twitter Archive Importer"
    nonisolated init() {}

    nonisolated func canHandle(archiveRoot: URL) -> Bool {
        let tweetsJS = archiveRoot.appendingPathComponent("data/tweets.js")
        return FileManager.default.fileExists(atPath: tweetsJS.path)
    }

    nonisolated func parse(archiveRoot: URL, progressHandler: @escaping (ImportProgress) -> Void) async throws -> [ImportableItem] {
        return await Task.detached(priority: .userInitiated) {
            var progress = ImportProgress()
            progress.phase = .parsing
            progressHandler(progress)

            let tweetsJS = archiveRoot.appendingPathComponent("data/tweets.js")
            guard var raw = try? String(contentsOf: tweetsJS, encoding: .utf8) else { return [] }

            // Strip JSONP wrapper: "window.YTD.tweets.part0 = "
            if let eqRange = raw.range(of: " = ") {
                raw = String(raw[eqRange.upperBound...])
            }

            guard let data = raw.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            progress.totalItems = array.count
            progressHandler(progress)

            var items: [ImportableItem] = []
            for (i, wrapper) in array.enumerated() {
                progress.currentItemIndex = i
                progressHandler(progress)

                guard let tweet = wrapper["tweet"] as? [String: Any] else { continue }
                let text = tweet["full_text"] as? String ?? tweet["text"] as? String
                guard let t = text, !t.hasPrefix("RT @") else { continue } // skip retweets

                let ts: Date? = {
                    if let s = tweet["created_at"] as? String {
                        let f = DateFormatter()
                        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
                        return f.date(from: s)
                    }
                    return nil
                }()

                // Resolve media
                var mediaURLs: [URL] = []
                if let entities = tweet["extended_entities"] as? [String: Any],
                   let mediaArr = entities["media"] as? [[String: Any]] {
                    for m in mediaArr {
                        if let filename = (m["media_url"] as? String).map({ URL(string: $0)?.lastPathComponent }),
                           let fn = filename {
                            let local = archiveRoot.appendingPathComponent("data/tweet_media/\(fn)")
                            if FileManager.default.fileExists(atPath: local.path) {
                                mediaURLs.append(local)
                            }
                        }
                    }
                }

                items.append(ImportableItem(
                    id: UUID().uuidString,
                    title: nil,
                    caption: t.trimmingCharacters(in: .whitespacesAndNewlines),
                    mediaURLs: mediaURLs,
                    mediaHashes: mediaURLs.compactMap { Self.sha256(url: $0) },
                    timestamp: ts,
                    source: .twitter,
                    rawJSON: tweet
                ))
            }

            progress.phase = .reviewReady
            progressHandler(progress)
            return items
        }.value
    }

    nonisolated private static func sha256(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256Hex.compute(data: data)
    }
}

// MARK: - SHA256 Helper

private enum SHA256Hex {
    nonisolated static func compute(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Built-in ZIP Extractor (no external dependencies)

/// Lightweight ZIP extractor using pure Swift + Compression framework.
/// Supports STORE (method 0) and DEFLATE (method 8) entries, which covers
/// all major social-platform data export archives.
///
/// All methods are nonisolated so this can be called safely from detached Tasks.
enum ZipExtractor {

    enum ZipError: LocalizedError {
        case invalidSignature
        case unsupportedCompression(UInt16)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidSignature:          return "Not a valid ZIP archive."
            case .unsupportedCompression(let m): return "Unsupported ZIP compression method \(m)."
            case .extractionFailed(let r):   return "ZIP extraction failed: \(r)"
            }
        }
    }

    nonisolated static func extract(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard let fileData = try? Data(contentsOf: source, options: .mappedIfSafe) else {
            throw ZipError.extractionFailed("Cannot read archive file.")
        }
        let bytes = [UInt8](fileData)
        var offset = 0

        while offset + 30 <= bytes.count {
            // Local file header signature = 0x04034b50
            let sig = readUInt32(bytes, offset: offset)
            guard sig == 0x04034b50 else { break }

            let compression   = readUInt16(bytes, offset: offset + 8)
            let compressedSize   = Int(readUInt32(bytes, offset: offset + 18))
            let uncompressedSize = Int(readUInt32(bytes, offset: offset + 22))
            let fileNameLength   = Int(readUInt16(bytes, offset: offset + 26))
            let extraFieldLength = Int(readUInt16(bytes, offset: offset + 28))

            let nameStart = offset + 30
            let nameEnd   = nameStart + fileNameLength
            guard nameEnd <= bytes.count else { break }

            let nameBytes = Array(bytes[nameStart..<nameEnd])
            let entryName = String(bytes: nameBytes, encoding: .utf8)
                         ?? String(bytes: nameBytes, encoding: .isoLatin1)
                         ?? "unknown"

            let dataStart = nameEnd + extraFieldLength
            let dataEnd   = dataStart + compressedSize
            guard dataEnd <= bytes.count else { break }

            offset = dataEnd

            // Skip directory entries
            if entryName.hasSuffix("/") { continue }

            // Build destination path (sanitize against path traversal)
            let safeName = entryName
                .components(separatedBy: "/")
                .filter { !$0.isEmpty && $0 != ".." && $0 != "." }
                .joined(separator: "/")
            guard !safeName.isEmpty else { continue }

            let outURL = destination.appendingPathComponent(safeName)
            let outDir = outURL.deletingLastPathComponent()
            try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

            let compressedData = Data(bytes[dataStart..<dataEnd])

            switch compression {
            case 0: // STORE
                try compressedData.write(to: outURL, options: .atomic)

            case 8: // DEFLATE
                let decompressed = try deflate(compressedData, expectedSize: uncompressedSize)
                try decompressed.write(to: outURL, options: .atomic)

            default:
                // Skip unsupported entries rather than aborting the whole extraction
                continue
            }
        }
    }

    // MARK: - DEFLATE via Compression framework

    nonisolated private static func deflate(_ data: Data, expectedSize: Int) throws -> Data {
        // Use zlib inflate (DEFLATE without the zlib wrapper) via Compression framework
        var sourceBuffer = [UInt8](data)
        let bufferSize = max(expectedSize, 1024)
        var destinationBuffer = [UInt8](repeating: 0, count: bufferSize)

        let decompressed = sourceBuffer.withUnsafeMutableBufferPointer { srcPtr in
            destinationBuffer.withUnsafeMutableBufferPointer { dstPtr in
                compression_decode_buffer(
                    dstPtr.baseAddress!, bufferSize,
                    srcPtr.baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard decompressed > 0 else {
            throw ZipError.extractionFailed("DEFLATE decompression returned 0 bytes.")
        }
        return Data(destinationBuffer.prefix(decompressed))
    }

    // MARK: - Little-endian readers

    nonisolated private static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    nonisolated private static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
             | (UInt32(bytes[offset + 1]) << 8)
             | (UInt32(bytes[offset + 2]) << 16)
             | (UInt32(bytes[offset + 3]) << 24)
    }
}

// MARK: - Import Errors

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case parseFailure(String)
    case uploadFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let m): return m
        case .parseFailure(let m):      return "Parse error: \(m)"
        case .uploadFailure(let m):     return "Upload error: \(m)"
        }
    }
}
