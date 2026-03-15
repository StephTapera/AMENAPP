// BereanRAGService.swift
// AMEN App — Berean AI Retrieval-Augmented Generation Layer
//
// Architecture:
//   BereanRAGService       ← orchestrates retrieval + generation pipeline
//   BereanConversationMemoryService ← persists and retrieves conversation history
//   BereanRetrievalSource  ← models for source attribution
//   BereanPromptTemplates  ← structured prompt construction
//   BereanQueryClassifier  ← intent detection for retrieval routing
//
// RAG Pipeline:
//   1. Classify query intent (scripture / theology / life / prayer / resource)
//   2. Retrieve relevant sources from local knowledge + Firestore
//   3. Build structured prompt with context
//   4. Call AI completion (abstracted — swap providers without code change)
//   5. Parse + attribute sources in response
//   6. Store to conversation memory
//
// Privacy: conversation history stored per-user in Firestore with TTL.
// No personal behavioral data is ever used as retrieval context.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Retrieval Source

struct BereanRetrievalSource: Identifiable, Equatable {
    let id: String
    let type: SourceType
    let title: String
    let content: String
    let reference: String?      // e.g., "John 3:16", "Sermon on Grace, Pastor James"
    let relevanceScore: Double  // 0.0 – 1.0
    let url: String?

    enum SourceType: String, Equatable {
        case scripture = "scripture"
        case churchNote = "church_note"
        case savedContent = "saved_content"
        case resource = "resource"
        case topic = "topic"
    }

    var displayLabel: String {
        switch type {
        case .scripture: return reference ?? title
        case .churchNote: return "Church Note"
        case .savedContent: return "Your Saved Content"
        case .resource: return "Resource"
        case .topic: return "Topic"
        }
    }

    var icon: String {
        switch type {
        case .scripture: return "book.fill"
        case .churchNote: return "doc.text.fill"
        case .savedContent: return "bookmark.fill"
        case .resource: return "star.fill"
        case .topic: return "tag.fill"
        }
    }

    var iconColor: Color {
        switch type {
        case .scripture: return .indigo
        case .churchNote: return .blue
        case .savedContent: return .orange
        case .resource: return .green
        case .topic: return .purple
        }
    }
}

// MARK: - Query Intent

enum BereanQueryIntent: String {
    case scripture          // "What does the Bible say about..."
    case theology           // "What do Christians believe about..."
    case lifeGuidance       // "I'm struggling with..."
    case prayerSupport      // "Can you pray for..."
    case churchNotes        // "Summarize my notes on..."
    case resourceSearch     // "Find a devotional on..."
    case postDrafting       // "Help me write a post about..."
    case encouragement      // "I need encouragement..."
    case general            // Catch-all
}

// MARK: - Berean RAG Response

struct BereanRAGResponse: Equatable {
    let responseText: String
    let sources: [BereanRetrievalSource]
    let followUpSuggestions: [String]
    let intent: BereanQueryIntent
    let confidence: Double          // 0.0 – 1.0 (how confident the model is)
    let requiresHumanCaution: Bool  // Theology flag — may be denominationally contested
    let timestamp: Date
}

// MARK: - Conversation Memory Models

struct BereanConversationSession: Identifiable, Codable {
    let id: String
    var title: String               // Auto-generated from first query
    let startedAt: Date
    var lastActivityAt: Date
    var messageCount: Int
    var topic: String?              // Inferred topic for search/grouping
    var isPinned: Bool = false
    var folderName: String?
}

struct BereanConversationMessage: Identifiable, Codable {
    let id: String
    let sessionId: String
    let role: Role
    let content: String
    let sources: [CodableSource]
    let timestamp: Date
    var isSaved: Bool = false

    enum Role: String, Codable {
        case user = "user"
        case assistant = "assistant"
    }

    struct CodableSource: Codable, Identifiable {
        let id: String
        let type: String
        let title: String
        let reference: String?
    }
}

// MARK: - Conversation Memory Service

