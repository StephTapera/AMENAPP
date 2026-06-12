//
//  BereanContextMemoryService.swift
//  AMENAPP
//
//  Berean's personal knowledge graph — walks with the user over time.
//  Stores to Firestore under users/{uid}/bereanMemory/
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Memory Models

struct BereanContextMemoryEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var category: MemoryCategory
    var summary: String
    var detail: String
    var tags: [String]
    var linkedVerses: [String]
    var createdAt: Date
    var lastReferencedAt: Date
    var timesReferenced: Int
    var isUserVisible: Bool

    enum MemoryCategory: String, Codable, CaseIterable {
        case scripture, decision, struggle, interest, milestone, belief, prayer, question

        var displayName: String { rawValue.capitalized }

        var icon: String {
            switch self {
            case .scripture: return "book.fill"
            case .decision:  return "arrow.triangle.branch"
            case .struggle:  return "heart.slash"
            case .interest:  return "star.fill"
            case .milestone: return "flag.fill"
            case .belief:    return "cross.fill"
            case .prayer:    return "hands.sparkles"
            case .question:  return "questionmark.circle.fill"
            }
        }
    }
}

struct BereanUserContext: Codable {
    var spiritualTopics: [String] = []
    var recentStruggles: [String] = []
    var favoriteVerses: [String] = []
    var growthAreas: [String] = []
    var lastUpdated: Date = Date()
}

// MARK: - Service

@MainActor
final class BereanContextMemoryService: ObservableObject {

    static let shared = BereanContextMemoryService()

    @Published private(set) var memories: [BereanContextMemoryEntry] = []
    @Published private(set) var userContext: BereanUserContext = BereanUserContext()
    @Published var isLoaded = false

    private lazy var db = Firestore.firestore()
    private var memoriesListener: ListenerRegistration?
    private var contextListener: ListenerRegistration?

    private init() {}

    // MARK: - Firestore Paths

    private func memoriesRef(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("bereanMemory")
    }

