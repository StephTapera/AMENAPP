// ContentHeroViewModel.swift
// AMEN App — Community Around Content OS › Dynamic Hero Experience
//
// Drives the MediaHeroView. Owns community data loading, layer selection,
// reflection prompts, and matched scripture verses for a single ContentObject.
//
// All features gated by CommunityOSFlag.heroExperience.

import SwiftUI
import Foundation

// MARK: - ContentHeroViewModel

@MainActor
final class ContentHeroViewModel: ObservableObject {

    // MARK: Published state

    @Published var contentObject: ContentObject
    @Published var communityNode: CommunityNode?
    @Published var dominantColor: Color = .clear
    @Published var secondaryColor: Color = .clear
    @Published var isLoadingCommunity: Bool = true
    @Published var hasJoinedCommunity: Bool = false
    @Published var activeLayer: CommunityLayer = .discussion
    @Published var reflectionPrompts: [String] = []
    @Published var matchedVerses: [String] = []

    // MARK: Init

    init(contentObject: ContentObject) {
        self.contentObject = contentObject
        // Seed the active layer to the first layer appropriate for the content kind.
        self.activeLayer = contentObject.kind.defaultCommunityLayers.first ?? .discussion
    }

    // MARK: Public API

    /// Loads all remote data in parallel: community node, reflection prompts, verse matches.
    func load() async {
        guard CommunityOSFlagService.shared.isEnabled(.heroExperience) else {
            dlog("[ContentHeroViewModel] heroExperience flag is disabled — skipping load.")
            isLoadingCommunity = false
            return
        }

        dlog("[ContentHeroViewModel] load() starting for contentObjectId: \(contentObject.id)")

        async let nodeFetch    = fetchCommunityNode(for: contentObject.id)
        async let promptsFetch = fetchReflectionPrompts(for: contentObject)
        async let versesFetch  = fetchMatchedVerses(for: contentObject)

        let (node, prompts, verses) = await (nodeFetch, promptsFetch, versesFetch)

        communityNode = node
        reflectionPrompts = prompts
        matchedVerses = verses
        isLoadingCommunity = false

        dlog("[ContentHeroViewModel] load() complete — node: \(node?.name ?? "none"), prompts: \(prompts.count), verses: \(verses.count)")
    }

    /// Joins the community node and fires a light haptic on success.
    func joinCommunity() async {
        guard CommunityOSFlagService.shared.isEnabled(.heroExperience) else { return }
        guard communityNode != nil else { return }

        dlog("[ContentHeroViewModel] joinCommunity() requested for node: \(communityNode?.id ?? "nil")")

        // Optimistic UI update.
        hasJoinedCommunity = true

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        // TODO: wire to Cloud Function when community membership CF is deployed.
        dlog("[ContentHeroViewModel] joinCommunity() — membership recorded (pending CF deploy).")
    }

    /// Switches the active community layer with the standard state-change animation.
    func switchLayer(_ layer: CommunityLayer) {
        guard CommunityOSFlagService.shared.isEnabled(.heroExperience) else { return }
        withAnimation(AppAnimation.stateChange) {
            activeLayer = layer
        }
        dlog("[ContentHeroViewModel] layer switched to: \(layer.displayName)")
    }

    // MARK: Computed

    /// The community layers relevant to this content kind.
    var availableLayers: [CommunityLayer] {
        contentObject.kind.defaultCommunityLayers
    }

    /// A formatted summary string for display in the community snapshot strip.
    var communityCountSummary: String {
        let discussions = contentObject.discussionCount.communityFormatted
        let prayers     = contentObject.prayerCount.communityFormatted
        let testimonies = contentObject.testimonyCount.communityFormatted
        return "\(discussions) discussing · \(prayers) praying · \(testimonies) testimonies"
    }

    // MARK: Private loaders
    // These return seed / derived data until the matching Cloud Functions are deployed.
    // Each is isolated so the async-let parallelism above is clean.

    private func fetchCommunityNode(for contentObjectId: String) async -> CommunityNode? {
        // If the content object already carries enough signal to synthesise a node, do so.
        guard contentObject.hasCommunity else {
            dlog("[ContentHeroViewModel] fetchCommunityNode — no community signal yet.")
            return nil
        }
        // Derive a lightweight CommunityNode from the ContentObject's own counts.
        // Replace with a Firestore fetch once communityNodes/{id} documents are deployed.
        return CommunityNode(
            id: "derived-\(contentObjectId)",
            contentObjectId: contentObjectId,
            contentKind: contentObject.kind,
            name: contentObject.title,
            memberCount: contentObject.totalEngagement,
            discussionCount: contentObject.discussionCount,
            prayerCount: contentObject.prayerCount,
            testimonyCount: contentObject.testimonyCount,
            isAutoGenerated: true,
            activeLayers: contentObject.kind.defaultCommunityLayers
        )
    }

    private func fetchReflectionPrompts(for object: ContentObject) async -> [String] {
        // Seed: use layer prompts for the available layers + any theme-derived questions.
        var prompts = object.kind.defaultCommunityLayers.map { $0.prompt }
        if !object.themes.isEmpty {
            let themePrompt = "How do the themes of \(object.themes.prefix(3).joined(separator: ", ")) connect to your faith?"
            prompts.insert(themePrompt, at: 1)
        }
        return Array(prompts.prefix(5))
    }

    private func fetchMatchedVerses(for object: ContentObject) async -> [String] {
        // Return the verse refs already attached to the content object.
        // Future: augment with Berean AI verse-match CF result.
        if !object.linkedVerseRefs.isEmpty {
            return object.linkedVerseRefs
        }
        // Fallback seed verses by kind when none are attached.
        switch object.kind {
        case .song, .sermon:
            return ["Psalm 95:1", "Ephesians 5:19", "Colossians 3:16"]
        case .bibleVerse:
            return [object.rawURL]
        case .prayerRequest:
            return ["Philippians 4:6–7", "1 Thessalonians 5:17"]
        case .testimony:
            return ["Romans 8:28", "Revelation 12:11"]
        default:
            return []
        }
    }
}

// MARK: - Int + communityFormatted

private extension Int {
    /// Formats large integers as abbreviated strings (1 200 → "1.2K", 1 200 000 → "1.2M").
    var communityFormatted: String {
        switch self {
        case 1_000_000...:
            let value = Double(self) / 1_000_000
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))M"
                : String(format: "%.1fM", value)
        case 1_000...:
            let value = Double(self) / 1_000
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))K"
                : String(format: "%.1fK", value)
        default:
            return "\(self)"
        }
    }
}