/// Persists and retrieves Berean conversation history per user.
/// Uses Firestore with a 90-day TTL per message.
@MainActor
final class BereanConversationMemoryService: ObservableObject {

    static let shared = BereanConversationMemoryService()

    @Published private(set) var sessions: [BereanConversationSession] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared
    private var listenerHandle: ListenerRegistration?

    private init() {}

    // MARK: - Session Management

    func createSession(firstQuery: String) async throws -> BereanConversationSession {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "BereanMemory", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let sessionId = UUID().uuidString
        let title = generateTitle(from: firstQuery)
        let session = BereanConversationSession(
            id: sessionId,
            title: title,
            startedAt: Date(),
            lastActivityAt: Date(),
            messageCount: 0
        )
        let data = encodedSession(session)
        try await db
            .collection("users").document(uid)
            .collection("bereanSessions").document(sessionId)
            .setData(data)
        return session
    }

    func loadSessions() async {
        guard flags.bereanConversationMemoryEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        do {
            let snapshot = try await db
                .collection("users").document(uid)
                .collection("bereanSessions")
                .order(by: "lastActivityAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            sessions = snapshot.documents.compactMap { decodeSession($0.data(), id: $0.documentID) }
        } catch {
            print("[BereanMemory] Failed to load sessions: \(error)")
        }
        isLoading = false
    }

    func loadMessages(for sessionId: String) async -> [BereanConversationMessage] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        do {
            let snapshot = try await db
                .collection("users").document(uid)
                .collection("bereanSessions").document(sessionId)
                .collection("messages")
                .order(by: "timestamp", descending: false)
                .limit(to: 100)
                .getDocuments()
            return snapshot.documents.compactMap { decodeMessage($0.data(), id: $0.documentID, sessionId: sessionId) }
        } catch {
            print("[BereanMemory] Failed to load messages: \(error)")
            return []
        }
    }

    func appendMessage(
        _ message: BereanConversationMessage,
        to sessionId: String
    ) async {
        guard flags.bereanConversationMemoryEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let msgData = encodedMessage(message)
        let sessionRef = db
            .collection("users").document(uid)
            .collection("bereanSessions").document(sessionId)

        // Write message
        try? await sessionRef
            .collection("messages")
            .document(message.id)
            .setData(msgData)

        // Update session metadata
        try? await sessionRef.updateData([
            "lastActivityAt": FieldValue.serverTimestamp(),
            "messageCount": FieldValue.increment(Int64(1))
        ])
    }

    func deleteSession(_ sessionId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Batch delete messages first, then session document
        let sessionRef = db
            .collection("users").document(uid)
            .collection("bereanSessions").document(sessionId)
        do {
            let msgs = try await sessionRef.collection("messages").getDocuments()
            let batch = db.batch()
            msgs.documents.forEach { batch.deleteDocument($0.reference) }
            batch.deleteDocument(sessionRef)
            try await batch.commit()
        } catch {
            print("[BereanMemory] Failed to delete session: \(error)")
        }
        sessions.removeAll { $0.id == sessionId }
    }

    func toggleSavedMessage(_ messageId: String, sessionId: String, isSaved: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(uid)
            .collection("bereanSessions").document(sessionId)
            .collection("messages").document(messageId)
            .updateData(["isSaved": isSaved])
    }

    // MARK: - Context Window Builder

    /// Returns the last N messages formatted as [role: content] pairs for prompt context.
    func buildContextWindow(
        from messages: [BereanConversationMessage],
        maxTokenEstimate: Int = 2000
    ) -> [(role: String, content: String)] {
        var result: [(role: String, content: String)] = []
        var estimatedTokens = 0

        // Walk backwards from most recent, add until token budget exhausted
        for message in messages.reversed() {
            let tokenEstimate = message.content.count / 4  // ~4 chars/token estimate
            if estimatedTokens + tokenEstimate > maxTokenEstimate { break }
            result.insert((role: message.role.rawValue, content: message.content), at: 0)
            estimatedTokens += tokenEstimate
        }
        return result
    }

