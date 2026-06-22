// BereanSemanticSearch.swift
// AMENAPP
//
// Semantic search over the user's Church Notes using vector embeddings:
//   - Embeddings generated via bereanEmbedProxy Cloud Function (OpenAI text-embedding-3-small)
//   - Embeddings cached in Firestore at churchNotes/{noteId}/embedding
//   - Cosine similarity computed on-device for privacy
//   - Returns ranked [SemanticSearchResult] for any natural-language query
//
// Entry points:
//   BereanSemanticSearchService.shared.search(query:notes:) async -> [SemanticSearchResult]
//   BereanSemanticSearchView(notes:) — full search UI

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Models

struct SemanticSearchResult: Identifiable {
    let id: String          // noteId
    let note: ChurchNote
    let score: Double       // cosine similarity 0–1
    let matchContext: String // best matching excerpt
}

// MARK: - BereanSemanticSearchService

@MainActor
final class BereanSemanticSearchService: ObservableObject {
    static let shared = BereanSemanticSearchService()

    @Published var results: [SemanticSearchResult] = []
    @Published var isSearching = false
    @Published var isIndexing  = false

    private lazy var functions = Functions.functions()
    private let db        = Firestore.firestore()

    // In-memory embedding cache: noteId → [Double]
    private var embeddingCache: [String: [Double]] = [:]

    // MARK: - Public API

    /// Semantic search over the provided notes using a natural-language query.
    func search(query: String, notes: [ChurchNote]) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !notes.isEmpty else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        // Embed query
        guard let queryEmbedding = await embed(text: query) else { return }

        // Get embeddings for all notes (fetch from cache or Firestore, generate if missing)
        var scored: [(note: ChurchNote, score: Double)] = []
        for note in notes {
            guard note.id != nil else { continue }
            let noteEmbed = await noteEmbedding(for: note)
            let sim = cosine(queryEmbedding, noteEmbed)
            scored.append((note, sim))
        }

        // Sort descending, keep top 10 with score > 0.35
        let top = scored
            .filter  { $0.score > 0.35 }
            .sorted  { $0.score > $1.score }
            .prefix(10)

