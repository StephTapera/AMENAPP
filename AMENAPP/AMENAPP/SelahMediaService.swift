import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Selah Media Service
// Handles all Firebase I/O for the Selah Media OS feature set.

@MainActor
final class SelahMediaService: ObservableObject {
    static let shared = SelahMediaService()

    // MARK: - Published State

    @Published var mediaFeed: [SelahMediaItem] = []
    @Published var myMedia: [SelahMediaItem] = []
    @Published var memories: [SelahMediaMemory] = []
    @Published var continuations: [SelahMediaContinuation] = []
    @Published var trustCircles: [SelahTrustCircle] = []
    @Published var creatorProjects: [SelahCreatorProject] = []
    @Published var isLoadingFeed = false
    @Published var isLoadingMemories = false
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0

    // MARK: - Private

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private var feedListener: ListenerRegistration?
    private var myMediaListener: ListenerRegistration?
    private var memoriesListener: ListenerRegistration?
    private var continuationsListener: ListenerRegistration?
    private var trustCirclesListener: ListenerRegistration?

    private var userId: String { Auth.auth().currentUser?.uid ?? "" }

    private init() {}

    deinit {
        stopListening()
    }

    func startListening() {
        guard !userId.isEmpty else { return }
        startListeningFeed()
        startListeningMyMedia()
        startListeningMemories()
        startListeningContinuations()
        startListeningTrustCircles()
    }

    func stopListening() {
        feedListener?.remove()
        myMediaListener?.remove()
        memoriesListener?.remove()
        continuationsListener?.remove()
        trustCirclesListener?.remove()
    }

    // MARK: - Feed Listeners