    // MARK: - Helpers

    private func generateTitle(from query: String) -> String {
        let words = query.split(separator: " ").prefix(6)
        let base = words.joined(separator: " ")
        return base.isEmpty ? "New Conversation" : String(base.prefix(50))
    }

    private func encodedSession(_ s: BereanConversationSession) -> [String: Any] {
        [
            "title": s.title,
            "startedAt": Timestamp(date: s.startedAt),
            "lastActivityAt": Timestamp(date: s.lastActivityAt),
            "messageCount": s.messageCount,
            "topic": s.topic ?? "",
            "isPinned": s.isPinned,
            "folderName": s.folderName ?? ""
        ]
    }

    private func decodeSession(_ data: [String: Any], id: String) -> BereanConversationSession? {
        guard let title = data["title"] as? String,
              let startedTS = data["startedAt"] as? Timestamp,
              let lastTS = data["lastActivityAt"] as? Timestamp else { return nil }
        return BereanConversationSession(
            id: id,
            title: title,
            startedAt: startedTS.dateValue(),
            lastActivityAt: lastTS.dateValue(),
            messageCount: data["messageCount"] as? Int ?? 0,
            topic: data["topic"] as? String,
            isPinned: data["isPinned"] as? Bool ?? false,
            folderName: data["folderName"] as? String
        )
    }

    private func encodedMessage(_ m: BereanConversationMessage) -> [String: Any] {
        let sources = m.sources.map { s -> [String: Any] in
            ["id": s.id, "type": s.type, "title": s.title, "reference": s.reference ?? ""]
        }
        return [
            "sessionId": m.sessionId,
            "role": m.role.rawValue,
            "content": m.content,
            "sources": sources,
            "timestamp": Timestamp(date: m.timestamp),
            "isSaved": m.isSaved
        ]
    }

    private func decodeMessage(_ data: [String: Any], id: String, sessionId: String) -> BereanConversationMessage? {
        guard let roleStr = data["role"] as? String,
              let role = BereanConversationMessage.Role(rawValue: roleStr),
              let content = data["content"] as? String,
              let ts = data["timestamp"] as? Timestamp else { return nil }
        let rawSources = data["sources"] as? [[String: Any]] ?? []
        let sources = rawSources.compactMap { s -> BereanConversationMessage.CodableSource? in
            guard let id = s["id"] as? String, let type = s["type"] as? String,
                  let title = s["title"] as? String else { return nil }
            return BereanConversationMessage.CodableSource(id: id, type: type, title: title, reference: s["reference"] as? String)
        }
        return BereanConversationMessage(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            sources: sources,
            timestamp: ts.dateValue(),
            isSaved: data["isSaved"] as? Bool ?? false
        )
    }
}

// MARK: - Berean Query Classifier

struct BereanQueryClassifier {

