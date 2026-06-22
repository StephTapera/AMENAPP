// BereanMemoryManager.swift
// AMEN App — Trust Architecture Layer 3: Berean Memory Management
//
// Single source of truth for Berean memory CRUD operations.
// All mutations go through Firebase Callable Functions so that server-side
// Firestore rules and audit logging are always enforced.
//
// Threading: all @Published state is mutated on MainActor. Callers may
// await any async method from any context.

import Foundation
import FirebaseFunctions

// MARK: - BereanMemoryEntry

/// A single persisted memory entry surfaced by the `bereanGetMemory` callable.
/// Stored under users/{uid}/bereanMemory/{id} in Firestore.
struct BereanMemoryEntry: Identifiable, Codable {
    let id: String
    let content: String
    let category: MemoryCategory
    let provenance: Provenance
    let createdAt: Date
    var isLocked: Bool

    // MARK: Provenance

    struct Provenance: Codable {
        /// Human-readable action label, e.g. "Saved during study session".
        let action: String
        /// Conversation ID that produced this entry, if any.
        let conversationId: String?
    }

    // MARK: MemoryCategory

    enum MemoryCategory: String, Codable, CaseIterable {
        case studyPreference     = "STUDY_PREFERENCE"
        case prayerRequest       = "PRAYER_REQUEST"
        case churchInvolvement   = "CHURCH_INVOLVEMENT"
        case savedStudy          = "SAVED_STUDY"
        case ongoingQuestion     = "ONGOING_QUESTION"
        case readingPlan         = "READING_PLAN"
        case translationPreference = "TRANSLATION_PREFERENCE"

        var displayName: String {
            rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }

        var systemImage: String {
            switch self {
            case .studyPreference:      return "books.vertical"
            case .prayerRequest:        return "hands.sparkles"
            case .churchInvolvement:    return "building.2"
            case .savedStudy:           return "bookmark.fill"
            case .ongoingQuestion:      return "questionmark.bubble"
            case .readingPlan:          return "list.bullet.rectangle"
            case .translationPreference: return "character.book.closed"
            }
        }

        var accentColor: String {
            // Returns a semantic name rather than a SwiftUI Color so this
            // model layer stays UI-framework agnostic.
            switch self {
            case .studyPreference:      return "indigo"
            case .prayerRequest:        return "purple"
            case .churchInvolvement:    return "green"
            case .savedStudy:           return "blue"
            case .ongoingQuestion:      return "orange"
            case .readingPlan:          return "teal"
            case .translationPreference: return "cyan"
            }
        }
    }

    // MARK: Codable — Date decoded as seconds-since-epoch Double

    enum CodingKeys: String, CodingKey {
        case id, content, category, provenance, createdAt, isLocked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        content    = try c.decode(String.self, forKey: .content)
        category   = try c.decodeIfPresent(MemoryCategory.self, forKey: .category) ?? .savedStudy
        provenance = try c.decodeIfPresent(Provenance.self, forKey: .provenance)
                        ?? Provenance(action: "Saved by Berean", conversationId: nil)
        isLocked   = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        let ts     = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        createdAt  = Date(timeIntervalSince1970: ts)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                              forKey: .id)
        try c.encode(content,                         forKey: .content)
        try c.encode(category,                        forKey: .category)
        try c.encode(provenance,                      forKey: .provenance)
        try c.encode(isLocked,                        forKey: .isLocked)
        try c.encode(createdAt.timeIntervalSince1970, forKey: .createdAt)
    }
}

// MARK: - BereanMemoryManager

/// ObservableObject that manages the full lifecycle of Berean memory entries
/// for a single authenticated user.
///
/// Usage:
/// ```swift
/// @StateObject private var manager = BereanMemoryManager()
/// ...
/// .task { await manager.fetchEntries(userId: uid) }
/// ```
@MainActor
final class BereanMemoryManager: ObservableObject {

    // MARK: Published state

    @Published var entries: [BereanMemoryEntry] = []
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: Private

    private let functions = Functions.functions()

    // MARK: Derived helpers

    /// All categories that are currently present in `entries`, in canonical order.
    var presentCategories: [BereanMemoryEntry.MemoryCategory] {
        let order = BereanMemoryEntry.MemoryCategory.allCases
        let occupied = Set(entries.map(\.category))
        return order.filter { occupied.contains($0) }
    }

    func entries(for category: BereanMemoryEntry.MemoryCategory) -> [BereanMemoryEntry] {
        entries.filter { $0.category == category }
    }

    // MARK: Fetch

    /// Loads all memory entries for `userId` from the `bereanGetMemory` callable.
    func fetchEntries(userId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("bereanGetMemory")
            let result   = try await callable.call(["userId": userId])
            guard let raw = result.data as? [[String: Any]] else {
                entries = []
                return
            }
            let data    = try JSONSerialization.data(withJSONObject: raw)
            entries     = try JSONDecoder().decode([BereanMemoryEntry].self, from: data)
        } catch {
            self.error = error
        }
    }

    // MARK: Delete single entry

    /// Deletes the entry with `id`. No-ops silently if the entry is locked.
    func deleteEntry(_ id: String, userId: String) async {
        guard let entry = entries.first(where: { $0.id == id }),
              !entry.isLocked else { return }
        error = nil
        do {
            let callable = functions.httpsCallable("bereanDeleteMemory")
            _ = try await callable.call(["userId": userId, "entryId": id])
            entries.removeAll { $0.id == id }
        } catch {
            self.error = error
        }
    }

    // MARK: Delete all

    /// Permanently deletes every memory entry for `userId`.
    func deleteAll(userId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("bereanDeleteAllMemory")
            _ = try await callable.call(["userId": userId])
            entries = []
        } catch {
            self.error = error
        }
    }

    // MARK: Toggle lock

    /// Flips the `isLocked` state of the entry with `id` via the server and
    /// re-fetches the full list on success to stay in sync with server truth.
    func toggleLock(_ id: String, userId: String) async {
        error = nil
        do {
            let callable = functions.httpsCallable("bereanToggleMemoryLock")
            _ = try await callable.call(["userId": userId, "entryId": id])
            // Optimistically flip local state while the re-fetch is in-flight.
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].isLocked.toggle()
            }
            // Full re-fetch keeps client consistent with server truth.
            await fetchEntries(userId: userId)
        } catch {
            self.error = error
        }
    }
}
