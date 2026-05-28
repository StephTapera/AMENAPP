import Foundation

// MARK: - Context Decision

struct AmenContextDecision: Equatable {
    let contentCategory: AmenSmartContentCategory
    let userIntent: AmenSmartUserIntent
    let primaryAction: AmenSmartAttachmentAction?
    let secondaryActions: [AmenSmartAttachmentAction]
    let suggestedDestinations: [AmenSmartMemoryDestination]
    let memoryDestination: AmenSmartMemoryDestination
    let smartLabel: String
    let confidence: Double
    let reasonCodes: [String]
    let safetyTreatment: AmenAttachmentSafetyStatus
}

// MARK: - AmenContextEngine

/// Analyzes a smart attachment + post context and produces a ranked context decision
/// used by AmenSmartObject and AmenObjectHubView to route actions and labels.
enum AmenContextEngine {
    static func analyze(
        attachment: AmenSmartAttachment,
        postText: String,
        surface: AmenSmartAttachmentSurface
    ) -> AmenContextDecision {
        let text = "\(attachment.title) \(attachment.description ?? "") \(postText)".lowercased()

        if attachment.safetyStatus == .blocked {
            return AmenContextDecision(
                contentCategory: .general,
                userIntent: .unknown,
                primaryAction: nil,
                secondaryActions: [],
                suggestedDestinations: [],
                memoryDestination: .none,
                smartLabel: "Restricted",
                confidence: 1.0,
                reasonCodes: ["safety_blocked"],
                safetyTreatment: .blocked
            )
        }

        if attachment.safetyStatus == .limited {
            return AmenContextDecision(
                contentCategory: .general,
                userIntent: .unknown,
                primaryAction: .open,
                secondaryActions: [.report],
                suggestedDestinations: [],
                memoryDestination: .none,
                smartLabel: "Limited Preview",
                confidence: 1.0,
                reasonCodes: ["safety_limited"],
                safetyTreatment: .limited
            )
        }

        // Detect content category from signals
        let (category, categoryReasons) = detectCategory(attachment: attachment, text: text)
        let (intent, intentReasons) = detectIntent(attachment: attachment, category: category)
        let (destinations, destinationReasons) = suggestDestinations(category: category, intent: intent, attachment: attachment)
        let primaryMemory = destinations.first ?? .none

        let primaryAction = primaryActionFor(intent: intent, attachment: attachment)
        let secondary = secondaryActionsFor(
            category: category,
            attachment: attachment,
            surface: surface,
            primary: primaryAction
        )

        let allReasons = categoryReasons + intentReasons + destinationReasons
        let confidence = min(1.0, Double(allReasons.count) * 0.25 + 0.25)

        return AmenContextDecision(
            contentCategory: category,
            userIntent: intent,
            primaryAction: primaryAction,
            secondaryActions: secondary,
            suggestedDestinations: destinations,
            memoryDestination: primaryMemory,
            smartLabel: labelFor(category: category, intent: intent, attachment: attachment),
            confidence: confidence,
            reasonCodes: allReasons,
            safetyTreatment: attachment.safetyStatus
        )
    }

    // MARK: - Category Detection

    private static let worshipSignals = ["worship", "praise", "hymn", "anthem", "holy", "glory", "hallelujah"]
    private static let sermonSignals = ["sermon", "message", "preaching", "teaching", "homily"]
    private static let devotionalSignals = ["devotional", "quiet time", "morning prayer", "daily bread", "reflection"]
    private static let prayerSignals = ["prayer", "intercession", "blessing", "invocation"]
    private static let bibleStudySignals = ["bible study", "scripture", "verse", "exegesis", "commentary", "devotion"]
    private static let testimonySignals = ["testimony", "testimony", "witness", "what god did", "miracle", "transformation"]

    private static func detectCategory(
        attachment: AmenSmartAttachment,
        text: String
    ) -> (AmenSmartContentCategory, [String]) {
        var reasons: [String] = []

        if attachment.type == .song {
            if worshipSignals.contains(where: text.contains) {
                reasons.append("worship_signal")
                return (.worship, reasons)
            }
            reasons.append("music_type")
            return (.music, reasons)
        }

        if attachment.type == .video || attachment.provider == .youtube {
            if sermonSignals.contains(where: text.contains) {
                reasons.append("sermon_signal")
                return (.sermon, reasons)
            }
            if bibleStudySignals.contains(where: text.contains) {
                reasons.append("bible_study_signal")
                return (.educational, reasons)
            }
            if worshipSignals.contains(where: text.contains) {
                reasons.append("worship_video_signal")
                return (.worship, reasons)
            }
            if testimonySignals.contains(where: text.contains) {
                reasons.append("testimony_signal")
                return (.testimony, reasons)
            }
            reasons.append("video_type")
            return (.entertainment, reasons)
        }

        if attachment.type == .podcast {
            if devotionalSignals.contains(where: text.contains) || bibleStudySignals.contains(where: text.contains) {
                reasons.append("devotional_podcast_signal")
                return (.devotional, reasons)
            }
            reasons.append("podcast_type")
            return (.podcast, reasons)
        }

        if attachment.type == .article {
            if bibleStudySignals.contains(where: text.contains) || sermonSignals.contains(where: text.contains) {
                reasons.append("theological_article_signal")
                return (.educational, reasons)
            }
            reasons.append("article_type")
            return (.article, reasons)
        }

        if prayerSignals.contains(where: text.contains) {
            reasons.append("prayer_text_signal")
            return (.prayer, reasons)
        }

        if devotionalSignals.contains(where: text.contains) {
            reasons.append("devotional_text_signal")
            return (.devotional, reasons)
        }

        reasons.append("fallback_general")
        return (.general, reasons)
    }

