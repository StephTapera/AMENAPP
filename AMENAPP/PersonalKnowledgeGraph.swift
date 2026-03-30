// PersonalKnowledgeGraph.swift
// AMENAPP
//
// Context Memory + Personal Knowledge Graph
//
// Berean remembers:
//   - What user is learning
//   - Struggles they've shared
//   - Interests and questions
//   - Past conversations
//   - Growth trajectory
//
// BUT:
//   - Scoped memory (user-controlled)
//   - Transparent ("Here's what I remember")
//   - Deletable at any time
//
// Entry points:
//   PersonalKnowledgeGraph.shared.remember(_ memory:) async
//   PersonalKnowledgeGraph.shared.recall(for:) async -> [Memory]
//   PersonalKnowledgeGraph.shared.getContextSummary() async -> String
//   PersonalKnowledgeGraph.shared.deleteMemory(_ id:) async
//   PersonalKnowledgeGraph.shared.clearAll() async

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

/// A single memory entry
struct BereanMemory: Identifiable, Codable {
    let id: String
    let userId: String
    let content: String             // What was learned/shared
    let category: MemoryCategory
    let tags: [String]              // Searchable tags
    let source: MemorySource
    let createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int
    var isActive: Bool              // User can deactivate without deleting
    var importance: Double          // 0.0-1.0, decays over time without access
}

enum MemoryCategory: String, Codable, CaseIterable {
    case learning = "learning"          // What they're studying
    case struggle = "struggle"          // Challenges they face
    case interest = "interest"          // Topics they care about
    case decision = "decision"          // Decisions they've made
    case prayer = "prayer"              // Prayer patterns
    case growth = "growth"              // Growth observations
    case preference = "preference"      // How they like to learn
    case relationship = "relationship"  // People/church connections

    var displayName: String {
        switch self {
        case .learning: return "Learning"
        case .struggle: return "Struggles"
        case .interest: return "Interests"
        case .decision: return "Decisions"
        case .prayer: return "Prayer Life"
        case .growth: return "Growth"
        case .preference: return "Preferences"
        case .relationship: return "Connections"
        }
    }

    var icon: String {
        switch self {
        case .learning: return "book.fill"
        case .struggle: return "heart.fill"
        case .interest: return "star.fill"
        case .decision: return "arrow.triangle.branch"
        case .prayer: return "hands.sparkles.fill"
        case .growth: return "leaf.fill"
        case .preference: return "slider.horizontal.3"
        case .relationship: return "person.2.fill"
        }
    }
}

enum MemorySource: String, Codable {
    case bereanChat = "berean_chat"
    case churchNote = "church_note"
    case prayer = "prayer"
    case post = "post"
    case sermonAnalysis = "sermon"
    case wordStudy = "word_study"
    case decisionEngine = "decision"
    case manual = "manual"
}

/// What Berean currently "knows" about the user
struct MemoryContext: Codable {
    let activeMemories: Int
    let topThemes: [String]
    let recentLearning: [String]
    let currentStruggles: [String]
    let contextSummary: String      // Natural language summary
}

// MARK: - PersonalKnowledgeGraph

@MainActor
final class PersonalKnowledgeGraph: ObservableObject {

    static let shared = PersonalKnowledgeGraph()

    @Published var memories: [BereanMemory] = []
    @Published var memoryContext: MemoryContext?
    @Published var isLoading = false
    @Published var totalMemories: Int = 0

    // Privacy controls
    @Published var isMemoryEnabled: Bool {
        didSet { UserDefaults.standard.set(isMemoryEnabled, forKey: "berean_memory_enabled") }
    }
    @Published var enabledCategories: Set<MemoryCategory> {
        didSet {
            let raw = enabledCategories.map { $0.rawValue }
            UserDefaults.standard.set(raw, forKey: "berean_memory_categories")
        }
    }

    private let db = Firestore.firestore()
    private let aiService = ClaudeService.shared
    private var listener: ListenerRegistration?

    // Memory limits
    private let maxMemories = 200
    private let importanceDecayRate = 0.02  // Per day without access

    private init() {
        isMemoryEnabled = UserDefaults.standard.bool(forKey: "berean_memory_enabled")
        if !UserDefaults.standard.bool(forKey: "berean_memory_initialized") {
            isMemoryEnabled = true
            UserDefaults.standard.set(true, forKey: "berean_memory_enabled")
            UserDefaults.standard.set(true, forKey: "berean_memory_initialized")
        }

        let savedCategories = UserDefaults.standard.stringArray(forKey: "berean_memory_categories")
        if let saved = savedCategories {
            enabledCategories = Set(saved.compactMap { MemoryCategory(rawValue: $0) })
        } else {
            enabledCategories = Set(MemoryCategory.allCases)
        }

        startListening()
    }

    // MARK: - Public API