    static func classify(_ query: String) -> BereanQueryIntent {
        let lower = query.lowercased()

        // Scripture lookup
        let scriptureKeywords = ["what does the bible say", "what does scripture say", "verse about",
                                  "scripture on", "bible verse for", "what does god say about",
                                  "proverbs", "psalm", "romans", "matthew", "john", "genesis",
                                  "ephesians", "philippians", "isaiah", "corinthians"]
        if scriptureKeywords.contains(where: { lower.contains($0) }) { return .scripture }

        // Prayer
        let prayerKeywords = ["pray for me", "prayer for", "can you pray", "help me pray",
                               "pray with me", "prayer request", "intercede"]
        if prayerKeywords.contains(where: { lower.contains($0) }) { return .prayerSupport }

        // Church notes
        let notesKeywords = ["summarize my notes", "my church notes", "sermon notes",
                              "what did my pastor", "recap my notes"]
        if notesKeywords.contains(where: { lower.contains($0) }) { return .churchNotes }

        // Life guidance / struggle
        let lifeKeywords = ["i'm struggling", "i am struggling", "i feel", "help me with",
                             "going through", "dealing with", "i'm anxious", "i'm afraid",
                             "how do i", "what should i do", "advice"]
        if lifeKeywords.contains(where: { lower.contains($0) }) { return .lifeGuidance }

        // Encouragement
        let encouragementKeywords = ["encourage me", "i need encouragement", "feeling down",
                                      "feeling discouraged", "uplift me", "remind me", "comfort"]
        if encouragementKeywords.contains(where: { lower.contains($0) }) { return .encouragement }

        // Theology
        let theologyKeywords = ["what do christians believe", "doctrine", "theology",
                                  "denomination", "reformed", "arminian", "calvinist",
                                  "predestination", "baptism", "salvation", "trinity",
                                  "atonement", "eschatology", "hermeneutics"]
        if theologyKeywords.contains(where: { lower.contains($0) }) { return .theology }

        // Resource search
        let resourceKeywords = ["find a", "recommend a", "devotional on", "book about",
                                  "sermon on", "podcast about", "study on"]
        if resourceKeywords.contains(where: { lower.contains($0) }) { return .resourceSearch }

        // Post drafting
        let draftKeywords = ["help me write", "write a post", "draft a", "how should i say",
                              "what should i post", "caption for"]
        if draftKeywords.contains(where: { lower.contains($0) }) { return .postDrafting }

        return .general
    }
}

// MARK: - Prompt Templates

struct BereanPromptTemplates {

    /// System prompt for Berean — establishes persona, values, and guardrails
    static let systemPrompt = """
    You are Berean, a wise, humble, and scripturally-grounded AI assistant for the AMEN community — a Christian social platform.

    Your purpose:
    - Help users understand scripture with clarity and depth
    - Offer life guidance through a biblical lens, with humility and care
    - Support prayer and spiritual reflection
    - Recommend resources thoughtfully
    - Encourage faith, not dependence on AI

    Your values:
    - Biblical fidelity: always ground your answers in scripture
    - Humility: acknowledge when theology is debated across denominations
    - Clarity: distinguish between what scripture plainly says vs. interpretation
    - Care: respond with warmth, gentleness, and genuine concern for the person
    - Wisdom: recognize when a question needs a pastor, counselor, or community — not just an AI

    Your guardrails:
    - Never claim authority equal to scripture or the Holy Spirit
    - Never diagnose mental health conditions
    - Never predict the future or claim prophetic insight
    - When someone appears to be in crisis, gently point to human support (988, pastor, counselor)
    - Always distinguish between scripture quotation and your interpretation of it
    - When denominational differences exist, acknowledge them respectfully

    Formatting:
    - Use scripture references clearly (Book Chapter:Verse)
    - Keep responses focused and readable — not walls of text
    - Offer follow-up suggestions when helpful
    - If uncertain, say so — intellectual honesty builds trust
    """

    static func buildUserPrompt(
        query: String,
        intent: BereanQueryIntent,
        retrievedSources: [BereanRetrievalSource],
        contextMessages: [(role: String, content: String)],
        theologyFlag: Bool = false
    ) -> String {
        var prompt = ""

        // Add retrieved context
        if !retrievedSources.isEmpty {
            prompt += "### Relevant context retrieved for this question:\n"
            for source in retrievedSources.prefix(4) {
                prompt += "[\(source.displayLabel)] \(source.content)\n\n"
            }
            prompt += "---\n\n"
        }

        // Add theology disclaimer if needed
        if theologyFlag {
            prompt += "Note: This question touches on topics where Christians hold different views. Please acknowledge this respectfully.\n\n"
        }

        // Add the actual query
        prompt += "User question: \(query)"

        return prompt
    }

