import Foundation
import FirebaseFirestore
import FirebaseAuth

// Firestore-backed service for the Church Notes Context Engine.
// All reads enforce ownership and group membership via security rules.
// Server-side callables handle AI-generated writes; client only approves/edits/rejects.
@MainActor
final class ChurchNotesContextService {

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Smart Recap

    func saveRecap(_ recap: CNSmartRecap) async throws {
        try requireAuth()
        let ref = db.collection("churchNotes").document(recap.noteId)
            .collection("recaps").document(recap.id)
        try ref.setData(from: recap)
    }

    func loadRecap(for noteId: String) async throws -> CNSmartRecap? {
        try requireAuth()
        let snap = try await db.collection("churchNotes").document(noteId)
            .collection("recaps")
            .order(by: "generatedAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        return try snap.documents.first.map { try $0.data(as: CNSmartRecap.self) }
    }

    // MARK: - Growth Timeline

    func saveGrowthEntry(_ entry: CNGrowthEntry) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChurchNotesContextError.unauthenticated }
        let ref = db.collection("users").document(uid)
            .collection("churchNotesMemory").document(entry.id)
        try ref.setData(from: entry)
    }

    func loadGrowthTimeline() async throws -> [CNGrowthEntry] {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChurchNotesContextError.unauthenticated }
        let snap = try await db.collection("users").document(uid)
            .collection("churchNotesMemory")
            .order(by: "date", descending: true)
            .limit(to: 50)
            .getDocuments()
        return try snap.documents.compactMap { try $0.data(as: CNGrowthEntry.self) }
    }

    func listenGrowthTimeline(onChange: @escaping ([CNGrowthEntry]) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let listener = db.collection("users").document(uid)
            .collection("churchNotesMemory")
            .order(by: "date", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                guard error == nil, let docs = snapshot?.documents else { return }
                let entries = docs.compactMap { try? $0.data(as: CNGrowthEntry.self) }
                Task { @MainActor in onChange(entries) }
            }
        listeners.append(listener)
    }

    // MARK: - Group Insights

    func loadGroupInsights(for churchId: String) async throws -> CNGroupInsight? {
        try requireAuth()
        let snap = try await db.collection("churches").document(churchId)
            .collection("noteInsights")
            .order(by: "generatedAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        return try snap.documents.first.map { try $0.data(as: CNGroupInsight.self) }
    }

    // MARK: - Action Suggestion Approval
    // Client only updates approvalState + editedText; server writes the canonical actionItem

    func approveActionSuggestion(_ suggestion: CNActionSuggestion, noteId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChurchNotesContextError.unauthenticated }
        let ref = db.collection("churchNotes").document(noteId)
            .collection("actions").document(suggestion.id)
        try await ref.setData([
            "approvalState": CNApprovalState.approved.rawValue,
            "editedText": suggestion.editedText as Any,
            "approvedBy": uid,
            "approvedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func rejectActionSuggestion(_ suggestion: CNActionSuggestion, noteId: String) async throws {
        try requireAuth()
        let ref = db.collection("churchNotes").document(noteId)
            .collection("actions").document(suggestion.id)
        try await ref.setData([
            "approvalState": CNApprovalState.rejected.rawValue
        ], merge: true)
    }

    // MARK: - Provenance Audit Trail

    func saveProvenanceLabel(_ label: CNProvenanceLabel, noteId: String, itemId: String) async throws {
        try requireAuth()
        let data: [String: Any] = [
            "itemId": itemId,
            "source": label.source,
            "confidence": label.confidence.rawValue,
            "whySuggested": label.whySuggested,
            "recordedAt": FieldValue.serverTimestamp()
        ]
        let ref = db.collection("churchNotes").document(noteId)
            .collection("provenance").document(itemId)
        try await ref.setData(data)
    }

    // MARK: - Private

    private func requireAuth() throws {
        guard Auth.auth().currentUser != nil else { throw ChurchNotesContextError.unauthenticated }
    }
}

// MARK: - Errors

enum ChurchNotesContextError: LocalizedError {
    case unauthenticated
    case unauthorized
    case notFound
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:      return "You must be signed in."
        case .unauthorized:         return "You don't have access to this content."
        case .notFound:             return "Content not found."
        case .serverError(let msg): return msg
        }
    }
}