    /// Store a new memory
    func remember(_ content: String, category: MemoryCategory, tags: [String] = [], source: MemorySource = .bereanChat) async {
        guard isMemoryEnabled else { return }
        guard enabledCategories.contains(category) else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Check for duplicates (similar content)
        if memories.contains(where: { $0.content.lowercased() == content.lowercased() }) { return }

        let memory = BereanMemory(
            id: UUID().uuidString,
            userId: uid,
            content: content,
            category: category,
            tags: tags,
            source: source,
            createdAt: Date(),
            lastAccessedAt: Date(),
            accessCount: 1,
            isActive: true,
            importance: 1.0
        )

        do {
            try db.collection("users").document(uid)
                .collection("bereanMemories").document(memory.id)
                .setData(from: memory)

            memories.insert(memory, at: 0)
            totalMemories += 1

            // Prune if over limit
            if memories.count > maxMemories {
                await pruneOldestMemories()
            }
        } catch {
            dlog("❌ [KnowledgeGraph] Remember failed: \(error)")
        }
    }

    /// Extract and store memories from a conversation turn
    func extractMemories(from userMessage: String, aiResponse: String) async {
        guard isMemoryEnabled else { return }

        let prompt = """
        From this conversation, extract any facts worth remembering about the user.
        Only extract meaningful, personal context — not generic questions.

        User said: \(String(userMessage.prefix(500)))
        AI responded about: \(String(aiResponse.prefix(200)))

        Return as JSON array (or empty array if nothing worth remembering):
        [
            {"content": "What to remember", "category": "learning|struggle|interest|decision|prayer|growth|preference|relationship", "tags": ["tag1"]}
        ]

        Only include genuinely useful context. Return ONLY valid JSON array.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let cleaned = cleanJSONArray(response)
            let data = Data(cleaned.utf8)

            struct MemoryExtract: Codable {
                let content: String
                let category: String
                let tags: [String]
            }

            let extracts = try JSONDecoder().decode([MemoryExtract].self, from: data)
            for extract in extracts {
                let cat = MemoryCategory(rawValue: extract.category) ?? .learning
                await remember(extract.content, category: cat, tags: extract.tags)
            }
        } catch {
            // Silent failure — memory extraction is best-effort
        }
    }

    /// Recall relevant memories for a query
    func recall(for query: String, limit: Int = 5) async -> [BereanMemory] {
        let queryLower = query.lowercased()
        let queryWords = Set(queryLower.split(separator: " ").map(String.init))

        // Score each memory by relevance
        let scored = memories.filter { $0.isActive }.map { memory -> (BereanMemory, Double) in
            var score = 0.0

            // Tag match
            let tagMatch = memory.tags.filter { queryWords.contains($0.lowercased()) }.count
            score += Double(tagMatch) * 0.3

            // Content word overlap
            let contentWords = Set(memory.content.lowercased().split(separator: " ").map(String.init))
            let overlap = contentWords.intersection(queryWords).count
            score += Double(overlap) * 0.2

            // Recency boost
            let daysSince = Date().timeIntervalSince(memory.lastAccessedAt) / 86400
            score += max(0, 1.0 - daysSince * 0.01)

            // Importance
            score += memory.importance * 0.3

            return (memory, score)
        }

        let relevant = scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .filter { $0.1 > 0.1 }
            .map { $0.0 }

        // Update access times
        for memory in relevant {
            await touchMemory(memory.id)
        }

        return relevant
    }

    /// Get a natural language summary of what Berean knows
    func getContextSummary() async -> String {
        guard !memories.isEmpty else { return "" }

        let activeMemories = memories.filter { $0.isActive }
        let byCategory = Dictionary(grouping: activeMemories, by: { $0.category })

        var parts: [String] = []
        for (category, mems) in byCategory.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let items = mems.prefix(3).map { $0.content }.joined(separator: "; ")
            parts.append("[\(category.displayName)]: \(items)")
        }

        return parts.joined(separator: "\n")
    }

    /// Get context for Berean system prompt
    func getSystemPromptContext() async -> String {
        guard isMemoryEnabled, !memories.isEmpty else { return "" }

        let summary = await getContextSummary()
        guard !summary.isEmpty else { return "" }

        return """
        \n--- User Memory Context (user has granted permission) ---
        \(summary)
        --- End Memory Context ---
        Use this context to personalize your responses. Reference past conversations naturally.
        """
    }

    /// Delete a specific memory
    func deleteMemory(_ memoryId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try await db.collection("users").document(uid)
                .collection("bereanMemories").document(memoryId)
                .delete()

            memories.removeAll { $0.id == memoryId }
            totalMemories = max(0, totalMemories - 1)
        } catch {
            dlog("❌ [KnowledgeGraph] Delete failed: \(error)")
        }
    }

    /// Clear all memories
    func clearAll() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let batch = db.batch()
        for memory in memories {
            let ref = db.collection("users").document(uid)
                .collection("bereanMemories").document(memory.id)
            batch.deleteDocument(ref)
        }

        do {
            try await batch.commit()
            memories.removeAll()
            totalMemories = 0
            memoryContext = nil
        } catch {
            dlog("❌ [KnowledgeGraph] Clear all failed: \(error)")
        }
    }

    // MARK: - Private

    private func touchMemory(_ memoryId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try? await db.collection("users").document(uid)
            .collection("bereanMemories").document(memoryId)
            .updateData([
                "lastAccessedAt": Timestamp(date: Date()),
                "accessCount": FieldValue.increment(Int64(1))
            ])
    }

    private func pruneOldestMemories() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Remove lowest-importance memories beyond the limit
        let sorted = memories.sorted { $0.importance < $1.importance }
        let toRemove = sorted.prefix(max(0, memories.count - maxMemories))

        for memory in toRemove {
            try? await db.collection("users").document(uid)
                .collection("bereanMemories").document(memory.id)
                .delete()
        }

        let removeIds = Set(toRemove.map { $0.id })
        memories.removeAll { removeIds.contains($0.id) }
    }

    private func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        listener = db.collection("users").document(uid)
            .collection("bereanMemories")
            .whereField("isActive", isEqualTo: true)
            .order(by: "lastAccessedAt", descending: true)
            .limit(to: maxMemories)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.memories = docs.compactMap { try? $0.data(as: BereanMemory.self) }
                    self.totalMemories = self.memories.count
                }
            }
    }

    private func cleanJSONArray(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "["), let end = s.range(of: "]", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Memory Management View (Trust & Transparency)

struct BereanMemoryView: View {
    @StateObject private var graph = PersonalKnowledgeGraph.shared
    @State private var selectedCategory: MemoryCategory?
    @State private var showClearConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var filteredMemories: [BereanMemory] {
        if let cat = selectedCategory {
            return graph.memories.filter { $0.category == cat }
        }
        return graph.memories
    }

    var body: some View {
        NavigationStack {
            List {
                // Controls section
                Section {
                    Toggle("Memory Enabled", isOn: $graph.isMemoryEnabled)

                    if graph.isMemoryEnabled {
                        NavigationLink("Memory Categories") {
                            memoryCategoriesView
                        }
                    }
                } header: {
                    Text("Privacy Controls")
                } footer: {
                    Text("When enabled, Berean remembers context from your conversations to personalize responses. You control what categories are remembered and can delete any memory at any time.")
                }

                // Stats
                Section("What Berean Knows") {
                    HStack {
                        Text("Total Memories")
                        Spacer()
                        Text("\(graph.totalMemories)")
                            .foregroundStyle(.secondary)
                    }

                    // Category breakdown
                    let grouped = Dictionary(grouping: graph.memories, by: { $0.category })
                    ForEach(MemoryCategory.allCases, id: \.self) { cat in
                        let count = grouped[cat]?.count ?? 0
                        if count > 0 {
                            Button {
                                selectedCategory = selectedCategory == cat ? nil : cat
                            } label: {
                                HStack {
                                    Image(systemName: cat.icon)
                                        .frame(width: 24)
                                    Text(cat.displayName)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundStyle(.secondary)
                                    if selectedCategory == cat {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }

                // Memory list
                Section("Memories\(selectedCategory != nil ? " — \(selectedCategory!.displayName)" : "")") {
                    ForEach(filteredMemories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.content)
                                .font(.subheadline)

                            HStack {
                                Image(systemName: memory.category.icon)
                                    .font(.caption2)
                                Text(memory.source.rawValue)
                                    .font(.caption2)
                                Spacer()
                                Text(memory.createdAt, style: .relative)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for idx in indexSet {
                                let memory = filteredMemories[idx]
                                await graph.deleteMemory(memory.id)
                            }
                        }
                    }
                }

                // Clear all
                Section {
                    Button("Clear All Memories", role: .destructive) {
                        showClearConfirmation = true
                    }
                }
            }
            .navigationTitle("Berean Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Clear All Memories?", isPresented: $showClearConfirmation) {
                Button("Clear All", role: .destructive) {
                    Task { await graph.clearAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete everything Berean remembers about you. This cannot be undone.")
            }
        }
    }

    private var memoryCategoriesView: some View {
        List {
            ForEach(MemoryCategory.allCases, id: \.self) { cat in
                Toggle(isOn: Binding(
                    get: { graph.enabledCategories.contains(cat) },
                    set: { enabled in
                        if enabled {
                            graph.enabledCategories.insert(cat)
                        } else {
                            graph.enabledCategories.remove(cat)
                        }
                    }
                )) {
                    Label(cat.displayName, systemImage: cat.icon)
                }
            }
        }
        .navigationTitle("Memory Categories")
    }
}
