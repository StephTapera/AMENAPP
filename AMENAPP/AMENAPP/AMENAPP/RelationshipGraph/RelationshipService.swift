import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - RelationshipError

enum RelationshipError: LocalizedError {
    case notAuthenticated
    case notAuthorized
    case discipleshipAlreadyExists
    case groupNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please sign in to continue."
        case .notAuthorized: return "You don't have permission for this action."
        case .discipleshipAlreadyExists: return "A discipleship connection already exists."
        case .groupNotFound: return "Group not found."
        }
    }
}

// MARK: - RelationshipService

@MainActor
final class RelationshipService: ObservableObject {
    static let shared = RelationshipService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Churches

    func createChurch(name: String, lat: Double, lng: Double, denomination: String? = nil) async throws -> RelationshipChurch {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }
        let ref = db.collection("churches").document()
        var church = RelationshipChurch(name: name, locationLat: lat, locationLng: lng,
                                        denomination: denomination, ownerUids: [uid], createdAt: Date())
        try ref.setData(from: church)
        church.id = ref.documentID
        return church
    }

    func fetchChurch(_ churchId: String) async throws -> RelationshipChurch? {
        let doc = try await db.collection("churches").document(churchId).getDocument()
        return try? doc.data(as: RelationshipChurch.self)
    }

    // MARK: - Groups

    func createGroup(
        churchId: String? = nil,
        name: String,
        type: AmenGroup.GroupType,
        visibility: AmenGroup.GroupVisibility = .public,
        studyPassage: String? = nil
    ) async throws -> AmenGroup {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }

        let batch = db.batch()
        let groupRef = db.collection("groups").document()
        var group = AmenGroup(churchId: churchId, name: name, type: type,
                              hostUids: [uid], memberUids: [uid], visibility: visibility,
                              studyPassage: studyPassage, createdAt: Date())
        try batch.setData(from: group, forDocument: groupRef)

        let membershipRef = db.collection("memberships").document()
        let membership = Membership(uid: uid, groupId: groupRef.documentID, role: .host, joinedAt: Date())
        try batch.setData(from: membership, forDocument: membershipRef)

        try await batch.commit()
        group.id = groupRef.documentID
        return group
    }

    func joinGroup(_ groupId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }

        let batch = db.batch()
        let groupRef = db.collection("groups").document(groupId)
        batch.updateData(["memberUids": FieldValue.arrayUnion([uid])], forDocument: groupRef)

        let membershipRef = db.collection("memberships").document()
        let membership = Membership(uid: uid, groupId: groupId, role: .member, joinedAt: Date())
        try batch.setData(from: membership, forDocument: membershipRef)
        try await batch.commit()
    }

    func leaveGroup(_ groupId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }

        let batch = db.batch()
        let groupRef = db.collection("groups").document(groupId)
        batch.updateData(["memberUids": FieldValue.arrayRemove([uid])], forDocument: groupRef)

        let memberships = try await db.collection("memberships")
            .whereField("uid", isEqualTo: uid)
            .whereField("groupId", isEqualTo: groupId)
            .getDocuments()
        for doc in memberships.documents { batch.deleteDocument(doc.reference) }
        try await batch.commit()
    }

    func fetchMyGroups() async throws -> [AmenGroup] {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }
        let snapshot = try await db.collection("groups")
            .whereField("memberUids", arrayContains: uid)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: AmenGroup.self) }
    }

    func fetchGroup(_ groupId: String) async throws -> AmenGroup? {
        let doc = try await db.collection("groups").document(groupId).getDocument()
        return try? doc.data(as: AmenGroup.self)
    }

    func fetchMembers(of groupId: String) async throws -> [Membership] {
        let snapshot = try await db.collection("memberships")
            .whereField("groupId", isEqualTo: groupId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Membership.self) }
    }

    // MARK: - Follows (uses existing followerId/followingId field names for compatibility)

    func follow(uid targetUid: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }
        guard uid != targetUid else { return }
        let followId = "\(uid)_\(targetUid)"
        try await db.collection("follows").document(followId).setData([
            "followerId": uid,
            "followingId": targetUid,
            "createdAt": FieldValue.serverTimestamp()
        ], merge: false)
    }

    func unfollow(uid targetUid: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }
        let followId = "\(uid)_\(targetUid)"
        try await db.collection("follows").document(followId).delete()
    }

    func isFollowing(uid targetUid: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let followId = "\(uid)_\(targetUid)"
        let doc = try await db.collection("follows").document(followId).getDocument()
        return doc.exists
    }

    // MARK: - Discipleship

    func requestDiscipleship(with targetUid: String) async throws -> DiscipleshipPair {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }

        let existing = try await db.collection("discipleship")
            .whereField("uids", arrayContains: uid)
            .getDocuments()
        for doc in existing.documents {
            let uids = doc.data()["uids"] as? [String] ?? []
            if uids.contains(targetUid) { throw RelationshipError.discipleshipAlreadyExists }
        }

        let ref = db.collection("discipleship").document()
        var pair = DiscipleshipPair(uids: [uid, targetUid].sorted(), status: .pending,
                                    initiatedBy: uid, createdAt: Date())
        try ref.setData(from: pair)
        pair.id = ref.documentID
        return pair
    }

    func acceptDiscipleship(pairId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }
        let ref = db.collection("discipleship").document(pairId)
        let doc = try await ref.getDocument()
        guard let uids = doc.data()?["uids"] as? [String], uids.contains(uid) else {
            throw RelationshipError.notAuthorized
        }
        try await ref.updateData(["status": DiscipleshipPair.Status.active.rawValue])
    }

    func endDiscipleship(pairId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }
        let ref = db.collection("discipleship").document(pairId)
        let doc = try await ref.getDocument()
        guard let uids = doc.data()?["uids"] as? [String], uids.contains(uid) else {
            throw RelationshipError.notAuthorized
        }
        try await ref.updateData(["status": DiscipleshipPair.Status.ended.rawValue])
    }

    func fetchMyDiscipleshipPairs() async throws -> [DiscipleshipPair] {
        guard let uid = Auth.auth().currentUser?.uid else { throw RelationshipError.notAuthenticated }
        let snapshot = try await db.collection("discipleship")
            .whereField("uids", arrayContains: uid)
            .whereField("status", in: [
                DiscipleshipPair.Status.pending.rawValue,
                DiscipleshipPair.Status.active.rawValue
            ])
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: DiscipleshipPair.self) }
    }
}