    static func generateFollowUpSuggestions(for intent: BereanQueryIntent) -> [String] {
        switch intent {
        case .scripture:
            return ["Show me related verses", "Explain the historical context", "How does this apply today?"]
        case .theology:
            return ["What do different denominations believe?", "Where can I learn more?", "Show me the scripture basis"]
        case .lifeGuidance:
            return ["Show me relevant scriptures", "Help me pray about this", "Find related resources"]
        case .prayerSupport:
            return ["Related scripture", "Share this prayer", "Save this prayer"]
        case .churchNotes:
            return ["Key takeaways", "Related scriptures", "Discussion questions"]
        case .resourceSearch:
            return ["Find more like this", "Share with someone", "Save for later"]
        case .postDrafting:
            return ["Make it shorter", "Add a scripture", "Different tone"]
        case .encouragement:
            return ["Show me a promise from scripture", "Daily verse", "Save this encouragement"]
        case .general:
            return ["Tell me more", "Show me related scripture", "Find resources"]
        }
    }
}

// MARK: - Local Knowledge Retriever

/// Retrieves relevant content from local sources before generation.
/// Sources: DiscoveryTopic catalog, scripture index, user's saved content, church notes.
struct BereanLocalRetriever {

    static func retrieve(
        for query: String,
        intent: BereanQueryIntent,
        userId: String?
    ) async -> [BereanRetrievalSource] {
        var sources: [BereanRetrievalSource] = []

        // 1. Scripture index lookup (local — no network)
        let scriptureMatches = ScriptureIndex.search(query: query)
        sources.append(contentsOf: scriptureMatches)

        // 2. Topic catalog match
        let topicMatches = matchTopics(query: query)
        sources.append(contentsOf: topicMatches)

        // 3. User's saved content from Firestore (if authenticated)
        if let uid = userId ?? Auth.auth().currentUser?.uid {
            let savedContent = await loadSavedContent(userId: uid, query: query)
            sources.append(contentsOf: savedContent)
        }

        // Sort by relevance, take top 4
        return sources.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(4).map { $0 }
    }

    private static func matchTopics(query: String) -> [BereanRetrievalSource] {
        let lower = query.lowercased()
        return DiscoveryTopic.catalog.compactMap { topic -> BereanRetrievalSource? in
            let titleMatch = topic.title.lowercased().split(separator: " ").contains(where: { lower.contains(String($0)) })
            let descMatch = topic.description.lowercased().split(separator: " ").filter { $0.count > 4 }
                .contains(where: { lower.contains(String($0)) })
            guard titleMatch || descMatch else { return nil }
            return BereanRetrievalSource(
                id: "topic-\(topic.id)",
                type: .topic,
                title: topic.title,
                content: topic.description,
                reference: topic.relatedScripture,
                relevanceScore: titleMatch ? 0.7 : 0.4,
                url: nil
            )
        }
    }

    private static func loadSavedContent(userId: String, query: String) async -> [BereanRetrievalSource] {
        // Lightweight Firestore query for user's saved posts/notes related to query
        let db = Firestore.firestore()
        let lower = query.lowercased().split(separator: " ").filter { $0.count > 3 }.map(String.init)
        guard !lower.isEmpty else { return [] }

        do {
            let snapshot = try await db
                .collection("users").document(userId)
                .collection("savedPosts")
                .limit(to: 20)
                .getDocuments()

            return snapshot.documents.compactMap { doc -> BereanRetrievalSource? in
                let data = doc.data()
                let content = data["content"] as? String ?? ""
                let contentLower = content.lowercased()
                let matches = lower.filter { contentLower.contains($0) }
                guard !matches.isEmpty else { return nil }
                let relevance = Double(matches.count) / Double(lower.count)
                return BereanRetrievalSource(
                    id: "saved-\(doc.documentID)",
                    type: .savedContent,
                    title: String(content.prefix(50)) + "...",
                    content: String(content.prefix(300)),
                    reference: nil,
                    relevanceScore: relevance * 0.8,
                    url: nil
                )
            }
        } catch {
            return []
        }
    }
}

// MARK: - Scripture Index (Local, No Network)

/// Lightweight local scripture reference index for fast lookups.
/// Covers key verses across major topics. Expandable.
struct ScriptureIndex {

