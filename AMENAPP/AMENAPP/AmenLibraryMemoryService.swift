// AmenLibraryMemoryService.swift
// AMENAPP

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct AmenLibraryReadEvent: Codable {
    let bookId: String
    let bookTitle: String
    let bookAuthor: String
    let thumbnailURL: String?
    let openedAt: Date
    var lastSeenAt: Date
    var progressFraction: Double   // 0.0–1.0
    var isCompleted: Bool
    var isAbandoned: Bool
    var formatPreference: AmenBookFormat
}

enum AmenBookFormat: String, Codable, CaseIterable {
    case ebook     = "ebook"
    case audio     = "audio"
    case physical  = "physical"
    case unknown   = "unknown"
}

struct AmenLibraryMemorySnapshot {
    let recentlyOpened: [AmenLibraryReadEvent]  // last 10, newest first
    let inProgress: [AmenLibraryReadEvent]       // 0 < progress < 1.0
    let completed: [AmenLibraryReadEvent]
    let abandoned: [AmenLibraryReadEvent]
    let preferredFormat: AmenBookFormat
    let topCategories: [String]                  // by read frequency
    let notedBookIds: Set<String>               // books that have highlights/notes
}

// MARK: - Service

@MainActor
final class AmenLibraryMemoryService: ObservableObject {

    static let shared = AmenLibraryMemoryService()

    @Published private(set) var snapshot = AmenLibraryMemorySnapshot(
        recentlyOpened: [], inProgress: [], completed: [], abandoned: [],
        preferredFormat: .unknown, topCategories: [], notedBookIds: []
    )

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Start

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("libraryMemory")
            .order(by: "lastSeenAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                let events = snap.documents.compactMap { try? $0.data(as: AmenLibraryReadEvent.self) }
                Task { await self?.rebuildSnapshot(events) }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Record Events

    func recordOpen(book: WLBook, format: AmenBookFormat = .unknown) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(uid)
            .collection("libraryMemory").document(book.id)

        Task {
            if var existing = try? await ref.getDocument(as: AmenLibraryReadEvent.self) {
                existing.lastSeenAt = Date()
                existing.formatPreference = format != .unknown ? format : existing.formatPreference
                try? ref.setData(from: existing, merge: false)
            } else {
                let event = AmenLibraryReadEvent(
                    bookId: book.id, bookTitle: book.title,
                    bookAuthor: book.primaryAuthor, thumbnailURL: book.thumbnailURL,
                    openedAt: Date(), lastSeenAt: Date(),
                    progressFraction: 0, isCompleted: false, isAbandoned: false,
                    formatPreference: format
                )
                try? ref.setData(from: event)
            }
        }
    }

    func updateProgress(bookId: String, progress: Double) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let clamped = min(max(progress, 0), 1)
        let ref = db.collection("users").document(uid)
            .collection("libraryMemory").document(bookId)
        ref.updateData([
            "progressFraction": clamped,
            "isCompleted": clamped >= 1.0,
            "isAbandoned": false,
            "lastSeenAt": FieldValue.serverTimestamp()
        ])
    }

    func markAbandoned(bookId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("libraryMemory").document(bookId)
            .updateData(["isAbandoned": true])
    }

    func markCompleted(bookId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("libraryMemory").document(bookId)
            .updateData(["isCompleted": true, "progressFraction": 1.0, "isAbandoned": false])
    }

    func recordNote(bookId: String) {
        // Adds bookId to the notedBookIds set via local + Firestore merge
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("libraryMemoryMeta").document("notes")
            .setData(["notedBookIds": FieldValue.arrayUnion([bookId])], merge: true)
    }

    // MARK: - Contextual Labels

    /// Returns the most relevant CTA label for a book, or nil if not in memory.
    func continuationLabel(for bookId: String) -> String? {
        if let event = snapshot.inProgress.first(where: { $0.bookId == bookId }) {
            let pct = Int(event.progressFraction * 100)
            return pct > 0 ? "Continue — \(pct)% in" : "Pick Up Where You Left Off"
        }
        if snapshot.recentlyOpened.first(where: { $0.bookId == bookId }) != nil {
            return "Resume"
        }
        if snapshot.completed.first(where: { $0.bookId == bookId }) != nil {
            return "Read Again"
        }
        return nil
    }

    func wasRecentlyOpened(_ bookId: String) -> Bool {
        snapshot.recentlyOpened.contains { $0.bookId == bookId }
    }

    // MARK: - Snapshot Rebuild

    private func rebuildSnapshot(_ events: [AmenLibraryReadEvent]) async {
        let recent = Array(events.prefix(10))
        let inProg = events.filter { !$0.isCompleted && !$0.isAbandoned && $0.progressFraction > 0 }
        let done   = events.filter { $0.isCompleted }
        let gone   = events.filter { $0.isAbandoned }

        // Preferred format: mode of non-unknown formats
        let formatCounts = Dictionary(grouping: events.map(\.formatPreference).filter { $0 != .unknown }) { $0 }
        let preferredFormat = formatCounts.max { $0.value.count < $1.value.count }?.key ?? .unknown

        // Noted book IDs
        let notedIds = await loadNotedBookIds()

        snapshot = AmenLibraryMemorySnapshot(
            recentlyOpened: recent, inProgress: inProg, completed: done, abandoned: gone,
            preferredFormat: preferredFormat, topCategories: [], notedBookIds: notedIds
        )
    }

    private func loadNotedBookIds() async -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let doc = try? await db.collection("users").document(uid)
            .collection("libraryMemoryMeta").document("notes").getDocument()
        let ids = doc?.data()?["notedBookIds"] as? [String] ?? []
        return Set(ids)
    }
}
