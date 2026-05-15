import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Owns the lifecycle of Church Note action items — drafts (suggested), approvals,
/// rejection, and completion. The service never writes the `actionItems` subcollection
/// directly; it always goes through callables so the server enforces permission
/// + adds provenance fields the client cannot fabricate.
@MainActor
final class ChurchNoteActionItemsService: ObservableObject {

    @Published private(set) var approvedItems: [ChurchNoteActionItem] = []
    @Published private(set) var draftItems: [String] = []
    @Published private(set) var draftJobId: String?
    @Published private(set) var draftIsRejected = false
    @Published private(set) var draftIsApproved = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private var itemsListener: ListenerRegistration?
    private var draftListener: ListenerRegistration?

    deinit {
        itemsListener?.remove()
        draftListener?.remove()
    }

    // MARK: - Listening

    func startListening(noteId: String) {
        stopListening()

        itemsListener = db.collection("churchNotes")
            .document(noteId)
            .collection("actionItems")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let items: [ChurchNoteActionItem] = snapshot?.documents.compactMap { doc in
                    ChurchNoteActionItem.fromFirestore(id: doc.documentID, data: doc.data())
                } ?? []
                Task { @MainActor [weak self] in
                    self?.approvedItems = items
                }
            }
    }

    /// Listens to the latest processing job that has a non-empty `actionItemsDraft`
    /// so the review UI can show pending suggestions. The service only surfaces
    /// drafts the user hasn't already approved or rejected.
    func startListeningToLatestDraft(noteId: String) {
        draftListener?.remove()
        draftListener = db.collection("churchNotes")
            .document(noteId)
            .collection("processingJobs")
            .whereField("actionItemsDraft", isNotEqualTo: NSNull())
            .order(by: "actionItemsDraft")
            .order(by: "updatedAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let doc      = snapshot?.documents.first
                let data     = doc?.data() ?? [:]
                let items    = (data["actionItemsDraft"] as? [String]) ?? []
                let approved = (data["approved_actionItemsDraft"] as? Bool) ?? false
                let rejected = (data["rejected_actionItemsDraft"] as? Bool) ?? false
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.draftItems      = items
                    self.draftJobId      = doc?.documentID
                    self.draftIsApproved = approved
                    self.draftIsRejected = rejected
                }
            }
    }

    func stopListening() {
        itemsListener?.remove()
        itemsListener = nil
        draftListener?.remove()
        draftListener = nil
    }

    // MARK: - Mutations

    func approveItems(
        noteId: String,
        jobId: String,
        approvals: [ChurchNoteActionItemApproval]
    ) async {
        guard !approvals.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let payload: [String: Any] = [
            "noteId": noteId,
            "jobId":  jobId,
            "items":  approvals.map { approval -> [String: Any] in
                var dict: [String: Any] = ["text": approval.text]
                if let idx = approval.originalIndex { dict["originalIndex"] = idx }
                return dict
            },
        ]
        do {
            _ = try await functions
                .httpsCallable("approveChurchNoteActionItems")
                .call(payload)
        } catch {
            errorMessage = "Could not save approved action items."
        }
    }

    func rejectDraft(noteId: String, jobId: String, reason: String? = nil) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        var payload: [String: Any] = ["noteId": noteId, "jobId": jobId]
        if let reason, !reason.isEmpty { payload["reason"] = reason }
        do {
            _ = try await functions
                .httpsCallable("rejectChurchNoteActionItemsDraft")
                .call(payload)
        } catch {
            errorMessage = "Could not reject draft action items."
        }
    }

    func setCompletion(noteId: String, itemId: String, completed: Bool) async {
        // Optimistic update — Firestore listener will reconcile on success/failure.
        if let idx = approvedItems.firstIndex(where: { $0.id == itemId }) {
            let existing = approvedItems[idx]
            approvedItems[idx] = ChurchNoteActionItem(
                id: existing.id, noteId: existing.noteId, text: existing.text,
                originalText: existing.originalText, wasEdited: existing.wasEdited,
                sourceJobId: existing.sourceJobId,
                approvedBy: existing.approvedBy, approvedAt: existing.approvedAt,
                completed: completed,
                completedBy: completed ? Auth.auth().currentUser?.uid : nil,
                completedAt: completed ? Date() : nil,
                createdAt: existing.createdAt, updatedAt: Date()
            )
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            _ = try await functions
                .httpsCallable("setChurchNoteActionItemCompletion")
                .call([
                    "noteId":    noteId,
                    "itemId":    itemId,
                    "completed": completed,
                ])
        } catch {
            errorMessage = "Could not update completion. Try again."
        }
    }
}
