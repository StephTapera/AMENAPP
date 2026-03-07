
//
//  GenericArchiveImporter.swift
//  AMENAPP
//
//  Sample concrete importer that handles a common JSON pattern shared by many
//  "Download Your Information" archives (Instagram, Facebook, etc.).
//
//  Expected archive layout (flexible — missing dirs/files are skipped):
//    archive/
//      posts/
//        post_1.json          (array of post objects OR single object)
//        media/
//          img001.jpg
//      content/
//        posts_1.json
//      your_posts_1.json      (flat file at root)
//
//  Each JSON post object may have any combination of:
//    "creation_timestamp" | "timestamp" | "taken_at" : Int (unix epoch)
//    "title" | "text" | "media_metadata" : String
//    "media" : [{"uri": "media/img001.jpg"}]
//    "data" : [{"post": "text here"}]
//
//  This importer is intentionally lenient — unknown structures fall back to
//  extracting whatever text and media it can find.
//

import Foundation
import CryptoKit

struct GenericArchiveImporter: ArchiveImporter {

    let displayName = "Generic Archive Importer"

    func canHandle(archiveRoot: URL) -> Bool {
        // Accept if any JSON file exists anywhere in the root
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: archiveRoot,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "json" { return true }
        }
        return false
    }

    func parse(archiveRoot: URL,
               progressHandler: @escaping (ImportProgress) -> Void) async throws -> [ImportableItem] {

        return try await Task.detached(priority: .userInitiated) {

            var progress = ImportProgress()
            progress.phase = .parsing
            progressHandler(progress)

            let jsonFiles = Self.collectJSONFiles(in: archiveRoot)
            progress.totalItems = jsonFiles.count
            progressHandler(progress)

            var items: [ImportableItem] = []

            for (index, jsonURL) in jsonFiles.enumerated() {
                progress.currentItemIndex = index
                progressHandler(progress)

                guard !Task.isCancelled else { break }

                do {
                    let data = try Data(contentsOf: jsonURL)
                    let parsed = try JSONSerialization.jsonObject(with: data)
                    let extracted = Self.extractItems(from: parsed,
                                                      archiveRoot: archiveRoot,
                                                      jsonURL: jsonURL)
                    items.append(contentsOf: extracted)
                } catch {
                    progress.errorMessages.append("Skipped \(jsonURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            progress.phase = .reviewReady
            progressHandler(progress)
            return items

        }.value
    }

    // MARK: - Private Helpers

    /// Recursively collect all .json files, skipping system/metadata files.
    private static func collectJSONFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        let skipNames: Set<String> = [
            "manifest.json", "index.json", "ads_information.json",
            "account_information.json", "personal_information.json",
            "profile_information.json", "settings.json"
        ]
        var result: [URL] = []
        guard let enumerator = fm.enumerator(at: root,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "json" else { continue }
            guard !skipNames.contains(url.lastPathComponent.lowercased()) else { continue }
            result.append(url)
        }
        return result
    }

    /// Extract one or more ImportableItems from a parsed JSON value.
    private static func extractItems(from json: Any,
                                     archiveRoot: URL,
                                     jsonURL: URL) -> [ImportableItem] {
        var results: [ImportableItem] = []

        // Top-level array
        if let array = json as? [[String: Any]] {
            for dict in array {
                if let item = makeItem(from: dict, archiveRoot: archiveRoot) {
                    results.append(item)
                }
            }
            return results
        }

        // Top-level dict that wraps an array under a common key
        if let dict = json as? [String: Any] {
            let arrayKeys = ["posts", "content", "media", "items", "data"]
            for key in arrayKeys {
                if let array = dict[key] as? [[String: Any]] {
                    for subDict in array {
                        if let item = makeItem(from: subDict, archiveRoot: archiveRoot) {
                            results.append(item)
                        }
                    }
                    if !results.isEmpty { return results }
                }
            }
            // Single post at top level
            if let item = makeItem(from: dict, archiveRoot: archiveRoot) {
                results.append(item)
            }
        }

        return results
    }

    /// Build a single ImportableItem from a dictionary, tolerating missing fields.
    private static func makeItem(from dict: [String: Any], archiveRoot: URL) -> ImportableItem? {
        // --- Timestamp ---
        let timestamp: Date? = {
            let keys = ["creation_timestamp", "timestamp", "taken_at", "date", "created_at"]
            for k in keys {
                if let epoch = dict[k] as? TimeInterval { return Date(timeIntervalSince1970: epoch) }
                if let epoch = dict[k] as? Int { return Date(timeIntervalSince1970: TimeInterval(epoch)) }
                if let str = dict[k] as? String, let d = ISO8601DateFormatter().date(from: str) { return d }
            }
            return nil
        }()

        // --- Text ---
        var text: String? = nil
        let textKeys = ["title", "text", "caption", "content", "description"]
        for k in textKeys {
            if let t = dict[k] as? String, !t.isEmpty { text = t; break }
        }
        // Instagram-style nested: data: [{post: "text"}]
        if text == nil, let data = dict["data"] as? [[String: Any]] {
            for entry in data {
                if let post = entry["post"] as? String, !post.isEmpty { text = post; break }
            }
        }

        // Must have at least some text or media to be worth importing
        let mediaURIs: [String] = {
            var uris: [String] = []
            if let media = dict["media"] as? [[String: Any]] {
                uris = media.compactMap { $0["uri"] as? String }
            } else if let uri = dict["uri"] as? String {
                uris = [uri]
            }
            return uris
        }()

        guard text != nil || !mediaURIs.isEmpty else { return nil }

        let mediaLocalURLs = mediaURIs.compactMap { uri -> URL? in
            // Archives usually store paths relative to the archive root
            let relative = archiveRoot.appendingPathComponent(uri)
            return FileManager.default.fileExists(atPath: relative.path) ? relative : nil
        }

        let hashes = mediaLocalURLs.compactMap { computeSHA256(url: $0) }

        return ImportableItem(
            id: UUID().uuidString,
            title: nil,
            caption: sanitize(text),
            mediaURLs: mediaLocalURLs,
            mediaHashes: hashes,
            timestamp: timestamp,
            source: .generic,
            rawJSON: dict
        )
    }

    // MARK: - Utilities

    private static func sanitize(_ text: String?) -> String? {
        guard var t = text else { return nil }
        // Strip HTML tags (rare but some exports include them)
        t = t.replacingOccurrences(of: "<[^>]+>",
                                   with: "",
                                   options: .regularExpression)
        // Collapse excessive whitespace
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func computeSHA256(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