    // MARK: - Intent Detection

    private static func detectIntent(
        attachment: AmenSmartAttachment,
        category: AmenSmartContentCategory
    ) -> (AmenSmartUserIntent, [String]) {
        switch attachment.type {
        case .song, .album, .playlist, .artist:
            if category == .worship || category == .prayer {
                return (.pray, ["song_worship"])
            }
            return (.listen, ["song_intent"])
        case .video, .reel, .short, .channel:
            if category == .sermon || category == .educational {
                return (.watch, ["educational_video"])
            }
            return (.watch, ["video_intent"])
        case .podcast, .episode, .rssFeed:
            return (.listen, ["podcast_intent"])
        case .article, .scripture:
            return (.read, ["article_intent"])
        case .sermon:
            return (.watch, ["sermon_intent"])
        case .event, .donation:
            return (.read, ["event_intent"])
        case .genericLink, .post, .profile:
            return (.read, ["generic_link"])
        }
    }

    // MARK: - Destination Suggestions

    private static func suggestDestinations(
        category: AmenSmartContentCategory,
        intent: AmenSmartUserIntent,
        attachment: AmenSmartAttachment
    ) -> ([AmenSmartMemoryDestination], [String]) {
        var destinations: [AmenSmartMemoryDestination] = []
        var reasons: [String] = []

        switch category {
        case .worship, .prayer:
            destinations.append(.selah)
            reasons.append("dest_worship_selah")
        case .sermon, .educational, .devotional:
            destinations.append(.churchNotes)
            reasons.append("dest_sermon_notes")
        case .scripture:
            destinations = [.churchNotes, .selah]
            reasons.append("dest_scripture_both")
        case .music:
            if intent == .pray || intent == .reflect {
                destinations.append(.selah)
                reasons.append("dest_reflective_music")
            } else {
                destinations.append(.savedForLater)
                reasons.append("dest_music_save")
            }
        case .podcast, .article:
            destinations.append(.savedForLater)
            reasons.append("dest_longform_save")
        case .testimony:
            destinations.append(.savedForLater)
            reasons.append("dest_testimony_save")
        case .entertainment, .news, .general:
            destinations.append(.savedForLater)
            reasons.append("dest_general_save")
        }

        return (destinations, reasons)
    }

    // MARK: - Action Mapping

    private static func primaryActionFor(
        intent: AmenSmartUserIntent,
        attachment: AmenSmartAttachment
    ) -> AmenSmartAttachmentAction? {
        switch intent {
        case .listen: return .listen
        case .watch: return .watch
        case .read, .reflect, .unknown: return .open
        case .save: return .saveForLater
        case .pray: return .saveToSelah
        case .discuss: return .startGroupDiscussion
        case .share: return .share
        }
    }

    private static func secondaryActionsFor(
        category: AmenSmartContentCategory,
        attachment: AmenSmartAttachment,
        surface: AmenSmartAttachmentSurface,
        primary: AmenSmartAttachmentAction?
    ) -> [AmenSmartAttachmentAction] {
        var actions: [AmenSmartAttachmentAction] = []

        if primary != .saveToSelah, category == .worship || category == .prayer {
            actions.append(.saveToSelah)
        }
        if primary != .addToChurchNotes, category == .sermon || category == .educational || category == .devotional {
            actions.append(.addToChurchNotes)
        }
        if primary != .saveForLater, attachment.type == .article || attachment.type == .podcast {
            actions.append(.saveForLater)
        }
        if surface == .expandedSheet || surface == .detail {
            actions.append(.share)
            if primary != .startGroupDiscussion {
                actions.append(.startGroupDiscussion)
            }
        }

        return actions.filter { $0 != primary }
    }

    // MARK: - Label

    private static func labelFor(
        category: AmenSmartContentCategory,
        intent: AmenSmartUserIntent,
        attachment: AmenSmartAttachment
    ) -> String {
        switch category {
        case .worship: return "Worship"
        case .sermon: return "Sermon"
        case .devotional: return "Devotional"
        case .educational: return "Bible Study"
        case .scripture: return "Scripture"
        case .prayer: return "Prayer"
        case .testimony: return "Testimony"
        case .music: return "Music"
        case .podcast: return "Podcast"
        case .article: return "Article"
        case .entertainment: return "Video"
        case .news: return "News"
        case .general:
            switch attachment.type {
            case .song, .album, .playlist: return "Music"
            case .video: return "Video"
            case .podcast: return "Podcast"
            case .article: return "Article"
            default: return "Link"
            }
        }
    }
}
