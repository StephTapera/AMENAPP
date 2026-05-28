import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - MeetingService

@MainActor
final class MeetingService: ObservableObject {
    static let shared = MeetingService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Create

    func createMeeting(
        groupId: String,
        title: String,
        startAt: Date,
        locationLat: Double? = nil,
        locationLng: Double? = nil,
        locationName: String? = nil,
        studyPassage: String? = nil,
        agendaBlocks: [AgendaBlock] = []
    ) async throws -> Meeting {
        guard let uid = Auth.auth().currentUser?.uid else { throw MeetingError.notAuthenticated }
        let ref = db.collection("meetings").document()
        var meeting = Meeting(groupId: groupId, hostUids: [uid], title: title, startAt: startAt,
                              locationLat: locationLat, locationLng: locationLng,
                              locationName: locationName, studyPassage: studyPassage,
                              agendaBlocks: agendaBlocks, status: .scheduled, rsvps: [])
        try ref.setData(from: meeting)
        meeting.id = ref.documentID
        return meeting
    }

    // MARK: - Fetch / Listen

    func fetchMeetingsForGroup(_ groupId: String) async throws -> [Meeting] {
        let snap = try await db.collection("meetings")
            .whereField("groupId", isEqualTo: groupId)
            .order(by: "startAt")
            .limit(to: 50)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Meeting.self) }
    }

    func listenMeetingsForGroup(_ groupId: String, handler: @escaping ([Meeting]) -> Void) -> ListenerRegistration {
        db.collection("meetings")
            .whereField("groupId", isEqualTo: groupId)
            .order(by: "startAt")
            .limit(to: 50)
            .addSnapshotListener { snap, _ in
                handler(snap?.documents.compactMap { try? $0.data(as: Meeting.self) } ?? [])
            }
    }

    // MARK: - RSVP

    func rsvp(meetingId: String, status: MeetingRSVPStatus) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw MeetingError.notAuthenticated }
        let ref = db.collection("meetings").document(meetingId)
        let doc = try await ref.getDocument()
        guard var meeting = try? doc.data(as: Meeting.self) else { throw MeetingError.meetingNotFound }
        meeting.rsvps.removeAll { $0.uid == uid }
        meeting.rsvps.append(MeetingRSVP(uid: uid, status: status, updatedAt: Date()))
        let encoded = try meeting.rsvps.map { try Firestore.Encoder().encode($0) }
        try await ref.updateData(["rsvps": encoded])
    }

    // MARK: - Status Transitions

    func goLive(meetingId: String) async throws {
        try await db.collection("meetings").document(meetingId)
            .updateData(["status": MeetingStatus.live.rawValue])
    }

    func endMeeting(meetingId: String) async throws {
        try await db.collection("meetings").document(meetingId)
            .updateData(["status": MeetingStatus.ended.rawValue])
    }

    // MARK: - Agenda

    func updateAgenda(_ blocks: [AgendaBlock], meetingId: String) async throws {
        let encoded = try blocks.map { try Firestore.Encoder().encode($0) }
        try await db.collection("meetings").document(meetingId)
            .updateData(["agendaBlocks": encoded])
    }
}

enum MeetingError: LocalizedError {
    case notAuthenticated, meetingNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please sign in to continue."
        case .meetingNotFound: return "Meeting not found."
        }
    }
}
