// BereanMentorService.swift
// AMENAPP — Berean OS Mentor OS
//
// Manages real and AI mentor relationships for projects.
// Writes to the `bereanMentorships` top-level collection.
// All methods guard on `bereanOSMentorOSEnabled`.

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - BereanMentorService

@MainActor
final class BereanMentorService: ObservableObject {
    static let shared = BereanMentorService()

    @Published private(set) var myMentorships: [BereanMentorRelationship] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Request Mentor

    /// Creates a new mentorship relationship. When `mentorUid == nil` an AI mentorship is created.
    func requestMentor(mentorUid: String?, projectId: String?) async throws -> BereanMentorRelationship {
        guard AMENFeatureFlags.shared.bereanOSMentorOSEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard let currentUser = Auth.auth().currentUser else {
            throw BereanOSError.unauthorized
        }

        let relationshipId = db.collection(BereanOSFirestore.mentorships).document().documentID
        let now = Date()
        let relationship = BereanMentorRelationship(
            id: relationshipId,
            mentorUid: mentorUid,
            menteeUid: currentUser.uid,
            projectId: projectId,
            status: mentorUid == nil ? .active : .pending,
            mentorNotes: [],
            milestoneIds: [],
            createdAt: now
        )

        var data: [String: Any] = [
            "id": relationship.id,
            "menteeUid": relationship.menteeUid,
            "status": relationship.status.rawValue,
            "milestoneIds": relationship.milestoneIds,
            "createdAt": Timestamp(date: now),
            "isAIMentor": mentorUid == nil
        ]
        if let mentor = mentorUid { data["mentorUid"] = mentor }
        if let project = projectId { data["projectId"] = project }

        try await db
            .document(BereanOSFirestore.mentorship(relationshipId: relationshipId))
            .setData(data)

        myMentorships.append(relationship)
        return relationship
    }

    // MARK: - Fetch My Mentorships

    /// Loads all mentorships where the current user is the mentee.
    func fetchMyMentorships() async throws {
        guard AMENFeatureFlags.shared.bereanOSMentorOSEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard let currentUser = Auth.auth().currentUser else {
            throw BereanOSError.unauthorized
        }

        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db
            .collection(BereanOSFirestore.mentorships)
            .whereField("menteeUid", isEqualTo: currentUser.uid)
            .getDocuments()

        myMentorships = snapshot.documents.compactMap { doc in
            try? doc.data(as: BereanMentorRelationship.self)
        }
    }

    // MARK: - Leave Mentor Note

    /// Appends a mentor note to the specified relationship document.
    func leaveMentorNote(
        relationshipId: String,
        content: String,
        targetEntryId: String?
    ) async throws {
        guard AMENFeatureFlags.shared.bereanOSMentorOSEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard let currentUser = Auth.auth().currentUser else {
            throw BereanOSError.unauthorized
        }

        let noteId = UUID().uuidString
        var noteData: [String: Any] = [
            "id": noteId,
            "content": content,
            "authorUid": currentUser.uid,
            "isPinned": false,
            "isActedUpon": false,
            "createdAt": Timestamp(date: Date())
        ]
        if let entry = targetEntryId { noteData["targetEntryId"] = entry }

        try await db
            .document(BereanOSFirestore.mentorship(relationshipId: relationshipId))
            .updateData([
                "mentorNotes": FieldValue.arrayUnion([noteData])
            ])

        // Reflect locally
        if let idx = myMentorships.firstIndex(where: { $0.id == relationshipId }) {
            let note = BereanMentorNote(
                id: noteId,
                content: content,
                targetEntryId: targetEntryId,
                authorUid: currentUser.uid,
                isPinned: false,
                isActedUpon: false,
                createdAt: Date()
            )
            myMentorships[idx].mentorNotes.append(note)
        }
    }

    // MARK: - Assign Mentor Task

    /// Writes a task entry under the mentorship relationship for the mentee.
    func assignMentorTask(
        to menteeUid: String,
        taskTitle: String,
        relationshipId: String
    ) async throws {
        guard AMENFeatureFlags.shared.bereanOSMentorOSEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard Auth.auth().currentUser != nil else {
            throw BereanOSError.unauthorized
        }

        let taskData: [String: Any] = [
            "id": UUID().uuidString,
            "title": taskTitle,
            "assignedTo": menteeUid,
            "status": BereanTaskStatus.notStarted.rawValue,
            "priority": BereanTaskPriority.medium.rawValue,
            "createdAt": Timestamp(date: Date())
        ]

        try await db
            .document(BereanOSFirestore.mentorship(relationshipId: relationshipId))
            .updateData([
                "assignedTasks": FieldValue.arrayUnion([taskData])
            ])
    }

    // MARK: - Update Mentorship Status

    /// Updates the status of a mentorship relationship.
    func updateMentorshipStatus(
        _ status: BereanMentorshipStatus,
        relationshipId: String
    ) async throws {
        guard AMENFeatureFlags.shared.bereanOSMentorOSEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard Auth.auth().currentUser != nil else {
            throw BereanOSError.unauthorized
        }

        try await db
            .document(BereanOSFirestore.mentorship(relationshipId: relationshipId))
            .updateData(["status": status.rawValue])

        if let idx = myMentorships.firstIndex(where: { $0.id == relationshipId }) {
            myMentorships[idx].status = status
        }
    }
}
