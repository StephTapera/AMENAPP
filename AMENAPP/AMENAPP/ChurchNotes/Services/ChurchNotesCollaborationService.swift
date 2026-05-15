import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class ChurchNotesCollaborationService: ObservableObject {
    @Published private(set) var collaborators: [ChurchNoteCollaborator] = []
    @Published private(set) var presence: [ChurchNotePresence] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var collaboratorsListener: ListenerRegistration?
    private var presenceListener: ListenerRegistration?
    private var noteId: String?

    var currentUid: String? { Auth.auth().currentUser?.uid }

    func start(noteId: String, currentRole: ChurchNoteCollaboratorRole = .viewer) {
        stop()
        self.noteId = noteId
        isLoading = true
        errorMessage = nil

        collaboratorsListener = db.collection("churchNotes")
            .document(noteId)
            .collection("collaborators")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.collaborators = snapshot?.documents.compactMap { document in
                        ChurchNoteCollaborator(documentID: document.documentID, data: document.data())
                    } ?? []
                }
            }

        presenceListener = db.collection("churchNotes")
            .document(noteId)
            .collection("presence")
            .order(by: "lastSeenAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.presence = snapshot?.documents.compactMap { document in
                        ChurchNotePresence(documentID: document.documentID, data: document.data())
                    } ?? []
                }
            }

        updatePresence(noteId: noteId, role: currentRole, isEditing: true)
    }

    func stop() {
        if let noteId, let uid = currentUid {
            db.collection("churchNotes")
                .document(noteId)
                .collection("presence")
                .document(uid)
                .delete()
        }
        collaboratorsListener?.remove()
        presenceListener?.remove()
        collaboratorsListener = nil
        presenceListener = nil
        noteId = nil
    }

    func updatePresence(
        noteId: String,
        role: ChurchNoteCollaboratorRole,
        isEditing: Bool,
        activeBlockId: String? = nil,
        editingState: ChurchNoteEditingState? = nil
    ) {
        guard let uid = currentUid else { return }
        let name = Auth.auth().currentUser?.displayName ?? "Someone"
        var payload: [String: Any] = [
            "uid": uid,
            "displayName": name,
            "role": role.rawValue,
            "isEditing": isEditing,
            // editingState supersedes the boolean isEditing for clients that
            // want richer state (viewing / editing / idle); both are written so
            // older clients keep working.
            "editingState": (editingState ?? (isEditing ? .editing : .viewing)).rawValue,
            "lastSeenAt": FieldValue.serverTimestamp(),
            "lastActiveAt": FieldValue.serverTimestamp(),
        ]
        if let activeBlockId {
            payload["activeBlockId"] = activeBlockId
        } else {
            payload["activeBlockId"] = NSNull()
        }
        db.collection("churchNotes")
            .document(noteId)
            .collection("presence")
            .document(uid)
            .setData(payload, merge: true)
    }

    /// Save guard: returns nil when the local edit is still on top of the latest
    /// remote revision; returns a `ChurchNoteRevisionConflict` when a different
    /// collaborator has saved a newer revision since the caller last loaded the
    /// note. Callers should surface a conflict prompt and refuse to silently
    /// overwrite — preserving collaborator work.
    func detectRevisionConflict(
        noteId: String,
        lastKnownRevision: Int?,
        lastKnownUpdatedAt: Date?
    ) async -> ChurchNoteRevisionConflict? {
        do {
            let snap = try await db.collection("churchNotes").document(noteId).getDocument()
            guard let data = snap.data() else { return nil }
            let remoteVersion = data["version"] as? Int
            let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            let remoteEditorUid = data["lastUpdatedByUid"] as? String

            // Version-based check (preferred): the document's version moved forward
            // beyond what the caller last saw.
            if let lastKnownRevision, let remoteVersion, remoteVersion > lastKnownRevision {
                return ChurchNoteRevisionConflict(
                    remoteVersion: remoteVersion,
                    remoteUpdatedAt: remoteUpdatedAt,
                    remoteEditorUid: remoteEditorUid
                )
            }
            // Timestamp fallback for legacy notes that don't carry a version field.
            if lastKnownRevision == nil,
               let lastKnownUpdatedAt,
               let remoteUpdatedAt,
               remoteUpdatedAt > lastKnownUpdatedAt.addingTimeInterval(0.5) {
                return ChurchNoteRevisionConflict(
                    remoteVersion: remoteVersion,
                    remoteUpdatedAt: remoteUpdatedAt,
                    remoteEditorUid: remoteEditorUid
                )
            }
            return nil
        } catch {
            // Read failure shouldn't claim a conflict — the save path will surface
            // the error if the network is unhealthy. Returning nil keeps current
            // optimistic save behaviour intact.
            return nil
        }
    }

    func share(noteId: String, collaboratorUid: String, role: ChurchNoteCollaboratorRole) async {
        await callCollaborationFunction(name: "shareChurchNoteWithCollaborators", payload: [
            "noteId": noteId,
            "collaboratorUid": collaboratorUid,
            "role": role.rawValue,
        ])
    }

    func updateRole(noteId: String, collaboratorUid: String, role: ChurchNoteCollaboratorRole) async {
        await callCollaborationFunction(name: "updateChurchNotePermissions", payload: [
            "noteId": noteId,
            "collaboratorUid": collaboratorUid,
            "role": role.rawValue,
            "remove": false,
        ])
    }

    func remove(noteId: String, collaboratorUid: String) async {
        await callCollaborationFunction(name: "updateChurchNotePermissions", payload: [
            "noteId": noteId,
            "collaboratorUid": collaboratorUid,
            "remove": true,
        ])
    }

    private func callCollaborationFunction(name: String, payload: [String: Any]) async {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await functions.httpsCallable(name).call(payload)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

enum ChurchNoteCollaboratorRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case editor
    case commenter
    case viewer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .editor: return "Editor"
        case .commenter: return "Commenter"
        case .viewer: return "Viewer"
        }
    }

    var canEdit: Bool { self == .owner || self == .editor }
    var canComment: Bool { self == .owner || self == .editor || self == .commenter }
}

