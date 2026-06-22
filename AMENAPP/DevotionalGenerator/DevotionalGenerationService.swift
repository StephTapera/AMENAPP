//
//  DevotionalGenerationService.swift
//  AMENAPP
//
//  Orchestrates the full devotional generation pipeline:
//  1. Gather user context (church notes, prayers, prior Selah sessions)
//  2. Recommend scripture passages for the topic via DevotionalTopicMap + YouVersion
//  3. Build a structured prompt and call ClaudeService
//  4. Parse the structured AI response into a DevotionalResponse
//  5. Persist the completed devotional to Firestore
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class DevotionalGenerationService: ObservableObject {
    static let shared = DevotionalGenerationService()

    // MARK: - Dependencies

    private lazy var db = Firestore.firestore()
    private let selahService = SelahService.shared

    private var userId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private init() {}

    // MARK: - Public Entry Point

    /// Generate a complete devotional from the given context.
    /// Calls `onPhase` as the pipeline advances through generation phases.
    func generate(
        context: DevotionalContext,
        onPhase: @escaping (DevotionalGenerationPhase) -> Void
    ) async throws -> DevotionalResponse {

        guard !userId.isEmpty else {
            throw DevotionalError.notAuthenticated
        }

        let request = DevotionalRequest(userId: userId, context: context)

        // Phase 1: Gather user context
        onPhase(.gatheringContext)
        let sourceBundle = await selahService.buildSourceBundle(
            forVerses: context.selectedVerses,
            query: context.topic,
            limit: 4
        )

        // Phase 2: Recommend scripture
        onPhase(.fetchingScripture)
        let scriptures = await recommendScripture(for: context)

        // Phase 3: Compose via Claude
        onPhase(.composing)
        let rawJSON = try await callClaude(
            request: request,
            sourceBundle: sourceBundle,
            scriptures: scriptures
        )

        // Phase 4: Parse
        let devotional = try parseResponse(rawJSON: rawJSON, request: request, scriptures: scriptures)

        // Phase 5: Safety
        onPhase(.validatingSafety)
        let safeDevotional = DevotionalSafetyService.shared.applyGuardrails(
            to: devotional,
            mode: context.safetyMode
        )

        // Persist
        try await persist(devotional: safeDevotional)

        onPhase(.complete)
        return safeDevotional
    }

    // MARK: - Scripture Recommendation

    /// Fetches scripture references for the topic. Prefers user-selected verses,
    /// then falls back to the topic map, then requests 2 passages from Claude.
    func recommendScripture(for context: DevotionalContext) async -> [ScripturePassage] {
        var refs: [String] = context.selectedVerses

        // Fill in from topic map if user didn't pre-select
        if refs.isEmpty {
            refs = Array(DevotionalTopicMap.passages(for: context.topic).prefix(4))
        }

        // Fetch actual text for each ref
        var passages: [ScripturePassage] = []
        for ref in refs.prefix(4) {
            if let passage = try? await YouVersionBibleService.shared.fetchVerse(reference: ref) {
                passages.append(passage)
            }
        }

        // If we still have fewer than 2 passages, let Claude pick references
        if passages.count < 2 {
            let aiRefs = await fetchScriptureRefsFromAI(topic: context.topic)
            for ref in aiRefs.prefix(3) {
                if let passage = try? await YouVersionBibleService.shared.fetchVerse(reference: ref) {
                    passages.append(passage)
                }
            }
        }

        return Array(passages.prefix(4))
    }

    private func fetchScriptureRefsFromAI(topic: String) async -> [String] {
        let prompt = """
        List 3 key Bible verse references (chapter:verse only, no text) \
        for the topic "\(topic)". Format: one reference per line, e.g. "John 3:16".
        """
        var result = ""
        do {
            let stream = ClaudeService.shared.sendMessage(
                prompt, maxTokens: 150, temperature: 0.3, mode: .scholar
            )
            for try await chunk in stream { result += chunk }
        } catch {}

        return result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 4 }
    }

    // MARK: - Claude Prompt

    private func callClaude(
        request: DevotionalRequest,
        sourceBundle: SelahSourceBundle,
        scriptures: [ScripturePassage]
    ) async throws -> String {

        let ctx = request.context
        let scriptureBlock = scriptures.prefix(4).map {
            "\($0.reference) (\($0.version.rawValue)): \($0.text.prefix(300))"
        }.joined(separator: "\n")

        let userContextBlock = sourceBundle.isEmpty ? "" : """

        USER'S PERSONAL SPIRITUAL CONTEXT (for grounding):
        \(sourceBundle.promptContext(limit: 800))
        """

        let communityInstructions = ctx.communityMode != .personal
            ? "\nInclude a 'community' section with 2-3 discussion prompts for \(ctx.communityMode.rawValue.lowercased())s."
            : ""

        let specificQuestion = ctx.specificQuestion.map { "\nThe user specifically asks: \"\($0)\"" } ?? ""

        let prompt = """
        You are a Spirit-led devotional writer for the AMEN Christian community app. \
        Write a complete, structured devotional in JSON format. \
        Tone: \(ctx.tone.promptDescription). \
        Audience: \(ctx.communityMode.promptNuance). \
        Topic: \(ctx.topic.isEmpty ? "general daily walk with God" : ctx.topic).\(specificQuestion)

        SCRIPTURE PROVIDED:
        \(scriptureBlock)
        \(userContextBlock)

        Return ONLY valid JSON (no markdown fences) matching this schema:
        {
          "title": "string — an evocative 5-8 word title",
          "openingVerse": { "reference": "string", "whyThisVerse": "string (1 sentence)" },
          "additionalVerses": [{ "reference": "string", "whyThisVerse": "string" }],
          "reflectionHeading": "string",
          "reflectionBody": "string (3-4 paragraphs, warm, theologically careful)",
          "prayerHeading": "string",
          "prayerBody": "string (2-3 paragraphs, first-person prayer)",
          "practiceSteps": ["string", "string", "string"],
          "communityPrompts": ["string", "string"]\(communityInstructions.isEmpty ? " or []" : ""),
          "topicTags": ["string", "string", "string"]
        }
        """

        var accumulated = ""
        let stream = ClaudeService.shared.sendMessage(
            prompt,
            maxTokens: 2200,
            temperature: 0.68,
            mode: .shepherd
        )
        for try await chunk in stream {
            accumulated += chunk
        }
        return accumulated
    }

    // MARK: - Response Parsing

    private func parseResponse(
        rawJSON: String,
        request: DevotionalRequest,
        scriptures: [ScripturePassage]
    ) throws -> DevotionalResponse {

        // Strip possible markdown fences
        var json = rawJSON
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            let lines = json.components(separatedBy: "\n")
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw DevotionalError.parseFailure
        }

        let title = dict["title"] as? String ?? "Your Devotional"

        // Opening verse
        let openingVerseDict = dict["openingVerse"] as? [String: String] ?? [:]
        let openingRef = openingVerseDict["reference"] ?? scriptures.first?.reference ?? ""
        let openingText = scriptures.first(where: { $0.reference == openingRef })?.text
            ?? scriptures.first?.text ?? ""
        let openingVersion = scriptures.first?.version.rawValue ?? "KJV" // TODO(legal): was NIV default — changed to KJV per AMEN-CONTENT-001
        let openingVerse = DevotionalScriptureCard(
            reference: openingRef,
            text: openingText,
            version: openingVersion,
            whyThisVerse: openingVerseDict["whyThisVerse"] ?? ""
        )

        // Additional verses
        let additionalDicts = dict["additionalVerses"] as? [[String: String]] ?? []
        let additionalScriptures: [DevotionalScriptureCard] = additionalDicts.compactMap { d in
            guard let ref = d["reference"] else { return nil }
            let text = scriptures.first(where: { $0.reference == ref })?.text ?? ""
            let version = scriptures.first(where: { $0.reference == ref })?.version.rawValue ?? "KJV" // TODO(legal): was NIV default — changed to KJV per AMEN-CONTENT-001
            return DevotionalScriptureCard(
                reference: ref,
                text: text,
                version: version,
                whyThisVerse: d["whyThisVerse"] ?? ""
            )
        }

        let reflection = DevotionalReflectionCard(
            heading: dict["reflectionHeading"] as? String ?? "Reflection",
            body: dict["reflectionBody"] as? String ?? ""
        )

        let prayer = DevotionalPrayerCard(
            heading: dict["prayerHeading"] as? String ?? "Prayer",
            body: dict["prayerBody"] as? String ?? ""
        )

        let practiceSteps = dict["practiceSteps"] as? [String] ?? []
        let practice = DevotionalPracticeCard(steps: practiceSteps)

        let communityPrompts = dict["communityPrompts"] as? [String] ?? []
        let community: DevotionalCommunityCard? = communityPrompts.isEmpty ? nil
            : DevotionalCommunityCard(prompts: communityPrompts)

        let topicTags = dict["topicTags"] as? [String] ?? []

        return DevotionalResponse(
            requestId: request.id,
            userId: request.userId,
            title: title,
            openingVerse: openingVerse,
            additionalScriptures: additionalScriptures,
            reflection: reflection,
            prayer: prayer,
            practice: practice,
            community: community,
            tone: request.context.tone,
            topicTags: topicTags
        )
    }

    // MARK: - Persistence

    func persist(devotional: DevotionalResponse) async throws {
        guard !userId.isEmpty else { return }
        let data = try Firestore.Encoder().encode(devotional)
        try await db
            .collection("users/\(userId)/devotionals")
            .document(devotional.id)
            .setData(data)
    }

    /// Save the devotional to a new Church Note and return the note ID.
    func saveToChurchNotes(devotional: DevotionalResponse) async throws -> String {
        guard !userId.isEmpty else { throw DevotionalError.notAuthenticated }

        let scriptureLine = devotional.allScriptureRefs.joined(separator: " • ")
        let content = """
        # \(devotional.title)

        **Scripture:** \(scriptureLine)

        ## Reflection
        \(devotional.reflection.body)

        ## Prayer
        \(devotional.prayer.body)

        ## Live It Out
        \(devotional.practice.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """

        let noteData: [String: Any] = [
            "title": devotional.title,
            "content": content,
            "tags": devotional.topicTags,
            "source": "devotionalGenerator",
            "devotionalId": devotional.id,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let ref = try await db
            .collection("users/\(userId)/churchNotes")
            .addDocument(data: noteData)

        // Update Firestore record with the note link
        try await db
            .collection("users/\(userId)/devotionals")
            .document(devotional.id)
            .updateData(["isSavedToNotes": true, "churchNoteId": ref.documentID])

        return ref.documentID
    }

    /// Load previously generated devotionals, newest first.
    func loadHistory(limit: Int = 20) async throws -> [DevotionalResponse] {
        guard !userId.isEmpty else { return [] }
        let snapshot = try await db
            .collection("users/\(userId)/devotionals")
            .order(by: "generatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? Firestore.Decoder().decode(DevotionalResponse.self, from: $0.data())
        }
    }

    // MARK: - Errors

    enum DevotionalError: LocalizedError {
        case notAuthenticated
        case parseFailure
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:       return "Please sign in to generate a devotional."
            case .parseFailure:           return "Could not parse the devotional response. Please try again."
            case .generationFailed(let m): return m
            }
        }
    }
}
