//
//  ChurchAIService.swift
//  AMENAPP
//
//  AI-powered features for church content: sermon analysis, recap drafts,
//  scripture extraction, reflection prompts, and discussion starters.
//
//  Routing:
//  - All requests are routed through BereanCoreService / BereanAnswerEngine.
//  - The church-voice system prompt is appended at the BereanCoreService layer;
//    this service only assembles the content payload.
//
//  Design notes:
//  - `isProcessing` gates duplicate concurrent calls at the UI layer.
//  - Reflection and discussion prompts use hardcoded safe defaults when the
//    AI response is unavailable, so the UI always has something to render.
//  - `analyzeSermon` is the primary entry point; all other methods are
//    lightweight helpers that compose on top of the same infrastructure.
//

import Foundation
// import FirebaseFirestore   ← add when Firebase SDK is linked (for caching responses)
// import FirebaseFunctions   ← add when Firebase SDK is linked (for BereanCoreService routing)

// MARK: - Supporting Types

/// A structured intelligence package derived from a single sermon.
struct SermonIntelligence {

    /// A concise summary of the sermon's core message (2–4 sentences).
    let summary: String

    /// Scripture references cited or alluded to during the sermon (e.g. "John 3:16").
    let scriptureReferences: [String]

    /// High-level theological topics covered (e.g. "Grace", "Forgiveness", "Identity in Christ").
    let topics: [String]

    /// Key takeaway statements suitable for social sharing or note-taking.
    let keyTakeaways: [String]

    /// Personal reflection prompts generated from the sermon content.
    let reflectionPrompts: [String]

    /// Community discussion starters generated from the sermon content.
    let discussionPrompts: [String]

    /// Curated follow-up study resources or related scripture passages.
    let studyFollowUps: [String]
}

// MARK: - Service