        results = top.compactMap { item in
            guard let id = item.note.id else { return nil }
            return SemanticSearchResult(
                id: id,
                note: item.note,
                score: item.score,
                matchContext: bestContext(for: query, in: item.note)
            )
        }
    }

    /// Pre-embed all notes that don't have an embedding yet (call once on notes load).
    func indexIfNeeded(notes: [ChurchNote]) async {
        let unindexed = notes.filter { note in
            guard let id = note.id else { return false }
            return embeddingCache[id] == nil
        }
        guard !unindexed.isEmpty else { return }
        isIndexing = true
        defer { isIndexing = false }
        for note in unindexed.prefix(50) { // batch limit
            _ = await noteEmbedding(for: note)
        }
    }

    // MARK: - Private

    private func noteEmbedding(for note: ChurchNote) async -> [Double] {
        guard let noteId = note.id else { return [] }

        // In-memory cache hit
        if let cached = embeddingCache[noteId] { return cached }

        // Firestore cache
        if let snap = try? await db.collection("churchNotes").document(noteId)
            .collection("meta").document("embedding").getDocument(),
           let arr = snap.data()?["vector"] as? [Double], !arr.isEmpty {
            embeddingCache[noteId] = arr
            return arr
        }

        // Generate via Cloud Function
        let text = [note.title, note.content, note.keyPoints.joined(separator: ". ")]
            .joined(separator: " ")
            .prefix(2000)
        guard let vector = await embed(text: String(text)) else { return [] }

        // Cache in Firestore (fire-and-forget)
        if let noteId = note.id {
            try? await db.collection("churchNotes").document(noteId)
                .collection("meta").document("embedding")
                .setData(["vector": vector, "updatedAt": FieldValue.serverTimestamp()])
        }
        embeddingCache[noteId] = vector
        return vector
    }

    private func embed(text: String) async -> [Double]? {
        do {
            let result = try await functions.httpsCallable("bereanEmbedProxy").call(["text": text])
            guard let data   = result.data as? [String: Any],
                  let vector = data["embedding"] as? [Double] else { return nil }
            return vector
        } catch {
            print("BereanSemanticSearch embed error: \(error)")
            return nil
        }
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot  = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        guard normA > 0 && normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    private func bestContext(for query: String, in note: ChurchNote) -> String {
        let words   = query.lowercased().split(separator: " ").map(String.init)
        let sources = [note.content, note.keyPoints.joined(separator: " ")]
        for source in sources {
            for word in words {
                if let range = source.lowercased().range(of: word) {
                    let start  = source.index(range.lowerBound, offsetBy: -40, limitedBy: source.startIndex) ?? source.startIndex
                    let end    = source.index(range.upperBound, offsetBy: 80,  limitedBy: source.endIndex) ?? source.endIndex
                    return "…" + String(source[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                }
            }
        }
        return String(note.content.prefix(120))
    }
}

// MARK: - BereanSemanticSearchView

struct BereanSemanticSearchView: View {
    let notes: [ChurchNote]
    @StateObject private var service = BereanSemanticSearchService.shared
    @State private var query = ""
    @FocusState private var focused: Bool
    @State private var debounceTask: Task<Void, Never>?

    private let suggestionChips = [
        "Grace & Forgiveness",
        "Prayer & Fasting",
        "Faith",
        "Recent",
        "Scriptures"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.systemScaled(15))
                    .foregroundStyle(Color(.secondaryLabel))

                TextField("Search your notes semantically…", text: $query)
                    .font(.systemScaled(15))
                    .focused($focused)
                    .onChange(of: query) { _, newVal in
                        scheduleSearch(newVal)
                    }

                if service.isSearching {
                    ProgressView().scaleEffect(0.75)
                } else if !query.isEmpty {
                    Button { query = ""; service.results = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if service.isIndexing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Indexing notes…")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.bottom, 8)
            }

            // Empty state when query is blank
            if query.isEmpty {
                semanticSearchEmptyState
            } else if !service.results.isEmpty {
                // Results
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.results) { result in
                            SemanticResultRow(result: result)
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
            } else if !service.isSearching {
                Text("No notes matched \"\(query)\"")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.top, 32)
            }

            Spacer()
        }
        .task { await service.indexIfNeeded(notes: notes) }
        .onAppear { focused = true }
    }

    // MARK: - Empty State

    private var semanticSearchEmptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 24)

            // Large sparkle/magnifier icon
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.purple.opacity(0.75))
                .symbolRenderingMode(.hierarchical)

            // Headline + body
            VStack(spacing: 8) {
                Text("Semantic Search")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Search by topic, theme, scripture, or feeling. Try \"sermons about grace\" or \"notes from last month\".")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }

            // Suggestion chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestionChips, id: \.self) { chip in
                        Button {
                            query = chip
                            scheduleSearch(chip)
                        } label: {
                            Text(chip)
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(Color.purple)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(Color.purple.opacity(0.07)))
                                        .overlay(Capsule().strokeBorder(Color.purple.opacity(0.22), lineWidth: 0.75))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    private func scheduleSearch(_ text: String) {
        debounceTask?.cancel()
        guard !text.isEmpty else { service.results = []; return }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await service.search(query: text, notes: notes)
        }
    }
}

// MARK: - SemanticResultRow

private struct SemanticResultRow: View {
    let result: SemanticSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.note.title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(result.score * 100))% match")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Text(result.matchContext)
                .font(.systemScaled(13))
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(2)

            if let date = result.note.date as Date? {
                Text(date.formatted(.dateTime.month().day().year()))
                    .font(.systemScaled(11))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - SemanticSearchButton (entry point for ChurchNotesView toolbar)

struct SemanticSearchButton: View {
    let notes: [ChurchNote]
    @State private var showSearch = false

    var body: some View {
        Button {
            showSearch = true
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.systemScaled(16))
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                BereanSemanticSearchView(notes: notes)
                    .navigationTitle("Smart Search")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showSearch = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }
}
