//
//  ProfileDiscoveryRouter.swift
//  AMENAPP
//
//  Translates UserProfileIdentity changes into routing signals consumed by
//  the feed, Berean, and church-discovery layers.
//
//  Call ProfileDiscoveryRouter.shared.start() on sign-in alongside
//  ProfileIdentityService.shared.startListening().
//  Call stop() on sign-out.
//
//  Other services read the @Published signals — no direct coupling needed.
//

import Foundation
import Combine

// MARK: - Feed Tuning Signal

/// Compact signal emitted whenever relevant identity fields change.
/// The feed ranking layer can read this to adjust content weights.
struct ProfileFeedSignal {
    /// Interest tags that should be amplified in the feed (from interests + openToSignals).
    let amplifiedTags: [String]
    /// Topic tags the user claims to speak on — surfaces similar creators.
    let topicTags: [String]
    /// Persona-driven content weights (keys match feature identifiers in BereanSpiritualModels).
    let emphasizedFeatures: [String]
    /// True when the user is in a leadership persona — boosts sermon/teaching content.
    let isLeadership: Bool
    /// True when the user is exploring/new — filters out hard theological debates.
    let isEarlyFaith: Bool
}

// MARK: - Berean Hint Signal

/// Injected into Berean's system context on each new conversation.
/// BereanAPIClient reads this when assembling the request payload.
struct BereanIdentityHint {
    /// Sentence injected into the Berean system prompt for personalization.
    let systemHint: String
    /// Short label surfaced in BereanContextResolver for dynamic chips.
    let faithStageLabel: String?
    /// Persona raw value for chip/prompt routing.
    let personaRaw: String?
    /// Whether to surface ask-me-about prompts in the Berean landing surface.
    let hasAskMeAbout: Bool
}

// MARK: - Church Discovery Signal

struct ChurchDiscoverySignal {
    /// If the user has named a church, boost results near that name in FindChurchView.
    let affiliatedChurchName: String?
    /// The matched Firestore church document ID, if available.
    let affiliatedChurchId: String?
    /// Denomination preference for filtering/sorting church discovery results.
    let denominationRaw: String?
    /// Coarse location for proximity search initialization.
    let cityRegion: String?
}

// MARK: - ProfileDiscoveryRouter

@MainActor
final class ProfileDiscoveryRouter: ObservableObject {
    static let shared = ProfileDiscoveryRouter()

    @Published private(set) var feedSignal:    ProfileFeedSignal    = .empty
    @Published private(set) var bereanHint:    BereanIdentityHint   = .empty
    @Published private(set) var churchSignal:  ChurchDiscoverySignal = .empty

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard cancellables.isEmpty else { return }
        dlog("[ProfileDiscovery] start — subscribing to identity changes")

        ProfileIdentityService.shared.$identity
            .receive(on: RunLoop.main)
            .sink { [weak self] identity in
                self?.route(identity: identity)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        feedSignal   = .empty
        bereanHint   = .empty
        churchSignal = .empty
        dlog("[ProfileDiscovery] stop — signals cleared")
    }

    // MARK: - Routing

    private func route(identity: UserProfileIdentity) {
        feedSignal   = buildFeedSignal(identity)
        bereanHint   = buildBereanHint(identity)
        churchSignal = buildChurchSignal(identity)
        dlog("[ProfileDiscovery] routed persona=\(identity.persona?.rawValue ?? "nil") " +
             "church=\(identity.churchAffiliationName ?? "nil")")
    }

    // MARK: - Feed Signal Builder

    private func buildFeedSignal(_ id: UserProfileIdentity) -> ProfileFeedSignal {
        // Collect amplified tags from openTo signals
        let openToTags = id.openToSignals.map(\.discoveryTag)

        // Leadership personas get sermon/teaching amplification
        let isLeadership = [UserPersona.pastor, .churchLeader, .worshipLeader]
            .contains(id.persona)

        // Early faith personas see gentler, foundational content
        let isEarlyFaith = id.faithJourneyStage == .exploring
            || id.faithJourneyStage == .newBeliever

        return ProfileFeedSignal(
            amplifiedTags:      openToTags,
            topicTags:          [],   // topics live in UserProfileData.profileTopics — read at feed query time
            emphasizedFeatures: id.persona?.emphasizedFeatures ?? [],
            isLeadership:       isLeadership,
            isEarlyFaith:       isEarlyFaith
        )
    }

    // MARK: - Berean Hint Builder

    private func buildBereanHint(_ id: UserProfileIdentity) -> BereanIdentityHint {
        var parts: [String] = []

        if let persona = id.persona {
            parts.append("The user identifies as a \(persona.displayName).")
        }

        if let stage = id.faithJourneyStage {
            parts.append(stage.bereanSuggestionHint)
        }

        if let denom = id.denomination, denom != .preferNotToSay {
            parts.append("They come from a \(denom.displayName) tradition.")
        }

        if !id.openToSignalIds.isEmpty {
            let labels = id.openToSignals.map(\.label).joined(separator: ", ")
            parts.append("They are open to: \(labels).")
        }

        if !id.askMeAbout.isEmpty {
            let topics = id.askMeAbout.map(\.topic).joined(separator: ", ")
            parts.append("They consider themselves knowledgeable about: \(topics).")
        }

        return BereanIdentityHint(
            systemHint:      parts.joined(separator: " "),
            faithStageLabel: id.faithJourneyStage?.displayName,
            personaRaw:      id.persona?.rawValue,
            hasAskMeAbout:   !id.askMeAbout.isEmpty
        )
    }

    // MARK: - Church Discovery Signal Builder

    private func buildChurchSignal(_ id: UserProfileIdentity) -> ChurchDiscoverySignal {
        ChurchDiscoverySignal(
            affiliatedChurchName: id.churchAffiliationName,
            affiliatedChurchId:   id.churchAffiliationId,
            denominationRaw:      id.denomination?.rawValue,
            cityRegion:           id.cityRegion
        )
    }
}

// MARK: - Empty States

private extension ProfileFeedSignal {
    static let empty = ProfileFeedSignal(
        amplifiedTags:      [],
        topicTags:          [],
        emphasizedFeatures: [],
        isLeadership:       false,
        isEarlyFaith:       false
    )
}

private extension BereanIdentityHint {
    static let empty = BereanIdentityHint(
        systemHint:      "",
        faithStageLabel: nil,
        personaRaw:      nil,
        hasAskMeAbout:   false
    )
}

private extension ChurchDiscoverySignal {
    static let empty = ChurchDiscoverySignal(
        affiliatedChurchName: nil,
        affiliatedChurchId:   nil,
        denominationRaw:      nil,
        cityRegion:           nil
    )
}