/// Provides AI-powered features for church content.
///
/// Routes to Berean AI infrastructure (BereanCoreService / BereanAnswerEngine)
/// for sermon analysis, recap generation, and prompt synthesis.
///
/// Results may optionally be cached in Firestore under `sermonIntelligence/{sermonId}`
/// to avoid redundant AI calls for the same content.
@MainActor
final class ChurchAIService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastError: Error?

    // Firestore / Functions placeholders:
    // private let db = Firestore.firestore()
    // private let functions = Functions.functions()
    // private let berean = BereanCoreService.shared

    // MARK: - Default Prompts

    /// Safe-default reflection prompts shown when AI generation is unavailable.
    private static let defaultReflectionPrompts: [String] = [
        "What stood out to you from today's message?",
        "What scripture stayed with you?",
        "How will you apply this in your life this week?",
        "What would you like prayer for after hearing this?"
    ]

    /// Safe-default discussion starters shown when AI generation is unavailable.
    private static let defaultDiscussionPrompts: [String] = [
        "What was the main message you heard today?",
        "Was there a moment that especially moved you?",
        "How is God speaking to you through this sermon?"
    ]

    // MARK: - Sermon Analysis

    /// Generates a full intelligence package from a sermon transcript or notes.
    ///
    /// Routes the combined prompt to BereanCoreService with a church-voice system
    /// context. Parses the structured JSON response into a ``SermonIntelligence`` value.
    ///
    /// If `transcript` and `notes` are both nil the method returns a default
    /// intelligence package with empty content and the standard safe prompts.
    ///
    /// - Parameters:
    ///   - title: The sermon title.
    ///   - transcript: Full or partial transcript text, if available.
    ///   - notes: Preacher or note-taker notes, if available.
    /// - Returns: A ``SermonIntelligence`` value. Falls back to safe defaults on AI failure.
    /// - Throws: ``ChurchAIError.processingFailed`` if BereanCoreService returns an error.
    func analyzeSermon(
        title: String,
        transcript: String?,
        notes: String?
    ) async throws -> SermonIntelligence {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            // Build content payload for BereanCoreService:
            // var contentParts: [String] = ["Sermon title: \(title)"]
            // if let transcript { contentParts.append("Transcript:\n\(transcript)") }
            // if let notes       { contentParts.append("Notes:\n\(notes)") }
            // let payload = contentParts.joined(separator: "\n\n")
            //
            // Route to Berean:
            // let response = try await berean.analyze(payload, context: .sermonIntelligence)
            // return try parseSermonIntelligence(from: response)

            // Stub — returns safe defaults until BereanCoreService is wired:
            return SermonIntelligence(
                summary: "",
                scriptureReferences: [],
                topics: [],
                keyTakeaways: [],
                reflectionPrompts: Self.defaultReflectionPrompts,
                discussionPrompts: Self.defaultDiscussionPrompts,
                studyFollowUps: []
            )
        } catch {
            lastError = error
            throw ChurchAIError.processingFailed(underlying: error)
        }
    }

    // MARK: - Recap Draft Generation

    /// Generates a recap post draft from core sermon metadata.
    ///
    /// Uses a church-voice prompt to produce a short, shareable recap
    /// (approximately 150–200 words) suitable for the church's public feed or Stories.
    ///
    /// - Parameters:
    ///   - title: The sermon title.
    ///   - scripture: The primary scripture reference.
    ///   - preacher: The name of the preacher.
    /// - Returns: A draft string for the church to review and publish.
    /// - Throws: ``ChurchAIError.processingFailed`` if BereanCoreService returns an error.
    func generateSermonRecapDraft(
        title: String,
        scripture: String,
        preacher: String
    ) async throws -> String {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            // Route to BereanCoreService for church-voice recap generation:
            // let prompt = """
            // Write a warm, shareable church recap post (150–200 words) for the following sermon.
            // Title: \(title)
            // Scripture: \(scripture)
            // Preacher: \(preacher)
            // Use an inviting tone that reflects a welcoming faith community.
            // """
            // return try await berean.generate(prompt, context: .churchRecap)

            return ""
        } catch {
            lastError = error
            throw ChurchAIError.processingFailed(underlying: error)
        }
    }

    // MARK: - Live Reflection Prompts

    /// Suggests reflection prompts suitable for display during or immediately after a live session.
    ///
    /// Prompts are contextualised by series title when available. Returns safe defaults
    /// if the AI call fails so the live surface always has content to render.
    ///
    /// - Parameter seriesTitle: The sermon series name, if the service is part of a series.
    /// - Returns: An array of 2–4 reflection prompt strings.
    /// - Throws: ``ChurchAIError.processingFailed`` if BereanCoreService returns an error.
    func liveReflectionPrompts(seriesTitle: String?) async throws -> [String] {
        // Route to BereanCoreService if seriesTitle is provided for richer context:
        // if let seriesTitle {
        //     let prompt = "Generate 3 live reflection prompts for a sermon in the '\(seriesTitle)' series."
        //     let response = try? await berean.generate(prompt, context: .liveReflection)
        //     if let prompts = parsePromptList(from: response) { return prompts }
        // }

        // Safe defaults — always returned when AI is unavailable:
        return [
            "What is God putting on your heart through this message?",
            "Share a prayer request after hearing today's sermon."
        ]
    }

    // MARK: - Private Helpers

    /// Parses a structured JSON response from BereanCoreService into a ``SermonIntelligence`` value.
    ///
    /// Expected JSON shape:
    /// ```json
    /// {
    ///   "summary": "...",
    ///   "scriptureReferences": ["..."],
    ///   "topics": ["..."],
    ///   "keyTakeaways": ["..."],
    ///   "reflectionPrompts": ["..."],
    ///   "discussionPrompts": ["..."],
    ///   "studyFollowUps": ["..."]
    /// }
    /// ```
    private func parseSermonIntelligence(from jsonString: String) throws -> SermonIntelligence {
        guard let data = jsonString.data(using: .utf8) else {
            throw ChurchAIError.parseError
        }
        let decoder = JSONDecoder()
        return try decoder.decode(SermonIntelligence.self, from: data)
    }
}

// MARK: - SermonIntelligence Codable

extension SermonIntelligence: Codable {}

// MARK: - Errors

enum ChurchAIError: LocalizedError {
    case processingFailed(underlying: Error)
    case parseError
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .processingFailed(let underlying):
            return "Sermon analysis failed: \(underlying.localizedDescription)"
        case .parseError:
            return "Could not parse the AI response."
        case .quotaExceeded:
            return "AI request quota exceeded. Please try again later."
        }
    }
}
