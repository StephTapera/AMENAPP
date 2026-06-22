import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Smart Church Notes Search — keyword/substring index over the owner's notes
/// and their processing outputs (transcripts, OCR, drafts).
///
/// SCALE NOTE: This is INDEXED keyword search, NOT vector/semantic search.
/// The UI label and user-facing copy must stay "Smart Church Notes Search"
/// (never "AI Search" or "Semantic Search") unless real embeddings + an ANN
/// backend are wired. To upgrade later, see `algoliaIndex` / `vectorBackend`
/// extension points below — adding either is a drop-in replacement for
/// `fetchCandidateBatch`.
///
/// Pagination: returns results in batches of `pageSize` (default 50). Call
/// `searchMore()` to load the next page using the saved cursor. This keeps
/// memory bounded even for users with thousands of notes.
@MainActor
final class SmartChurchNotesSearchService: ObservableObject {
    @Published private(set) var results: [ChurchNotesSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = false

    private let db = Firestore.firestore()

    /// Per-page Firestore fetch size. Each note costs one parent doc + up to
    /// three subcollection reads inside `processingIndexText`, so we cap the
    /// batch size to keep per-search read counts predictable.
    static let pageSize = 50

    /// Hard ceiling on the candidate set per search. Beyond this, results
    /// become stale before the user finishes scrolling them, so we stop and
    /// honestly tell the user there are more matches.
    static let maxCandidates = 500

    private var lastQuery: String = ""
    private var lastFilters: ChurchNotesSearchFilters = ChurchNotesSearchFilters()
    private var lastCursor: DocumentSnapshot?
    private var totalScanned: Int = 0

    /// Search-from-start. Resets pagination cursor and accumulated results.
    func search(query: String, filters: ChurchNotesSearchFilters) async {
        lastQuery = query
        lastFilters = filters
        lastCursor = nil
        totalScanned = 0
        results = []
        hasMore = false
        await fetchNextPage()
    }

    /// Loads the next page of candidates against the most recent query/filters.
    /// Idempotent if there's no more data to load.
    func searchMore() async {
        guard hasMore, !isSearching else { return }
        await fetchNextPage()
    }

    private func fetchNextPage() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in to search notes."
            return
        }