struct ChurchNoteCollaborator: Identifiable, Equatable {
    let id: String
    let uid: String
    let role: ChurchNoteCollaboratorRole
    let displayName: String

    init(documentID: String, data: [String: Any]) {
        id = documentID
        uid = (data["uid"] as? String) ?? documentID
        role = ChurchNoteCollaboratorRole(rawValue: (data["role"] as? String) ?? "viewer") ?? .viewer
        displayName = (data["displayName"] as? String) ?? uid
    }
}

/// Richer per-user editing state. `viewing` means the user is open in the note
/// but not focused on a text field; `editing` means an active text field has
/// focus; `idle` means the user has been inactive for the staleness window.
enum ChurchNoteEditingState: String, Codable {
    case viewing
    case editing
    case idle
}

struct ChurchNotePresence: Identifiable, Equatable {
    let id: String
    let uid: String
    let displayName: String
    let role: ChurchNoteCollaboratorRole
    let isEditing: Bool
    let editingState: ChurchNoteEditingState
    /// The block / section the user is currently editing, if the editor reports it.
    let activeBlockId: String?
    /// Last time the client wrote a presence heartbeat. The UI treats presence as
    /// stale and hides it after `staleAfterSeconds` (see `isStale`).
    let lastActiveAt: Date?

    init(documentID: String, data: [String: Any]) {
        id = documentID
        uid = (data["uid"] as? String) ?? documentID
        displayName = (data["displayName"] as? String) ?? "Someone"
        role = ChurchNoteCollaboratorRole(rawValue: (data["role"] as? String) ?? "viewer") ?? .viewer
        isEditing = (data["isEditing"] as? Bool) ?? false
        let rawState = data["editingState"] as? String
        editingState = ChurchNoteEditingState(rawValue: rawState ?? "")
            ?? (isEditing ? .editing : .viewing)
        activeBlockId = data["activeBlockId"] as? String
        if let timestamp = data["lastActiveAt"] as? Timestamp {
            lastActiveAt = timestamp.dateValue()
        } else if let timestamp = data["lastSeenAt"] as? Timestamp {
            lastActiveAt = timestamp.dateValue()
        } else {
            lastActiveAt = nil
        }
    }

    static let staleAfterSeconds: TimeInterval = 90

    /// Presence beyond `staleAfterSeconds` since the last heartbeat is hidden so
    /// disconnected clients don't appear as live participants forever.
    var isStale: Bool {
        guard let lastActiveAt else { return false }
        return Date().timeIntervalSince(lastActiveAt) > Self.staleAfterSeconds
    }
}

/// Returned by `detectRevisionConflict` when the remote note has moved forward
/// beyond what the local caller last loaded. Callers surface a conflict prompt
/// and either refresh-from-remote or merge before saving.
struct ChurchNoteRevisionConflict: Equatable {
    let remoteVersion: Int?
    let remoteUpdatedAt: Date?
    let remoteEditorUid: String?
}
