import Foundation
import Testing
@testable import AMENAPP

struct AmenSmartAttachmentTests {
    @Test("AmenSmartAttachment codable round trip")
    func codableRoundTrip() throws {
        let original = AmenSmartAttachment(
            id: "yt_123",
            postId: "post_1",
            provider: .youtube,
            type: .video,
            providerId: "123",
            title: "Sunday Sermon",
            subtitle: "YouTube",
            creatorName: "Grace Church",
            description: "A full sermon message",
            artworkUrl: "https://i.ytimg.com/example.jpg",
            canonicalUrl: "https://youtube.com/watch?v=123",
            durationMs: 4200000,
            previewUrl: nil,
            attributionText: "YouTube",
            sourceLogoRequired: true,
            playbackPolicy: .externalOnly,
            safetyStatus: .approved,
            smartActions: [.watch, .addToChurchNotes],
            soundtrackEnabled: false,
            createdAt: Date(timeIntervalSince1970: 123),
            updatedAt: Date(timeIntervalSince1970: 456)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AmenSmartAttachment.self, from: data)
        #expect(decoded == original)
    }

    @Test("Sermon video suggests Church Notes")
    func sermonSuggestsChurchNotes() {
        let attachment = AmenSmartAttachment(
            id: "1", postId: nil, provider: .youtube, type: .video, providerId: nil,
            title: "Sunday sermon", subtitle: nil, creatorName: nil, description: "Bible study",
            artworkUrl: nil, canonicalUrl: "https://youtube.com/watch?v=1", durationMs: nil, previewUrl: nil,
            attributionText: "YouTube", sourceLogoRequired: true, playbackPolicy: .externalOnly,
            safetyStatus: .approved, smartActions: [.watch], soundtrackEnabled: false, createdAt: nil, updatedAt: nil
        )
        let decision = AmenSmartAttachmentActionEngine.decide(attachment: attachment, postText: "great teaching", surface: .feed)
        #expect(decision.actions.contains(.addToChurchNotes))
    }
}
