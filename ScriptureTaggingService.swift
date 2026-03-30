//
//  ScriptureTaggingService.swift
//  AMENAPP
//
//  Auto-tags posts with relevant scripture references using AI.
//  Every post, testimony, and prayer request gets 1-3 verse pills
//  surfaced without the user manually tapping Berean.
//

import Foundation
import Combine
import SwiftUI
import FirebaseFirestore

struct ScriptureTag: Codable, Identifiable, Hashable {
    var id: String          // e.g. "john-3-16"
    let reference: String   // e.g. "John 3:16"
    let preview: String     // first 60 chars of verse
    let relevanceScore: Float
    let theme: String       // e.g. "grace", "faith", "redemption"
}

@MainActor
class ScriptureTaggingService: ObservableObject {
    static let shared = ScriptureTaggingService()

    // In-memory cache: postID → tags
    private var tagCache: [String: [ScriptureTag]] = [:]

    private init() {}

    // MARK: - Public API

    /// Get scripture tags for a post. Returns cached tags or fetches from
    /// Firestore/AI. Never blocks — returns empty array immediately if not cached.
    func getTags(for postID: String) -> [ScriptureTag] {
        tagCache[postID] ?? []
    }

    /// Load tags for a post asynchronously. Updates cache when done.
    func loadTags(for postID: String, postText: String) async -> [ScriptureTag] {
        // Return cached if available
        if let cached = tagCache[postID] {
            return cached
        }

        // Check Firestore first
        let db = Firestore.firestore()
        if let doc = try? await db.collection("posts").document(postID).getDocument(),
           let data = doc.data(),
           let tagsData = data["scriptureTags"] as? [[String: Any]], !tagsData.isEmpty {
            let tags = tagsData.compactMap { parseTag($0) }
            tagCache[postID] = tags
            return tags
        }

        // Skip short posts
        guard postText.count >= 20 else { return [] }

        // Generate tags via AI
        do {
            let tags = try await generateTags(for: postText)
            tagCache[postID] = tags

            // Store on Firestore document (fire and forget)
            if !tags.isEmpty {
                let tagsDict = tags.map { tag -> [String: Any] in
                    [
                        "id": tag.id,
                        "reference": tag.reference,
                        "preview": tag.preview,
                        "relevanceScore": tag.relevanceScore,
                        "theme": tag.theme,
                    ]
                }
                try? await db.collection("posts").document(postID).updateData([
                    "scriptureTags": tagsDict,
                    "scriptureTaggedAt": FieldValue.serverTimestamp(),
                ])
            }

            return tags
        } catch {
            return []
        }
    }

    // MARK: - AI Tag Generation

    private func generateTags(for text: String) async throws -> [ScriptureTag] {
        let result = try await CloudFunctionsService.shared.call(
            "bereanScriptureExtract",
            data: [
                "text": String(text.prefix(500)),
                "purpose": "auto_tag",
                "maxResults": 3,
            ] as [String: Any]
        )

        guard let dict = result as? [String: Any] else { return [] }

        // Try parsing structured response
        if let tagsArray = dict["scriptures"] as? [[String: Any]] {
            return tagsArray.compactMap { parseTag($0) }
        }

        // Try parsing text response as JSON
        if let text = dict["text"] as? String,
           let jsonData = text.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            return parsed.compactMap { parseTag($0) }
        }

        return []
    }

    private func parseTag(_ dict: [String: Any]) -> ScriptureTag? {
        guard let reference = dict["reference"] as? String, !reference.isEmpty else { return nil }
        let preview = dict["preview"] as? String ?? ""
        let score = dict["relevanceScore"] as? Float ?? Float(dict["relevanceScore"] as? Double ?? 0.8)
        let theme = dict["theme"] as? String ?? "faith"
        let id = reference.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        guard score > 0.7 else { return nil }

        return ScriptureTag(
            id: id,
            reference: reference,
            preview: String(preview.prefix(60)),
            relevanceScore: score,
            theme: theme
        )
    }

    /// Clear cache (call on sign-out)
    func clearCache() {
        tagCache.removeAll()
    }
}

// MARK: - Scripture Tags Row View

struct ScriptureTagsRow: View {
    let postID: String
    let postText: String
    @State private var tags: [ScriptureTag] = []
    @State private var expandedTag: ScriptureTag?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                // Shimmer placeholder
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 80, height: 24)
                }
                .transition(.opacity)
            } else if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags) { tag in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        expandedTag = expandedTag?.id == tag.id ? nil : tag
                                    }
                                } label: {
                                    Text(tag.reference)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color.purple.opacity(0.8)))
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }

                    // Expanded verse preview
                    if let expanded = expandedTag {
                        Text(expanded.preview.isEmpty ? expanded.reference : expanded.preview)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.horizontal, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .task {
            tags = await ScriptureTaggingService.shared.loadTags(for: postID, postText: postText)
            isLoading = false
        }
    }
}