    private func contextRef(uid: String) -> DocumentReference {
        db.collection("users").document(uid).collection("bereanContext").document("profile")
    }

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanContextMemoryService: no authenticated user, skipping listen")
            return
        }

        dlog("BereanContextMemoryService: starting listeners for uid \(uid)")

        memoriesListener = memoriesRef(uid: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("BereanContextMemoryService memories listener error: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let decoder = Firestore.Decoder()
                self.memories = docs.compactMap { doc in
                    try? doc.data(as: BereanContextMemoryEntry.self, decoder: decoder)
                }
                self.isLoaded = true
                dlog("BereanContextMemoryService: loaded \(self.memories.count) memory entries")
            }

        contextListener = contextRef(uid: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("BereanContextMemoryService context listener error: \(error.localizedDescription)")
                    return
                }
                if let ctx = try? snapshot?.data(as: BereanUserContext.self) {
                    self.userContext = ctx
                }
            }
    }

    func stopListening() {
        memoriesListener?.remove()
        contextListener?.remove()
        memoriesListener = nil
        contextListener = nil
        dlog("BereanContextMemoryService: stopped listeners")
    }

    // MARK: - Memory Operations

    func addMemory(_ entry: BereanContextMemoryEntry) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanContextMemoryService.addMemory: no authenticated user")
            return
        }
        do {
            let encoder = Firestore.Encoder()
            let data = try encoder.encode(entry)
            try await memoriesRef(uid: uid).document(entry.id).setData(data)
            dlog("BereanContextMemoryService: saved memory \(entry.id) [\(entry.category.rawValue)]")
        } catch {
            dlog("BereanContextMemoryService.addMemory error: \(error.localizedDescription)")
        }
    }

    func updateMemory(_ id: String, summary: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanContextMemoryService.updateMemory: no authenticated user")
            return
        }
        do {
            try await memoriesRef(uid: uid).document(id).updateData([
                "summary": summary,
                "lastReferencedAt": Timestamp(date: Date())
            ])
            dlog("BereanContextMemoryService: updated memory \(id)")
        } catch {
            dlog("BereanContextMemoryService.updateMemory error: \(error.localizedDescription)")
        }
    }

    func deleteMemory(_ id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanContextMemoryService.deleteMemory: no authenticated user")
            return
        }
        do {
            try await memoriesRef(uid: uid).document(id).delete()
            dlog("BereanContextMemoryService: deleted memory \(id)")
        } catch {
            dlog("BereanContextMemoryService.deleteMemory error: \(error.localizedDescription)")
        }
    }

    func clearAllMemories() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanContextMemoryService.clearAllMemories: no authenticated user")
            return
        }
        do {
            let snap = try await memoriesRef(uid: uid).getDocuments()
            let batch = db.batch()
            snap.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            dlog("BereanContextMemoryService: cleared all \(snap.documents.count) memories")
        } catch {
            dlog("BereanContextMemoryService.clearAllMemories error: \(error.localizedDescription)")
        }
    }

    // MARK: - Context Building

    /// Build a compact context string to prepend to Berean prompts (max ~300 chars).
    func buildContextSummary() -> String {
        var parts: [String] = []

        if !userContext.recentStruggles.isEmpty {
            let joined = userContext.recentStruggles.prefix(3).joined(separator: ", ")
            parts.append("struggling with \(joined)")
        }
        if !userContext.spiritualTopics.isEmpty {
            let joined = userContext.spiritualTopics.prefix(3).joined(separator: ", ")
            parts.append("interested in \(joined)")
        }
        if !userContext.growthAreas.isEmpty {
            let joined = userContext.growthAreas.prefix(2).joined(separator: ", ")
            parts.append("growing in \(joined)")
        }

        let recentQuestions = memories
            .filter { $0.category == .question }
            .prefix(3)
            .map(\.summary)
        if !recentQuestions.isEmpty {
            parts.append("has asked about \(recentQuestions.joined(separator: ", ")) before")
        }

        guard !parts.isEmpty else { return "" }

        let full = "User context: \(parts.joined(separator: "; "))."
        // Trim to 300 chars to stay within system prompt budget
        if full.count > 300 {
            return String(full.prefix(297)) + "..."
        }
        return full
    }

    /// Extract and save new memory from a conversation turn using Claude.
    func extractMemoryFromConversation(userMessage: String, aiResponse: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let prompt = """
        Analyze the following conversation and extract any important personal facts worth remembering long-term.

        User message: \(userMessage)
        AI response: \(aiResponse)

        Identify up to 2 notable facts from these categories: struggle, scripture, decision, interest, milestone, belief, prayer, question.
        For each fact, reply on its own line in this exact format:
        CATEGORY|SUMMARY|TAGS(comma-separated)|VERSE_REFS(comma-separated or blank)

        Only output lines in that format. No extra text.
        """

        do {
            let raw = try await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)
            let lines = raw.components(separatedBy: "\n").filter { $0.contains("|") }

            for line in lines {
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 2 else { continue }

                let rawCategory = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let summary = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !summary.isEmpty,
                      let category = BereanContextMemoryEntry.MemoryCategory(rawValue: rawCategory) else { continue }

                let tags: [String] = parts.count > 2
                    ? parts[2].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    : []
                let verses: [String] = parts.count > 3
                    ? parts[3].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    : []

                let entry = BereanContextMemoryEntry(
                    category: category,
                    summary: summary,
                    detail: "\(userMessage)\n\n\(aiResponse)",
                    tags: tags,
                    linkedVerses: verses,
                    createdAt: Date(),
                    lastReferencedAt: Date(),
                    timesReferenced: 1,
                    isUserVisible: true
                )
                await addMemory(entry)

                // Also update the userContext based on category
                await updateContextFromEntry(entry, uid: uid)
            }
        } catch {
            dlog("BereanContextMemoryService.extractMemoryFromConversation error: \(error.localizedDescription)")
        }
    }

    private func updateContextFromEntry(_ entry: BereanContextMemoryEntry, uid: String) async {
        var ctx = userContext
        switch entry.category {
        case .struggle:
            if !ctx.recentStruggles.contains(entry.summary) {
                ctx.recentStruggles.insert(entry.summary, at: 0)
                ctx.recentStruggles = Array(ctx.recentStruggles.prefix(10))
            }
        case .interest, .scripture, .question:
            for tag in entry.tags where !ctx.spiritualTopics.contains(tag) {
                ctx.spiritualTopics.insert(tag, at: 0)
            }
            ctx.spiritualTopics = Array(ctx.spiritualTopics.prefix(20))
        case .milestone, .belief:
            if !ctx.growthAreas.contains(entry.summary) {
                ctx.growthAreas.insert(entry.summary, at: 0)
                ctx.growthAreas = Array(ctx.growthAreas.prefix(10))
            }
        default:
            break
        }
        ctx.lastUpdated = Date()
        userContext = ctx

        do {
            let encoder = Firestore.Encoder()
            let data = try encoder.encode(ctx)
            try await contextRef(uid: uid).setData(data, merge: true)
        } catch {
            dlog("BereanContextMemoryService.updateContextFromEntry error: \(error.localizedDescription)")
        }
    }

    // MARK: - Smart Recall

    /// Find memories relevant to a query using keyword matching.
    func recallRelevant(to query: String, limit: Int = 5) -> [BereanContextMemoryEntry] {
        let keywords = query
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 }

        guard !keywords.isEmpty else { return Array(memories.prefix(limit)) }

        let scored: [(BereanContextMemoryEntry, Int)] = memories.map { entry in
            let haystack = (entry.summary + " " + entry.detail + " " + entry.tags.joined(separator: " ")).lowercased()
            let score = keywords.reduce(0) { acc, kw in acc + (haystack.contains(kw) ? 1 : 0) }
            return (entry, score)
        }

        return scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Returns a continuation suggestion string if a closely related prior memory exists.
    func continuationSuggestion(for query: String) -> String? {
        let relevant = recallRelevant(to: query, limit: 1)
        guard let top = relevant.first else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let timeAgo = formatter.localizedString(for: top.lastReferencedAt, relativeTo: Date())
        return "You explored \"\(top.summary)\" \(timeAgo) — want to continue?"
    }
}
