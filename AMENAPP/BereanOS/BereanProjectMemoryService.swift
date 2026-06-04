// BereanProjectMemoryService.swift
// AMENAPP — BereanOS
// Reads/writes memory entries for a Berean OS project.
// All writes are gated by AMENFeatureFlags.shared.bereanOSMemoryBrainEnabled.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - BereanProjectMemoryService

@MainActor
final class BereanProjectMemoryService: ObservableObject {
    static let shared = BereanProjectMemoryService()

    @Published private(set) var entries: [BereanProjectMemoryEntry] = []
    @Published private(set) var isExtracting = false
    @Published private(set) var lastError: String?

    // MARK: Private dependencies

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    // MARK: - Init

    private init() {}

    // MARK: - Fetch

    /// Attaches a live Firestore listener for the given project's memory entries.
    func fetchEntries(projectId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            lastError = "Not signed in."
            return
        }

        listener?.remove()

        let path = BereanOSFirestore.memoryEntries(uid: uid, projectId: projectId)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false

            self.listener = self.db.collection(path)
                .whereField("isResolved", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }

                    if let error {
                        self.lastError = error.localizedDescription
                        if !didResume {
                            didResume = true
                            continuation.resume(throwing: error)
                        }
                        return
                    }

                    guard let snapshot else { return }

                    let decoded: [BereanProjectMemoryEntry] = snapshot.documents.compactMap { doc in
                        self.decode(doc)
                    }
                    self.entries = Self.sorted(decoded)
                    self.lastError = nil

                    if !didResume {
                        didResume = true
                        continuation.resume()
                    }
                }
        }
    }

    // MARK: - Extract (Cloud Function)

    /// Sends `text` to the `bereanExtractProjectMemory` Cloud Function and
    /// persists the returned entries. Gated by feature flag.
    func extractMemory(from text: String, projectId: String) async throws {
        guard AMENFeatureFlags.shared.bereanOSMemoryBrainEnabled else { return }

        isExtracting = true
        lastError = nil
        defer { isExtracting = false }

        let callable = functions.httpsCallable("bereanExtractProjectMemory")
        _ = try await callable.call(["text": text, "projectId": projectId])
        // The live listener will pick up the newly written entries automatically.
    }

    // MARK: - Resolve

    /// Marks an entry as resolved (soft-delete). Gated by feature flag.
    func resolveEntry(id: String, projectId: String) async throws {
        guard AMENFeatureFlags.shared.bereanOSMemoryBrainEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "BereanProjectMemoryService", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in."])
        }

        let path = BereanOSFirestore.memoryEntry(uid: uid, projectId: projectId, entryId: id)
        try await db.document(path).updateData(["isResolved": true])
        entries.removeAll { $0.id == id }
    }

    // MARK: - Filter helper

    func entriesByType(_ type: BereanProjectMemoryEntryType) -> [BereanProjectMemoryEntry] {
        entries.filter { $0.entryType == type }
    }

    // MARK: - Private helpers

    /// Sort order: facts -> decisions -> questions -> others
    private static func sorted(_ raw: [BereanProjectMemoryEntry]) -> [BereanProjectMemoryEntry] {
        raw.sorted { lhs, rhs in
            sortPriority(lhs.entryType) < sortPriority(rhs.entryType)
        }
    }

    private static func sortPriority(_ type: BereanProjectMemoryEntryType) -> Int {
        switch type {
        case .knownFact:     return 0
        case .decision:      return 1
        case .openQuestion:  return 2
        default:             return 3
        }
    }

    private func decode(_ doc: DocumentSnapshot) -> BereanProjectMemoryEntry? {
        guard let data = doc.data() else { return nil }

        let entryType = BereanProjectMemoryEntryType(rawValue: data["entryType"] as? String ?? "")
            ?? .knownFact
        let confidence = BereanConfidenceLevel(rawValue: data["confidence"] as? String ?? "")
            ?? .uncertain

        return BereanProjectMemoryEntry(
            id: doc.documentID,
            projectId: data["projectId"] as? String ?? "",
            entryType: entryType,
            content: data["content"] as? String ?? "",
            confidence: confidence,
            sourceIds: data["sourceIds"] as? [String] ?? [],
            linkedProjectEntryIds: data["linkedProjectEntryIds"] as? [String] ?? [],
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            lastVerifiedAt: (data["lastVerifiedAt"] as? Timestamp)?.dateValue(),
            isAutoExtracted: data["isAutoExtracted"] as? Bool ?? false,
            isResolved: data["isResolved"] as? Bool ?? false
        )
    }
}