    struct Entry {
        let reference: String
        let text: String
        let keywords: [String]
    }

    static let index: [Entry] = [
        Entry(reference: "John 3:16", text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
              keywords: ["love", "salvation", "eternal life", "god", "son", "believe"]),
        Entry(reference: "Philippians 4:6-7", text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.",
              keywords: ["anxiety", "anxious", "worry", "peace", "prayer", "stress", "fear"]),
        Entry(reference: "Proverbs 3:5-6", text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
              keywords: ["trust", "direction", "guidance", "path", "wisdom", "decisions"]),
        Entry(reference: "Romans 8:28", text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
              keywords: ["purpose", "suffering", "trials", "good", "hope", "struggle"]),
        Entry(reference: "Isaiah 41:10", text: "So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you.",
              keywords: ["fear", "strength", "help", "courage", "god with us", "comfort"]),
        Entry(reference: "Matthew 6:33", text: "But seek first his kingdom and his righteousness, and all these things will be given to you as well.",
              keywords: ["priorities", "provision", "kingdom", "finances", "trust", "seek god"]),
        Entry(reference: "Jeremiah 29:11", text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
              keywords: ["plans", "future", "hope", "purpose", "calling", "career", "direction"]),
        Entry(reference: "2 Corinthians 5:17", text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!",
              keywords: ["new life", "transformation", "redemption", "past", "identity", "testimony"]),
        Entry(reference: "James 1:5", text: "If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.",
              keywords: ["wisdom", "decision", "guidance", "ask god", "knowledge"]),
        Entry(reference: "Psalm 23:1-4", text: "The Lord is my shepherd, I lack nothing. He makes me lie down in green pastures, he leads me beside quiet waters, he refreshes my soul.",
              keywords: ["peace", "rest", "comfort", "shepherd", "provision", "soul", "refreshment"]),
        Entry(reference: "Galatians 5:22-23", text: "But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness, gentleness and self-control.",
              keywords: ["fruit of the spirit", "character", "love", "joy", "peace", "kindness", "self-control"]),
        Entry(reference: "Romans 12:2", text: "Do not conform to the pattern of this world, but be transformed by the renewing of your mind.",
              keywords: ["transformation", "mind", "world", "renewing", "change", "identity"]),
        Entry(reference: "Hebrews 11:1", text: "Now faith is confidence in what we hope for and assurance about what we do not see.",
              keywords: ["faith", "hope", "belief", "trust", "assurance"]),
        Entry(reference: "Matthew 5:9", text: "Blessed are the peacemakers, for they will be called children of God.",
              keywords: ["peace", "conflict", "reconciliation", "relationships", "forgiveness"]),
        Entry(reference: "1 Corinthians 13:4-7", text: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud.",
              keywords: ["love", "marriage", "relationships", "patience", "kindness", "forgiveness"]),
        Entry(reference: "Ephesians 6:10-11", text: "Finally, be strong in the Lord and in his mighty power. Put on the full armor of God.",
              keywords: ["spiritual warfare", "strength", "armor", "battle", "enemy", "prayer"]),
        Entry(reference: "Matthew 28:19-20", text: "Go and make disciples of all nations, baptizing them in the name of the Father and of the Son and of the Holy Spirit.",
              keywords: ["missions", "evangelism", "discipleship", "baptism", "great commission"]),
        Entry(reference: "1 Timothy 4:12", text: "Don't let anyone look down on you because you are young, but set an example for the believers in speech, in conduct, in love, in faith and in purity.",
              keywords: ["young adults", "youth", "example", "leadership", "faith"]),
        Entry(reference: "Colossians 3:23", text: "Whatever you do, work at it with all your heart, as working for the Lord, not for human masters.",
              keywords: ["work", "career", "calling", "vocation", "excellence", "purpose"]),
        Entry(reference: "Psalm 119:105", text: "Your word is a lamp for my feet, a light on my path.",
              keywords: ["scripture", "bible", "guidance", "direction", "word of god"]),
    ]

