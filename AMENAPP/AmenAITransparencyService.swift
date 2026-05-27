//
//  AmenAITransparencyService.swift
//  AMENAPP
//
//  AI transparency layer.
//  Answers: Was AI used? Is this source verified? Is this edited?
//  Every AI-generated or AI-assisted object must be labeled.
//
//  Applied to:
//    - posts, captions, comments, replies, summaries
//    - recommendations, church matches, creator tools
//    - suggested replies, AI images, AI audio, AI video
//    - AI profile content
//

import Foundation
import SwiftUI
import FirebaseFunctions
import FirebaseFirestore

@MainActor
final class AmenAITransparencyService: ObservableObject {

    static let shared = AmenAITransparencyService()

    private let functions = Functions.functions()
    private let flags = AmenSafetyFeatureFlags.shared
    private let db = Firestore.firestore()

    // Cache: contentId → transparency record
    private var cache: [String: TSAITransparencyRecord] = [:]

    private init() {}

    // MARK: - Fetch transparency info

    func transparencyRecord(for contentId: String, contentType: ContentSurface) async -> TSAITransparencyRecord? {
        if let cached = cache[contentId] { return cached }

        do {
            let snap = try await db.document("posts/\(contentId)/safety/main").getDocument()
            guard let data = snap.data() else { return nil }
            let record = parseRecord(data, contentId: contentId, contentType: contentType)
            cache[contentId] = record
            return record
        } catch { return nil }
    }

    // MARK: - Register AI-generated content

    func registerAIContent(
        contentId: String,
        contentType: ContentSurface,
        wasAIGenerated: Bool,
        wasAIAssisted: Bool,
        aiModelsUsed: [String] = [],
        declarationByAuthor: AIGeneratedStatus = .unknown
    ) async {
        let labelType = determineLabelType(
            wasAIGenerated: wasAIGenerated,
            wasAIAssisted: wasAIAssisted,
            declaration: declarationByAuthor
        )

        let record: [String: Any] = [
            "contentId": contentId,
            "contentType": contentType.rawValue,
            "wasAIGenerated": wasAIGenerated,
            "wasAIAssisted": wasAIAssisted,
            "aiModelsUsed": aiModelsUsed,
            "declarationByAuthor": declarationByAuthor.rawValue,
            "detectedBySystem": wasAIGenerated ? "ai_generated" : wasAIAssisted ? "ai_assisted" : "not_ai",
            "labelShown": labelType != .none,
            "labelType": labelType.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
        ]

        do {
            try await db.document("posts/\(contentId)/safety/main").setData(record, merge: true)
        } catch {
            dlog("⚠️ AI transparency record write failed for \(contentId): \(error)")
        }
    }

    // MARK: - Label determination

    func determineLabelType(
        wasAIGenerated: Bool,
        wasAIAssisted: Bool,
        declaration: AIGeneratedStatus
    ) -> AILabelType {
        if wasAIGenerated || declaration == .aiGenerated { return .aiGenerated }
        if wasAIAssisted || declaration == .aiAssisted { return .aiAssisted }
        if declaration == .unknown { return .none }
        return .none
    }

    // MARK: - "Why am I seeing this?" text

    func whyThisPost(for contentId: String) async -> String {
        guard flags.whyThisPostEnabled else { return "" }
        if let record = await transparencyRecord(for: contentId, contentType: .post) {
            var parts: [String] = []
            if record.wasAIGenerated { parts.append("This content is AI-generated.") }
            else if record.wasAIAssisted { parts.append("This content was created with AI assistance.") }
            return parts.joined(separator: " ")
        }
        return "Posts are ranked by safety, usefulness, and community health — not just likes."
    }

    // MARK: - Parse

    private func parseRecord(_ data: [String: Any], contentId: String, contentType: ContentSurface) -> TSAITransparencyRecord {
        let labelTypeStr = data["labelType"] as? String ?? "none"
        return TSAITransparencyRecord(
            contentId: contentId,
            contentType: contentType,
            wasAIGenerated: data["wasAIGenerated"] as? Bool ?? false,
            wasAIAssisted: data["wasAIAssisted"] as? Bool ?? false,
            aiModelsUsed: data["aiModelsUsed"] as? [String] ?? [],
            labelShown: data["labelShown"] as? Bool ?? false,
            labelType: AILabelType(rawValue: labelTypeStr) ?? .none
        )
    }
}
