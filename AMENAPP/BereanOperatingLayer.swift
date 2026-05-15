import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BereanOperatingLayer: ObservableObject {
    static let shared = BereanOperatingLayer()

    private lazy var db = Firestore.firestore()
    private let groundingService = BereanChurchGroundingService.shared
    private let graphService = SpiritualGraphService.shared

    private init() {}

    func assembleContext(
        churchId: String? = nil,
        eventId: String? = nil,
        mediaId: String? = nil,
        studyTopicIds: [String] = []
    ) async -> BereanOperatingContext? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        let memories = (try? await graphService.exportMemoryPayload()) ?? []
        let sources = await loadApprovedSources(churchId: churchId, eventId: eventId, mediaId: mediaId)
        let confidence = ChurchConfidenceMetadata(
            confidence: sources.isEmpty ? 0.15 : 0.72,
            level: sources.isEmpty ? .low : .high,
            sources: sources,
            note: sources.isEmpty ? "Not confirmed yet" : "Grounded in approved AMEN context sources.",
            updatedAt: Date()
        )

        return BereanOperatingContext(
            userId: uid,
            churchId: churchId,
            eventId: eventId,
            mediaId: mediaId,
            studyTopicIds: studyTopicIds,
            memoryIds: memories.filter { $0.visibility != .privateOnly }.map(\.id),
            preferredResponseMode: "grounded_contextual",
            sources: sources,
            confidence: confidence
        )
    }

    func answerChurchSpecificQuestion(churchId: String, question: String) async throws -> BereanOperatingResponse {
        let grounded = try await groundingService.answerChurchQuestion(churchId: churchId, question: question)
        return BereanOperatingResponse(
            answer: grounded.response,
            attributionLine: grounded.sources.isEmpty ? "Not confirmed yet" : "Based on verified church metadata and approved sources.",
            confidence: grounded.confidence,
            sources: grounded.sources,
            notConfirmedYet: grounded.confidence.level == .low
        )
    }

    private func loadApprovedSources(churchId: String?, eventId: String?, mediaId: String?) async -> [ChurchGroundingSource] {
        var sources: [ChurchGroundingSource] = []

        if let churchId {
            let churchDoc = try? await db.collection("churches").document(churchId).getDocument()
            if let data = churchDoc?.data(), let name = data["name"] as? String {
                sources.append(
                    ChurchGroundingSource(
                        id: "church:\(churchId)",
                        type: .verifiedMetadata,
                        title: name,
                        detail: "Verified church metadata",
                        url: data["website"] as? String,
                        verified: (data["verificationStatus"] as? String) == ChurchVerificationStatus.verified.rawValue,
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
                    )
                )
            }
        }

        if let eventId {
            sources.append(
                ChurchGroundingSource(
                    id: "event:\(eventId)",
                    type: .adminProvided,
                    title: "Church event context",
                    detail: "Admin-provided event metadata",
                    url: nil,
                    verified: true,
                    updatedAt: Date()
                )
            )
        }

        if let mediaId {
            sources.append(
                ChurchGroundingSource(
                    id: "media:\(mediaId)",
                    type: .approvedMedia,
                    title: "Approved church media",
                    detail: "Moderated media context",
                    url: nil,
                    verified: true,
                    updatedAt: Date()
                )
            )
        }

        return sources
    }
}