    private func startListeningFeed() {
        feedListener?.remove()
        feedListener = db.collection("selah_media")
            .whereField("trustCircleTier", in: ["community", "public"])
            .order(by: "createdAt", descending: true)
            .limit(to: 40)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self?.mediaFeed = docs.compactMap { try? $0.data(as: SelahMediaItem.self) }
            }
    }

    private func startListeningMyMedia() {
        guard !userId.isEmpty else { return }
        myMediaListener?.remove()
        myMediaListener = db.collection("selah_media")
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self?.myMedia = docs.compactMap { try? $0.data(as: SelahMediaItem.self) }
            }
    }

    private func startListeningMemories() {
        guard !userId.isEmpty else { return }
        memoriesListener?.remove()
        memoriesListener = db.collection("users").document(userId)
            .collection("selah_memories")
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self?.memories = docs.compactMap { try? $0.data(as: SelahMediaMemory.self) }
            }
    }

    private func startListeningContinuations() {
        guard !userId.isEmpty else { return }
        continuationsListener?.remove()
        continuationsListener = db.collection("users").document(userId)
            .collection("selah_continuations")
            .whereField("completed", isEqualTo: false)
            .order(by: "relevanceScore", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self?.continuations = docs.compactMap { try? $0.data(as: SelahMediaContinuation.self) }
            }
    }

    private func startListeningTrustCircles() {
        guard !userId.isEmpty else { return }
        trustCirclesListener?.remove()
        trustCirclesListener = db.collection("users").document(userId)
            .collection("selah_trust_circles")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self?.trustCircles = docs.compactMap { try? $0.data(as: SelahTrustCircle.self) }
            }
    }

    // MARK: - Media Upload

    /// Uploads image data to Firebase Storage, then creates a Firestore document.
    func uploadPhoto(
        imageData: Data,
        caption: String,
        meaningTags: [SelahMeaningTag],
        scriptureRef: String?,
        tier: SelahTrustCircleTier,
        circleId: String?,
        commentRoomMode: SelahCommentRoomMode
    ) async throws -> SelahMediaItem {
        guard !userId.isEmpty else { throw SelahMediaError.notAuthenticated }

        isUploading = true
        uploadProgress = 0
        defer { isUploading = false }

        // Upload to Storage
        let path = "selah_media/\(userId)/\(UUID().uuidString).jpg"
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = ref.putData(imageData, metadata: metadata) { [weak self] _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
            }

            uploadTask.observe(.progress) { [weak self] snapshot in
                Task { @MainActor in
                    if let progress = snapshot.progress {
                        self?.uploadProgress = progress.fractionCompleted
                    }
                }
            }

            uploadTask.observe(.success) { [weak self] _ in
                guard let self else { return }
                ref.downloadURL { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let downloadURL = url else {
                        continuation.resume(throwing: SelahMediaError.uploadFailed)
                        return
                    }

                    var item = SelahMediaItem(
                        authorId: self.userId,
                        type: .photo,
                        mediaURL: downloadURL.absoluteString,
                        caption: caption,
                        meaningTags: meaningTags,
                        scriptureRef: scriptureRef,
                        trustCircleTier: tier,
                        trustCircleId: circleId,
                        commentRoomEnabled: commentRoomMode != .closed,
                        commentRoomMode: commentRoomMode
                    )

                    Task { @MainActor in
                        do {
                            let docRef = try self.db.collection("selah_media").addDocument(from: item)
                            item.id = docRef.documentID
                            continuation.resume(returning: item)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }

            uploadTask.observe(.failure) { _ in
                continuation.resume(throwing: SelahMediaError.uploadFailed)
            }
        }
    }

    // MARK: - Memories

    @discardableResult
    func saveMemory(_ memory: SelahMediaMemory) async throws -> String {
        guard !userId.isEmpty else { throw SelahMediaError.notAuthenticated }
        var m = memory
        m.userId = userId
        let ref = try db.collection("users").document(userId)
            .collection("selah_memories")
            .addDocument(from: m)
        return ref.documentID
    }

    func deleteMemory(id: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection("users").document(userId)
            .collection("selah_memories")
            .document(id)
            .delete()
    }

    // MARK: - Continuations

    @discardableResult
    func saveContinuation(_ continuation: SelahMediaContinuation) async throws -> String {
        guard !userId.isEmpty else { throw SelahMediaError.notAuthenticated }
        var c = continuation
        c.userId = userId
        let ref = try db.collection("users").document(userId)
            .collection("selah_continuations")
            .addDocument(from: c)
        return ref.documentID
    }

    func completeContinuation(id: String, noteText: String?, scriptureRef: String?) async throws {
        guard !userId.isEmpty else { return }
        let uid = userId
        let contRef = db.collection("users").document(uid)
            .collection("selah_continuations")
            .document(id)
        let outcomeRef = db.collection("users").document(uid)
            .collection("selah_outcomes")
            .document()

        let snap = try await contRef.getDocument()
        guard let cont = try? snap.data(as: SelahMediaContinuation.self) else { return }

        let batch = db.batch()
        batch.updateData(["completed": true, "completedAt": Timestamp(date: Date())], forDocument: contRef)
        let outcome = SelahOutcome(
            userId: uid,
            continuationId: id,
            action: cont.action,
            noteText: noteText,
            scriptureRef: scriptureRef,
            createdAt: Date()
        )
        if let data = try? Firestore.Encoder().encode(outcome) {
            batch.setData(data, forDocument: outcomeRef)
        }
        try await batch.commit()
    }

    // MARK: - Trust Circles

    @discardableResult
    func createTrustCircle(name: String, memberIds: [String], emoji: String) async throws -> String {
        guard !userId.isEmpty else { throw SelahMediaError.notAuthenticated }
        let circle = SelahTrustCircle(
            ownerId: userId,
            name: name,
            memberIds: [userId] + memberIds,
            emoji: emoji
        )
        let ref = try db.collection("users").document(userId)
            .collection("selah_trust_circles")
            .addDocument(from: circle)
        return ref.documentID
    }

    func addMemberToCircle(circleId: String, memberId: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection("users").document(userId)
            .collection("selah_trust_circles")
            .document(circleId)
            .updateData(["memberIds": FieldValue.arrayUnion([memberId])])
    }

    // MARK: - Comment Rooms

    func fetchCommentRoom(for itemId: String) async throws -> [SelahCommentRoomMessage] {
        let snap = try await db.collection("selah_media")
            .document(itemId)
            .collection("comment_room")
            .order(by: "createdAt", descending: false)
            .limit(to: 50)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: SelahCommentRoomMessage.self) }
    }

    func addCommentRoomMessage(
        to itemId: String,
        text: String,
        scriptureRef: String? = nil
    ) async throws {
        guard !userId.isEmpty else { throw SelahMediaError.notAuthenticated }
        let user = Auth.auth().currentUser
        var message = SelahCommentRoomMessage(
            authorId: userId,
            authorDisplayName: user?.displayName ?? "Anonymous",
            text: text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500).description,
            scriptureRef: scriptureRef,
            createdAt: Date()
        )
        try db.collection("selah_media")
            .document(itemId)
            .collection("comment_room")
            .addDocument(from: message)
    }

    // MARK: - Reactions

    func toggleLike(itemId: String) async throws {
        guard !userId.isEmpty else { return }
        let likeRef = db.collection("selah_media").document(itemId)
            .collection("likes").document(userId)
        let snap = try await likeRef.getDocument()
        let batch = db.batch()
        let itemRef = db.collection("selah_media").document(itemId)
        if snap.exists {
            batch.deleteDocument(likeRef)
            batch.updateData(["likeCount": FieldValue.increment(Int64(-1))], forDocument: itemRef)
        } else {
            batch.setData(["userId": userId, "createdAt": Timestamp(date: Date())], forDocument: likeRef)
            batch.updateData(["likeCount": FieldValue.increment(Int64(1))], forDocument: itemRef)
        }
        try await batch.commit()
    }

    func saveMedia(itemId: String) async throws {
        guard !userId.isEmpty else { return }
        let saveRef = db.collection("users").document(userId)
            .collection("selah_saved").document(itemId)
        let itemRef = db.collection("selah_media").document(itemId)
        let batch = db.batch()
        batch.setData(["itemId": itemId, "savedAt": Timestamp(date: Date())], forDocument: saveRef)
        batch.updateData(["saveCount": FieldValue.increment(Int64(1))], forDocument: itemRef)
        try await batch.commit()
    }

    // MARK: - Creator Projects

    @discardableResult
    func createProject(title: String, description: String, meaningTags: [SelahMeaningTag]) async throws -> String {
        guard !userId.isEmpty else { throw SelahMediaError.notAuthenticated }
        let project = SelahCreatorProject(
            authorId: userId,
            title: title,
            description: description,
            meaningTags: meaningTags,
            status: .draft
        )
        let ref = try db.collection("users").document(userId)
            .collection("selah_creator_projects")
            .addDocument(from: project)
        return ref.documentID
    }

    func publishProject(id: String) async throws {
        guard !userId.isEmpty else { return }
        try await db.collection("users").document(userId)
            .collection("selah_creator_projects")
            .document(id)
            .updateData([
                "status": SelahCreatorProjectStatus.published.rawValue,
                "publishedAt": Timestamp(date: Date())
            ])
    }

    // MARK: - Ask Berean about Media

    func askBereanAboutMedia(
        item: SelahMediaItem,
        question: String
    ) -> AsyncThrowingStream<String, Error> {
        let context = """
        User is looking at a Selah media moment:
        Caption: \(item.caption.prefix(300))
        Scripture: \(item.scriptureRef ?? "none")
        Themes: \(item.meaningTags.map { $0.label }.joined(separator: ", "))

        User's question: \(question)
        """
        return ClaudeService.shared.sendMessage(
            context,
            maxTokens: 800,
            temperature: 0.6,
            mode: .shepherd
        )
    }

    // MARK: - Error

    enum SelahMediaError: LocalizedError {
        case notAuthenticated
        case uploadFailed
        case itemNotFound

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Sign in to use Selah Media."
            case .uploadFailed:     return "Media upload failed. Please try again."
            case .itemNotFound:     return "Media item not found."
            }
        }
    }
}
