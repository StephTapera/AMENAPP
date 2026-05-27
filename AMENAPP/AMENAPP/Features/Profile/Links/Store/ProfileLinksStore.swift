import Foundation
import FirebaseFirestore

// MARK: - ProfileLinksStore

/// Observable store for a user's typed profile link slots.
/// Streams the `profile.links` array from Firestore and exposes
/// async mutating operations. Consumed by Agent C (Action Chips)
/// via `linksByType(_:)` and by the Profile Header UI.
@MainActor
@Observable
public final class ProfileLinksStore {

    // MARK: Public State

    private(set) var slots: [LinkSlot] = []
    private(set) var isLoading: Bool = false

    // MARK: Private

    private let userId: String
    private var listenerRegistration: ListenerRegistration?

    // MARK: Init

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Lifecycle

    /// Attaches the Firestore snapshot listener and begins streaming slots.
    func start() {
        guard listenerRegistration == nil else { return }
        isLoading = true

        let docRef = Firestore.firestore()
            .collection("users")
            .document(userId)

        listenerRegistration = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            Task { @MainActor in
                self.isLoading = false
                if let error {
                    // Surface the error in the future via an error state property;
                    // for now log and leave existing slots intact.
                    print("[ProfileLinksStore] snapshot error: \(error.localizedDescription)")
                    return
                }
                guard let data = snapshot?.data() else { return }
                self.slots = Self.decodeSlots(from: data)
            }
        }
    }

    /// Detaches the Firestore listener and stops streaming.
    func stop() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    // MARK: - Mutations

    /// Appends a new slot to `profile.links` in Firestore.
    /// Throws `ProfileLinksError.invalidURLScheme` if the URL scheme is not http or https.
    func add(_ slot: LinkSlot) async throws {
        try validateURLScheme(slot.url)
        let ref = userDocRef()
        let newData = slot.firestoreData
        try await ref.updateData([
            "profile.links": FieldValue.arrayUnion([newData])
        ])
    }

    /// Removes the slot with the given `id` from `profile.links` in Firestore.
    /// Throws `ProfileLinksError.slotNotFound` if the id is unknown.
    func remove(id: String) async throws {
        guard let slot = slots.first(where: { $0.id == id }) else {
            throw ProfileLinksError.slotNotFound(id)
        }
        let ref = userDocRef()
        try await ref.updateData([
            "profile.links": FieldValue.arrayRemove([slot.firestoreData])
        ])
    }

    /// Replaces all slots with the provided array, updating the `order` field
    /// to match the position in `newOrder`.
    func reorder(_ newOrder: [LinkSlot]) async throws {
        let updated = newOrder.enumerated().map { index, slot -> LinkSlot in
            LinkSlot(id: slot.id, type: slot.type, url: slot.url, label: slot.label, order: index)
        }
        let ref = userDocRef()
        let encodedArray = updated.map { $0.firestoreData }
        try await ref.updateData(["profile.links": encodedArray])
    }

    /// Replaces an existing slot in-place within `profile.links`.
    /// Performs a read-modify-write using the current in-memory snapshot.
    func update(_ slot: LinkSlot) async throws {
        try validateURLScheme(slot.url)
        var updated = slots
        guard let index = updated.firstIndex(where: { $0.id == slot.id }) else {
            throw ProfileLinksError.slotNotFound(slot.id)
        }
        updated[index] = slot
        let ref = userDocRef()
        let encodedArray = updated.map { $0.firestoreData }
        try await ref.updateData(["profile.links": encodedArray])
    }

    // MARK: - Queries

    /// Returns all slots whose type matches `type`, sorted by `order`.
    /// Consumed by Agent C for the Give and Visit Church action chips.
    func linksByType(_ type: LinkType) -> [LinkSlot] {
        slots
            .filter { $0.type == type }
            .sorted { $0.order < $1.order }
    }

    // MARK: - Private Helpers

    private func userDocRef() -> DocumentReference {
        Firestore.firestore().collection("users").document(userId)
    }

    private func validateURLScheme(_ url: URL) throws {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            throw ProfileLinksError.invalidURLScheme(url)
        }
    }

    private static func decodeSlots(from data: [String: Any]) -> [LinkSlot] {
        guard
            let profile = data["profile"] as? [String: Any],
            let linksRaw = profile["links"] as? [[String: Any]]
        else { return [] }

        return linksRaw
            .compactMap { LinkSlot(firestoreData: $0) }
            .sorted { $0.order < $1.order }
    }
}

// MARK: - ProfileLinksError

enum ProfileLinksError: LocalizedError {
    case invalidURLScheme(URL)
    case slotNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidURLScheme(let url):
            return "Link URL must use http or https (got \"\(url.scheme ?? "none")\")."
        case .slotNotFound(let id):
            return "No link slot found with id \"\(id)\"."
        }
    }
}