        let terms = lastQuery
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard !terms.isEmpty || lastFilters.hasAnyFilter else {
            results = []
            hasMore = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            var query: Query = db.collection("churchNotes")
                .whereField("userId", isEqualTo: uid)
                .order(by: "updatedAt", descending: true)
                .limit(to: Self.pageSize)
            if let cursor = lastCursor {
                query = query.start(afterDocument: cursor)
            }
            let snapshot = try await query.getDocuments()
            lastCursor = snapshot.documents.last

            var pageMatches: [ChurchNotesSearchResult] = []
            for document in snapshot.documents {
                var haystack = document.data()
                let noteId = document.documentID
                let processingText = try await processingIndexText(noteId: noteId)
                haystack["processingIndexText"] = processingText

                guard matchesFilters(haystack, filters: lastFilters) else { continue }
                let score = scoreDocument(haystack, terms: terms)
                if terms.isEmpty || score > 0 {
                    pageMatches.append(ChurchNotesSearchResult(
                        id: noteId,
                        title: stringValue(haystack["title"]) ?? stringValue(haystack["sermonTitle"]) ?? "Untitled note",
                        excerpt: bestExcerpt(from: haystack, terms: terms),
                        score: score,
                        mediaTypes: stringArray(haystack["mediaTypes"]),
                        tags: stringArray(haystack["tags"])
                    ))
                }
            }
            totalScanned += snapshot.documents.count

            // Append + re-sort so highest-scoring matches surface at the top
            // even across pages.
            results.append(contentsOf: pageMatches)
            results.sort { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }

            // Honest "more results may exist" signal. We refuse to keep paging
            // past `maxCandidates` so we don't pretend to be a real search
            // engine — at that point the user should switch to a more
            // specific query or filter.
            hasMore = snapshot.documents.count == Self.pageSize && totalScanned < Self.maxCandidates
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Extension points for future search backends.

    /// Algolia is already wired for users/posts (see AlgoliaSearchService /
    /// AlgoliaSyncService). To switch Church Notes onto Algolia:
    ///   1. Add a Firestore trigger that pushes churchNotes writes to an
    ///      `church_notes` index with a visibility filter (`ownerUid:<uid>` OR
    ///      `collaborators:<uid>`).
    ///   2. Replace `fetchNextPage` with an Algolia query that returns
    ///      `objectID`s; fetch full docs with `db.getAllDocuments(refs)` to
    ///      preserve security rule enforcement.
    /// The pagination + scoring + filter logic above is reusable as-is.
    private func _algoliaExtensionPoint() {}

    /// Vector backend extension point — when on-device embeddings or a hosted
    /// vector store is available, this hook can return semantic neighbours
    /// keyed by `noteId` for re-ranking. Leave a stub here so search.label
    /// stays honest ("Smart Church Notes Search") until embeddings ship.
    private func _vectorBackendExtensionPoint() {}

    private func processingIndexText(noteId: String) async throws -> String {
        async let jobs = db.collection("churchNotes").document(noteId).collection("processingJobs").limit(to: 20).getDocuments()
        async let transcripts = db.collection("churchNotes").document(noteId).collection("transcripts").limit(to: 20).getDocuments()
        async let ocrResults = db.collection("churchNotes").document(noteId).collection("ocrResults").limit(to: 20).getDocuments()

        let snapshots = try await [jobs, transcripts, ocrResults]
        return snapshots.flatMap(\.documents).flatMap { document in
            document.data().compactMap { _, value -> String? in
                if let string = value as? String { return string }
                if let strings = value as? [String] { return strings.joined(separator: " ") }
                return nil
            }
        }.joined(separator: " ")
    }

    private func scoreDocument(_ data: [String: Any], terms: [String]) -> Int {
        guard !terms.isEmpty else { return 1 }
        let indexed = [
            "title", "body", "approvedBody", "approvedContent", "processingIndexText",
            "summaryDraft", "actionItemsDraft", "prayerPromptsDraft", "speaker",
            "sermonSpeaker", "churchName", "mediaTypes", "tags", "scriptureRefs",
            "scriptureReferences"
        ].compactMap { key -> String? in
            if let string = stringValue(data[key]) { return string }
            let array = stringArray(data[key])
            return array.isEmpty ? nil : array.joined(separator: " ")
        }.joined(separator: " ").lowercased()

        return terms.reduce(0) { partial, term in
            partial + (indexed.contains(term) ? 1 : 0)
        }
    }

    private func matchesFilters(_ data: [String: Any], filters: ChurchNotesSearchFilters) -> Bool {
        if let shared = filters.sharedOnly, ((data["isPublic"] as? Bool) ?? false) != shared { return false }
        if !filters.churchId.isEmpty, stringValue(data["churchId"]) != filters.churchId { return false }
        if !filters.scripture.isEmpty {
            let refs = stringArray(data["scriptureRefs"]) + stringArray(data["scriptureReferences"])
            if !refs.joined(separator: " ").localizedCaseInsensitiveContains(filters.scripture) { return false }
        }
        if let mediaType = filters.mediaType, !stringArray(data["mediaTypes"]).contains(mediaType) { return false }
        if filters.hasTranscript == true, (data["hasTranscript"] as? Bool) != true { return false }
        if filters.hasOCR == true, (data["hasOCR"] as? Bool) != true { return false }
        if filters.hasStudyGuide == true, (data["hasStudyGuide"] as? Bool) != true { return false }
        if filters.hasActionItems == true, (data["hasActionItems"] as? Bool) != true { return false }
        if filters.fromDate != nil || filters.toDate != nil {
            guard let createdAt = dateValue(data["createdAt"]) else { return false }
            if let from = filters.fromDate, createdAt < from { return false }
            if let to = filters.toDate, createdAt > to { return false }
        }
        return true
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }

    private func bestExcerpt(from data: [String: Any], terms: [String]) -> String {
        let candidates = ["approvedBody", "body", "processingIndexText", "summaryDraft"]
            .compactMap { stringValue(data[$0]) }
            .filter { !$0.isEmpty }
        let selected = candidates.first { candidate in
            terms.contains { candidate.localizedCaseInsensitiveContains($0) }
        } ?? candidates.first ?? ""
        return String(selected.prefix(180))
    }

    private func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }
}

struct ChurchNotesSearchFilters: Equatable {
    var sharedOnly: Bool?
    var churchId = ""
    var scripture = ""
    var mediaType: String?
    var hasTranscript: Bool?
    var hasOCR: Bool?
    var hasStudyGuide: Bool?
    var hasActionItems: Bool?
    var fromDate: Date?
    var toDate: Date?

    var hasAnyFilter: Bool {
        sharedOnly != nil || !churchId.isEmpty || !scripture.isEmpty || mediaType != nil ||
        hasTranscript != nil || hasOCR != nil || hasStudyGuide != nil || hasActionItems != nil ||
        fromDate != nil || toDate != nil
    }
}

struct ChurchNotesSearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let excerpt: String
    let score: Int
    let mediaTypes: [String]
    let tags: [String]
}
