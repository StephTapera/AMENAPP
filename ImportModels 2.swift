
//
//  ImportModels.swift
//  AMENAPP
//
//  Data models for the User Data Export Importer (Feature A).
//  Supports official user-supplied archives only — no scraping, no unofficial APIs.
//  These are the user's OWN data files, exported through each platform's
//  "Download Your Information" / "Request Your Data" flow.
//

import Foundation

// MARK: - Import Source

/// Identifies the platform from which the archive originated.
enum ImportSource: String, Codable, CaseIterable, Identifiable {
    case instagram = "instagram"
    case twitter   = "twitter"
    case facebook  = "facebook"
    case generic   = "generic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .twitter:   return "X / Twitter"
        case .facebook:  return "Facebook"
        case .generic:   return "Other Platform"
        }
    }

    var icon: String {
        switch self {
        case .instagram: return "camera.filters"
        case .twitter:   return "bird"
        case .facebook:  return "person.2"
        case .generic:   return "square.and.arrow.down"
        }
    }

    /// Legal disclaimer shown to user before import begins.
    var legalNote: String {
        "You are importing your own personal data exported from \(displayName). " +
        "AMEN does not have any relationship with \(displayName). " +
        "Only content you personally created and own will be imported."
    }
}

// MARK: - Import Destination

/// Where the imported content will live inside AMEN.
enum ImportDestination: String, Codable, CaseIterable, Identifiable {
    /// Visible on the user's profile feed. Queued for moderation before going public.
    case importedPosts = "importedPosts"
    /// Private by default. Never public until the user explicitly shares it.
    case memories      = "memories"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .importedPosts: return "Imported Posts (Public after review)"
        case .memories:      return "Memories (Private)"
        }
    }

    var description: String {
        switch self {
        case .importedPosts:
            return "Your posts will be visible on your profile after AMEN's moderation review (usually fast)."
        case .memories:
            return "Stored privately — only you can see them. You can share individual memories later."
        }
    }
}

// MARK: - Importable Item

/// A single piece of content extracted from an export archive.
/// All fields are optional/resilient — archives are frequently incomplete.
struct ImportableItem: Identifiable, Hashable {
    let id: String                      // stable UUID generated at parse time
    var title: String?
    var caption: String?                // the main text content
    var mediaURLs: [URL]                // local file:// URLs pointing into the unzipped archive
    var mediaHashes: [String]           // SHA256 hex strings for dedupe
    var timestamp: Date?                // original creation date from export
    var source: ImportSource
    var rawJSON: [String: Any]?         // for debugging; excluded from Hashable/Codable

    // MARK: Toggles (user controls)
    var isSelected: Bool = true

    // MARK: Dedupe status (set by ImportBatchManager)
    var isDuplicate: Bool = false
    var duplicateReason: String?

    // Hashable conformance — identity only
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ImportableItem, rhs: ImportableItem) -> Bool { lhs.id == rhs.id }

    /// A short human-readable preview of the item (for the review list).
    var previewText: String {
        let text = caption ?? title ?? ""
        return text.isEmpty ? "(No text)" : String(text.prefix(120))
    }

    /// Firestore category string derived from destination.
    func firestoreCategory(destination: ImportDestination) -> String {
        destination == .importedPosts ? "openTable" : "memories"
    }
}

// MARK: - Import Batch

/// A batch created from a single archive file, written to Firestore as one atomic group.
struct ImportBatch: Identifiable, Codable {
    var id: String                      // UUID
    var userId: String
    var source: ImportSource
    var destination: ImportDestination
    var archiveFilename: String
    var itemCount: Int
    var importedAt: Date
    var status: BatchStatus

    enum BatchStatus: String, Codable {
        case pending    = "pending"
        case uploading  = "uploading"
        case completed  = "completed"
        case failed     = "failed"
    }
}

// MARK: - Import Progress

/// Observable progress state for the import pipeline.
struct ImportProgress {
    var phase: Phase = .idle
    var currentItemIndex: Int = 0
    var totalItems: Int = 0
    var bytesProcessed: Int64 = 0
    var totalBytes: Int64 = 0
    var errorMessages: [String] = []

    var fractionComplete: Double {
        guard totalItems > 0 else { return 0 }
        return Double(currentItemIndex) / Double(totalItems)
    }

    enum Phase: Equatable {
        case idle
        case unzipping
        case parsing
        case reviewReady
        case uploading
        case completed(importedCount: Int, skippedCount: Int)
        case failed(String)
    }
}

// MARK: - Importer Protocol

/// Generic interface for platform-specific import parsers.
/// Add new concrete importers (InstagramImporter, TwitterImporter) by conforming to this.
protocol ArchiveImporter {
    /// Human-readable name shown in the UI (e.g. "Instagram Archive Importer").
    var displayName: String { get }

    /// Returns true if this importer can handle the given archive root directory.
    func canHandle(archiveRoot: URL) -> Bool

    /// Parses the archive and returns an array of importable items.
    /// Should be called on a background thread.
    /// Must be resilient: partial failures should skip the item, not throw.
    func parse(archiveRoot: URL,
               progressHandler: @escaping (ImportProgress) -> Void) async throws -> [ImportableItem]
}