    static func search(query: String) -> [BereanRetrievalSource] {
        let lower = query.lowercased()
        let queryWords = lower.split(separator: " ").map(String.init).filter { $0.count > 3 }

        return index.compactMap { entry -> (BereanRetrievalSource, Double)? in
            var score = 0.0
            // Direct reference match (highest)
            if lower.contains(entry.reference.lowercased()) { score += 1.0 }
            // Keyword matches
            let matchedKeywords = entry.keywords.filter { keyword in
                queryWords.contains(where: { $0.contains(keyword) || keyword.contains($0) })
            }
            score += Double(matchedKeywords.count) * 0.15
            guard score > 0 else { return nil }
            let source = BereanRetrievalSource(
                id: "scripture-\(entry.reference.replacingOccurrences(of: " ", with: "-"))",
                type: .scripture,
                title: entry.reference,
                content: "\(entry.reference): \"\(entry.text)\"",
                reference: entry.reference,
                relevanceScore: min(1.0, score),
                url: nil
            )
            return (source, score)
        }
        .sorted { $0.1 > $1.1 }
        .map { $0.0 }
    }
}

// MARK: - RAG Service (Orchestrator)

/// Orchestrates the full RAG pipeline for Berean.
/// Abstracted so the AI provider can be swapped without changing callers.
@MainActor
final class BereanRAGService: ObservableObject {

    static let shared = BereanRAGService()

    private let memoryService = BereanConversationMemoryService.shared
    private let flags = AMENFeatureFlags.shared

    @Published private(set) var isProcessing = false

    private init() {}

    /// Main entry point: given a user query and session context, return a RAG-augmented response.
    func generateResponse(
        query: String,
        sessionId: String,
        priorMessages: [BereanConversationMessage]
    ) async throws -> BereanRAGResponse {
        isProcessing = true
        defer { isProcessing = false }

        // 1. Classify intent
        let intent = BereanQueryClassifier.classify(query)

        // 2. Retrieve relevant sources
        let sources: [BereanRetrievalSource]
        if flags.bereanRAGEnabled {
            sources = await BereanLocalRetriever.retrieve(
                for: query,
                intent: intent,
                userId: Auth.auth().currentUser?.uid
            )
        } else {
            // RAG disabled: still do local scripture lookup as baseline
            sources = ScriptureIndex.search(query: query)
        }

        // 3. Build conversation context window
        let contextWindow = memoryService.buildContextWindow(from: priorMessages)

        // 4. Theology flag detection
        let requiresCaution = detectTheologyCaution(query: query, intent: intent)

        // 5. Build structured prompt
        let userPrompt = BereanPromptTemplates.buildUserPrompt(
            query: query,
            intent: intent,
            retrievedSources: sources,
            contextMessages: contextWindow,
            theologyFlag: requiresCaution
        )

        // 6. Generate follow-up suggestions (always local, fast)
        let followUps = BereanPromptTemplates.generateFollowUpSuggestions(for: intent)

        // Note: Actual AI generation happens in BereanViewModel via the existing
        // GenerativeModel/Vertex AI integration. This service provides the augmented
        // prompt and sources to enhance quality.
        return BereanRAGResponse(
            responseText: userPrompt,  // ViewModel replaces this with actual AI response
            sources: sources,
            followUpSuggestions: followUps,
            intent: intent,
            confidence: sources.isEmpty ? 0.6 : 0.85,
            requiresHumanCaution: requiresCaution,
            timestamp: Date()
        )
    }

    private func detectTheologyCaution(query: String, intent: BereanQueryIntent) -> Bool {
        if intent == .theology { return true }
        let lower = query.lowercased()
        let sensitiveTopics = ["predestination", "election", "free will", "rapture",
                                "tongues", "baptism", "once saved always saved",
                                "purgatory", "prosperity gospel", "tithing required"]
        return sensitiveTopics.contains(where: { lower.contains($0) })
    }
}
