//
//  SelahService.swift
//  AMENAPP
//
//  Central service for Selah features: source aggregation, grounded AI,
//  session persistence, theme memory, verse expansion, transformations,
//  and the verse-to-testimony workflow engine.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SelahService: ObservableObject {
    static let shared = SelahService()

    // MARK: - Published State

    @Published var sessions: [SelahSession] = []
    @Published var themes: [ThemeTag] = []
    @Published var workflows: [SelahWorkflow] = []
    @Published var isLoading = false

    // MARK: - Private

    private lazy var db = Firestore.firestore()
    private var sessionListener: ListenerRegistration?
    private var workflowListener: ListenerRegistration?

    private var userId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private init() {
        startListeningSessions()
        startListeningWorkflows()
    }

    deinit {
        sessionListener?.remove()
        workflowListener?.remove()
    }

    // MARK: - Source Aggregation

    /// Builds a SelahSourceBundle from the user's data to ground AI responses.
    func buildSourceBundle(
        forVerses verses: [String] = [],
        query: String = "",
        limit: Int = 5
    ) async -> SelahSourceBundle {
        var bundle = SelahSourceBundle(
            verses: [],
            notes: [],
            prayers: [],
            testimonies: [],
            bereanHistory: []
        )

        // Fetch verse texts
        for ref in verses.prefix(limit) {
            if let passage = try? await YouVersionBibleService.shared.fetchVerse(reference: ref) {
                bundle.verses.append(SelahVerseSource(
                    reference: passage.reference,
                    text: passage.text,
                    version: passage.version.rawValue
                ))
            }
        }

        // Fetch recent church notes
        guard !userId.isEmpty else { return bundle }

        do {
            let notesSnap = try await db.collection("users/\(userId)/churchNotes")
                .order(by: "updatedAt", descending: true)
                .limit(to: limit)
                .getDocuments()

            bundle.notes = notesSnap.documents.compactMap { doc in
                let data = doc.data()
                return SelahNoteSource(
                    noteId: doc.documentID,
                    title: data["title"] as? String ?? "",
                    contentPreview: String((data["content"] as? String ?? "").prefix(300)),
                    date: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
        } catch {
            print("[ERROR] SelahService.buildSourceBundle: failed to fetch church notes — \(error)")
        }

        // Fetch recent Berean sessions
        do {
            let sessSnap = try await db.collection("users/\(userId)/selahSessions")
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()

            bundle.bereanHistory = sessSnap.documents.compactMap { doc in
                let data = doc.data()
                return SelahBereanSource(
                    query: data["query"] as? String ?? "",
                    responsePreview: String((data["responsePreview"] as? String ?? "").prefix(300)),
                    date: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
        } catch {
            print("[ERROR] SelahService.buildSourceBundle: failed to fetch Selah sessions — \(error)")
        }

        return bundle
    }

    // MARK: - Ask Selah AI

    /// Streams a grounded AI response using the Claude service.
    func askSelah(
        query: String,
        sourceBundle: SelahSourceBundle,
        format: SelahFormat = .essay
    ) -> AsyncThrowingStream<String, Error> {
        let contextBlock = sourceBundle.promptContext()

        let systemSuffix = """
        You are Selah, a contemplative Bible study assistant within the AMEN app. \
        Ground your answers in the user's personal context provided below. \
        When citing sources, use bracketed references like [John 3:16] or [Note: Sunday Sermon]. \
        Be warm, thoughtful, and theologically careful. \
        Format your response as: \(format.rawValue).

        USER CONTEXT:
        \(contextBlock)
        """

        return ClaudeService.shared.sendMessage(
            query,
            maxTokens: 2500,
            temperature: 0.6,
            mode: .shepherd,
            systemPromptSuffix: systemSuffix
        )
    }

    // MARK: - Session Persistence

    @discardableResult
    func saveSession(
        title: String,
        query: String,
        responsePreview: String,
        format: SelahFormat,
        scriptureRefs: [String],
        tags: [String]
    ) async throws -> String {
        guard !userId.isEmpty else { throw SelahError.notAuthenticated }

        let session = SelahSession(
            userId: userId,
            title: title,
            query: query,
            responsePreview: String(responsePreview.prefix(500)),
            format: format.rawValue,
            scriptureRefs: scriptureRefs,
            tags: tags,
            createdAt: Date(),
            updatedAt: Date()
        )

        let ref = try db.collection("users/\(userId)/selahSessions")
            .addDocument(from: session)
        return ref.documentID
    }

    func deleteSession(_ sessionId: String) async throws {
        guard !userId.isEmpty else { throw SelahError.notAuthenticated }
        try await db.collection("users/\(userId)/selahSessions")
            .document(sessionId)
            .delete()
    }

    func linkNote(sessionId: String, noteId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection("users/\(userId)/selahSessions")
            .document(sessionId)
            .updateData(["linkedNoteIds": FieldValue.arrayUnion([noteId])])
    }

    func linkPrayer(sessionId: String, prayerId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection("users/\(userId)/selahSessions")
            .document(sessionId)
            .updateData(["linkedPrayerIds": FieldValue.arrayUnion([prayerId])])
    }

    func linkTestimony(sessionId: String, testimonyId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection("users/\(userId)/selahSessions")
            .document(sessionId)
            .updateData(["linkedTestimonyIds": FieldValue.arrayUnion([testimonyId])])
    }

    private func startListeningSessions() {
        guard !userId.isEmpty else { return }
        sessionListener?.remove()
        sessionListener = db.collection("users/\(userId)/selahSessions")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let docs = snapshot?.documents else { return }
                self?.sessions = docs.compactMap { try? $0.data(as: SelahSession.self) }
                self?.rebuildThemes()
            }
    }

    // MARK: - Theme Memory

    func rebuildThemes() {
        var tagCounts: [String: Int] = [:]
        for session in sessions {
            for tag in session.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        let palette: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .red, .indigo, .mint, .cyan]
        themes = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(20)
            .enumerated()
            .map { index, pair in
                ThemeTag(name: pair.key, count: pair.value, color: palette[index % palette.count])
            }
    }

    func sessions(forTheme theme: String) -> [SelahSession] {
        sessions.filter { $0.tags.contains(theme) }
    }

    /// Detect themes from text content using keyword analysis.
    func detectThemes(in text: String) -> [String] {
        let lower = text.lowercased()
        let themeKeywords: [String: [String]] = [
            "Faith": ["faith", "believe", "trust", "confidence"],
            "Grace": ["grace", "mercy", "forgiveness", "forgive"],
            "Prayer": ["pray", "prayer", "intercede", "petition"],
            "Love": ["love", "agape", "compassion", "charity"],
            "Hope": ["hope", "hopeful", "promise", "future"],
            "Wisdom": ["wisdom", "wise", "knowledge", "understanding", "discern"],
            "Salvation": ["salvation", "saved", "redeem", "redemption", "gospel"],
            "Worship": ["worship", "praise", "glory", "glorify"],
            "Suffering": ["suffer", "trial", "tribulation", "hardship", "pain"],
            "Joy": ["joy", "joyful", "rejoice", "gladness"],
            "Obedience": ["obey", "obedience", "commandment", "follow"],
            "Community": ["church", "community", "fellowship", "brother", "sister"],
            "Holiness": ["holy", "sanctif", "righteous", "pure"],
            "Identity": ["identity", "who i am", "child of god", "chosen"],
            "Purpose": ["purpose", "calling", "mission", "destiny"],
        ]

        var matched: [String] = []
        for (theme, keywords) in themeKeywords {
            if keywords.contains(where: { lower.contains($0) }) {
                matched.append(theme)
            }
        }
        return Array(matched.prefix(5))
    }

    // MARK: - Verse Expansion (YouVersion)

    func expandVerse(reference: String) async throws -> VerseExpansion {
        let versions: [ScripturePassage.BibleVersion] = [.esv, .niv, .kjv, .nlt]
        var passages: [ScripturePassage] = []

        for version in versions {
            if let passage = try? await YouVersionBibleService.shared.fetchVerse(reference: reference, version: version) {
                passages.append(passage)
            }
        }

        return VerseExpansion(
            reference: reference,
            passages: passages,
            contextBefore: nil,
            contextAfter: nil
        )
    }

    func fetchCrossReferences(for reference: String) async -> [CrossReference] {
        // Use AI to suggest cross-references
        let prompt = "List 5 cross-references for \(reference). Format each as: TARGET_REF | RELATIONSHIP | BRIEF_SNIPPET (one per line, no numbering)."

        var refs: [CrossReference] = []
        var accumulated = ""

        do {
            let stream = ClaudeService.shared.sendMessage(
                prompt,
                maxTokens: 600,
                temperature: 0.4,
                mode: .scholar
            )
            for try await chunk in stream {
                accumulated += chunk
            }

            let lines = accumulated.components(separatedBy: "\n").filter { $0.contains("|") }
            for line in lines.prefix(5) {
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 2 else { continue }
                refs.append(CrossReference(
                    sourceRef: reference,
                    targetRef: parts[0],
                    relationship: parts.count > 1 ? parts[1] : "related",
                    snippet: parts.count > 2 ? parts[2] : nil
                ))
            }
        } catch {
            print("[ERROR] SelahService.fetchCrossReferences: AI cross-reference generation failed — \(error)")
        }

        return refs
    }

    // MARK: - Transformations

    func transform(
        content: String,
        scriptureRefs: [String],
        to type: SelahTransformationType
    ) -> AsyncThrowingStream<String, Error> {
        let refsText = scriptureRefs.isEmpty ? "" : " Referenced verses: \(scriptureRefs.joined(separator: ", "))."

        let prompt: String
        switch type {
        case .devotional:
            prompt = "Transform this Bible study into a short morning devotional (3-4 paragraphs). Include an opening verse, reflection, and closing prayer.\(refsText)\n\nContent:\n\(content.prefix(1500))"
        case .prayerGuide:
            prompt = "Create a guided prayer based on these insights. Include adoration, confession, thanksgiving, and supplication sections.\(refsText)\n\nContent:\n\(content.prefix(1500))"
        case .studyOutline:
            prompt = "Create a structured Bible study outline with: Context, Key Themes, Verse-by-Verse Notes, Discussion Questions, and Application.\(refsText)\n\nContent:\n\(content.prefix(1500))"
        case .memoryCard:
            prompt = "Distill this into a concise memory card: one key verse, one core truth (1 sentence), and one application point.\(refsText)\n\nContent:\n\(content.prefix(1500))"
        case .journalPrompt:
            prompt = "Create 5 reflective journaling prompts based on these biblical insights. Each should invite personal reflection and application.\(refsText)\n\nContent:\n\(content.prefix(1500))"
        case .shareSnippet:
            prompt = "Craft a brief, shareable insight (2-3 sentences max) that captures the essence of this study. Make it encouraging and social-media friendly.\(refsText)\n\nContent:\n\(content.prefix(1500))"
        }

        return ClaudeService.shared.sendMessage(
            prompt,
            maxTokens: 1500,
            temperature: 0.65,
            mode: .shepherd
        )
    }

    // MARK: - Workflow Engine

    func createWorkflow(verseReference: String) async throws -> String {
        guard !userId.isEmpty else { throw SelahError.notAuthenticated }

        let workflow = SelahWorkflow(
            userId: userId,
            verseReference: verseReference,
            currentStage: WorkflowStage.verse.rawValue,
            stageData: [WorkflowStage.verse.rawValue: verseReference],
            createdAt: Date(),
            updatedAt: Date()
        )

        let ref = try db.collection("users/\(userId)/selahWorkflows")
            .addDocument(from: workflow)
        return ref.documentID
    }

    func advanceWorkflow(workflowId: String, content: String) async throws {
        guard !userId.isEmpty else { throw SelahError.notAuthenticated }

        let docRef = db.collection("users/\(userId)/selahWorkflows").document(workflowId)
        let snapshot = try await docRef.getDocument()
        guard var workflow = try? snapshot.data(as: SelahWorkflow.self) else {
            throw SelahError.workflowNotFound
        }

        let currentStage = workflow.currentWorkflowStage
        workflow.stageData[currentStage.rawValue] = content

        // Advance to next stage
        let allStages = WorkflowStage.allCases
        if let currentIndex = allStages.firstIndex(of: currentStage),
           currentIndex + 1 < allStages.count {
            workflow.currentStage = allStages[currentIndex + 1].rawValue
        } else {
            workflow.isComplete = true
        }
        workflow.updatedAt = Date()

        try docRef.setData(from: workflow)
    }

    func suggestNextStep(for workflow: SelahWorkflow) -> WorkflowSuggestion {
        let stage = workflow.currentWorkflowStage
        let verseContent = workflow.stageData[WorkflowStage.verse.rawValue] ?? workflow.verseReference

        let suggestion: String
        switch stage {
        case .verse:
            suggestion = "Open \(verseContent) and read it slowly. What stands out to you?"
        case .reflect:
            suggestion = "What does \(verseContent) mean for your life right now? Write a few sentences."
        case .pray:
            suggestion = "Turn your reflection into a prayer. Talk to God about what you've discovered."
        case .journal:
            suggestion = "Record what God is showing you through \(verseContent) in your journal."
        case .testimony:
            suggestion = "Shape your journey with \(verseContent) into a testimony others can learn from."
        case .share:
            suggestion = "Share your testimony with someone who might need to hear it."
        }

        return WorkflowSuggestion(
            stage: stage,
            prompt: stage.prompt,
            aiSuggestion: suggestion
        )
    }

    private func startListeningWorkflows() {
        guard !userId.isEmpty else { return }
        workflowListener?.remove()
        workflowListener = db.collection("users/\(userId)/selahWorkflows")
            .whereField("isComplete", isEqualTo: false)
            .order(by: "updatedAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let docs = snapshot?.documents else { return }
                self?.workflows = docs.compactMap { try? $0.data(as: SelahWorkflow.self) }
            }
    }

    // MARK: - Errors

    enum SelahError: LocalizedError {
        case notAuthenticated
        case workflowNotFound
        case transformationFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Please sign in to use Selah features."
            case .workflowNotFound: return "Workflow not found."
            case .transformationFailed: return "Failed to generate transformation."
            }
        }
    }
}
