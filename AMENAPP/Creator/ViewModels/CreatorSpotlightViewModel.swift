// CreatorSpotlightViewModel.swift
// AMENAPP — Creator Spotlight / Wave 1 → LIVE
//
// Renders the public Creator Spotlight over the EXISTING creator profile data
// (CreatorHubService) — does NOT fork a parallel profile model and does NOT
// fabricate any data. Media that moderation hasn't approved is treated as
// pending (fail-closed). No trust score, no vanity counters.

import Foundation
import SwiftUI

@MainActor
final class CreatorSpotlightViewModel: ObservableObject {

    @Published var spotlight: CreatorSpotlight?
    @Published var profile: CreatorHubProfile?
    @Published var contents: [CreatorContent] = []
    @Published var isLoading = false
    @Published var error: String?

    private let creatorId: String

    init(creatorId: String) {
        self.creatorId = creatorId
    }

    var displayName: String { profile?.displayName ?? "Creator" }

    func load() async {
        guard AMENFeatureFlags.shared.creatorSpotlightEnabled else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await CreatorHubService.shared.assembleProfile(creatorId: creatorId)
            self.profile = payload.profile
            self.contents = payload.firstPages.teachings.map { Self.content(from: $0, creatorId: creatorId) }
            self.spotlight = Self.spotlight(from: payload, creatorId: creatorId, contents: contents)
            self.error = nil
        } catch {
            if spotlight == nil {
                self.error = "We couldn’t load this page. Pull to try again."
            }
        }
    }

    // MARK: - Mapping (existing hub data → Spotlight contracts)

    private static func content(from t: CreatorHubTeaching, creatorId: String) -> CreatorContent {
        let format: ContentFormat = t.video != nil ? .video : (t.audio != nil ? .audio : .text)

        // Fail-closed: if a media ref exists but moderation hasn't approved it,
        // the content is pending (never shown as approved).
        let mediaApproved: Bool = {
            if let v = t.video { return v.isServable }
            if let a = t.audio { return a.isServable }
            return true // text-only teaching: no unapproved media to gate
        }()

        var capabilities: [ContentCapability] = [
            ContentCapability(kind: .worksWithBerean, available: true)
        ]
        if t.audio != nil { capabilities.append(ContentCapability(kind: .audio, available: true)) }
        if t.transcriptRef != nil { capabilities.append(ContentCapability(kind: .transcripts, available: true)) }
        if !t.outline.isEmpty || (t.notes?.isEmpty == false) {
            capabilities.append(ContentCapability(kind: .studyGuide, available: true))
        }

        let metadata = OrientingMetadata(
            format: [format],
            approximateLengthMinutes: t.durationSec > 0 ? Int(t.durationSec / 60) : nil,
            scriptureReferences: t.scriptureRefs,
            liturgicalSeason: nil,
            audienceDescription: nil,
            whereToStart: nil,
            seriesName: t.series,
            totalEpisodes: nil
        )

        let disclosure = PrivacyDisclosure(
            contentId: t.id,
            creatorId: creatorId,
            touchedFields: [
                PrivacyFieldDisclosure(
                    fieldName: "viewedContentId",
                    description: "Which teaching you opened",
                    zone: .functional,
                    purposeDescription: "So you can resume where you left off"
                )
            ],
            neverTouchedList: ["contacts", "location", "microphone", "health"],
            nsmPrivacyTracking: false,
            generatedAt: 0
        )

        return CreatorContent(
            id: t.id,
            creatorId: creatorId,
            title: t.title,
            description: t.notes,
            format: format,
            thumbnailUrl: nil,            // hub stores Storage paths, not URLs — never fabricate a URL
            previewUrl: nil,
            durationSeconds: t.durationSec > 0 ? Int(t.durationSec) : nil,
            scriptureReferences: t.scriptureRefs,
            seriesId: t.series,
            seriesPosition: nil,
            publishedAt: nil,
            orientingMetadata: metadata,
            capabilities: capabilities,
            appropriatenessSignal: .allAges,
            moderationStatus: mediaApproved ? .approved : .pending,
            privacyDisclosure: disclosure
        )
    }

    private static func spotlight(
        from payload: CreatorHubProfilePayload,
        creatorId: String,
        contents: [CreatorContent]
    ) -> CreatorSpotlight {
        let approved = contents.filter { $0.moderationStatus == .approved }

        // Verification badges from the existing factual `verified` flag + role labels.
        // No trust tier, no rank — only "what is verified".
        var badges: [VerificationBadge] = []
        if payload.profile.verified {
            badges.append(VerificationBadge(kind: .identity, verifiedAt: 0, verifiedBy: "amen_team", displayLabel: VerificationBadgeKind.identity.displayLabel))
        }
        for role in payload.profile.roleLabels.map({ $0.lowercased() }) {
            if role.contains("minister") || role.contains("pastor") {
                badges.append(VerificationBadge(kind: .minister, verifiedAt: 0, verifiedBy: "amen_team", displayLabel: VerificationBadgeKind.minister.displayLabel))
            } else if role.contains("teacher") || role.contains("educator") {
                badges.append(VerificationBadge(kind: .educator, verifiedAt: 0, verifiedBy: "amen_team", displayLabel: VerificationBadgeKind.educator.displayLabel))
            }
        }

        let seriesIds = Array(Set(approved.compactMap { $0.seriesId })).sorted()

        // Now / New from real upcoming or live events.
        let nowItems: [NowAndNewItem] = payload.firstPages.events
            .filter { $0.status == .scheduled || $0.status == .live }
            .prefix(5)
            .map { e in
                NowAndNewItem(
                    id: e.id,
                    creatorId: creatorId,
                    kind: e.status == .live ? .liveSession : .upcomingEvent,
                    headline: e.title,
                    description: nil,
                    scheduledAt: e.startsAt.timeIntervalSince1970,
                    liveNow: e.status == .live,
                    primaryActionLabel: e.registrationUrl != nil ? "Register" : nil,
                    primaryActionDeepLink: e.registrationUrl
                )
            }

        var tabs: [ContentTab] = [.overview]
        if !approved.isEmpty { tabs.append(.teachings) }
        if !seriesIds.isEmpty { tabs.append(.series) }
        if !payload.firstPages.events.isEmpty { tabs.append(.events) }
        if !payload.firstPages.resources.isEmpty { tabs.append(.resources) }
        tabs.append(.about)

        return CreatorSpotlight(
            creatorId: creatorId,
            missionStatement: nil,                       // no mission field in the profile model — left honest
            featuredContentId: approved.first?.id,
            verificationBadges: badges,
            activeSeriesIds: seriesIds,
            contentTabOrder: tabs,
            reasonedConnections: [],                     // reasoned-connections engine is a later wave
            nowAndNew: nowItems,
            enabled: true
        )
    }
}
