import Foundation
import SwiftUI

// MARK: - Action Intelligence Core

/// Privacy lane for intent detection. Public/community content can be indexed server-side;
/// confidential and sacred content should keep detection local unless a user acts.
enum ActionIntelligencePrivacyTier: String, Codable, CaseIterable, Sendable {
    case publicCommunity = "tier_p"
    case confidential = "tier_c"
    case sacred = "tier_s"

    var requiresLocalDetection: Bool {
        self == .confidential || self == .sacred
    }
}

enum ActionIntelligenceSurface: String, Codable, CaseIterable, Sendable {
    case feedPost = "feed_post"
    case comment = "comment"
    case message = "message"
    case directMessage = "direct_message"
    case groupChat = "group_chat"
    case amenSpace = "amen_space"
    case amenRoom = "amen_room"
    case churchNote = "church_note"
    case sermon = "sermon"
    case creatorPost = "creator_post"
    case organizationUpdate = "organization_update"
}

enum CommitmentObjectClass: String, Codable, CaseIterable, Sendable {
    case moment
    case commitment
    case need
    case initiative

    var displayName: String {
        switch self {
        case .moment: return "Moment"
        case .commitment: return "Commitment"
        case .need: return "Need"
        case .initiative: return "Initiative"
        }
    }
}

enum AmenIntentKind: String, Codable, CaseIterable, Sendable {
    case prayerNeed = "prayer_need"
    case prayerCommitment = "prayer_commitment"
    case scriptureReference = "scripture_reference"
    case event = "event"
    case volunteerOffer = "volunteer_offer"
    case volunteerNeed = "volunteer_need"
    case initiativeIdea = "initiative_idea"
    case studyPrompt = "study_prompt"
    case creatorResource = "creator_resource"
    case openQuestion = "open_question"
    case followUp = "follow_up"

    var commitmentClass: CommitmentObjectClass {
        switch self {
        case .event, .scriptureReference, .studyPrompt, .creatorResource, .openQuestion:
            return .moment
        case .prayerCommitment, .volunteerOffer, .followUp:
            return .commitment
        case .prayerNeed, .volunteerNeed:
            return .need
        case .initiativeIdea:
            return .initiative
        }
    }

    var title: String {
        switch self {
        case .prayerNeed: return "Prayer Need"
        case .prayerCommitment: return "Prayer Commitment"
        case .scriptureReference: return "Scripture"
        case .event: return "Event"
        case .volunteerOffer: return "Volunteer Offer"
        case .volunteerNeed: return "Volunteer Need"
        case .initiativeIdea: return "Initiative"
        case .studyPrompt: return "Study Prompt"
        case .creatorResource: return "Creator Resource"
        case .openQuestion: return "Open Question"
        case .followUp: return "Follow-Up"
        }
    }
}

enum AmenActionVerb: String, Codable, CaseIterable, Sendable {
    case prayNow = "pray_now"
    case commitToPray = "commit_to_pray"
    case setPrayerReminder = "set_prayer_reminder"
    case followUpdates = "follow_updates"
    case addToPrayerList = "add_to_prayer_list"
    case saveVerse = "save_verse"
    case compareTranslations = "compare_translations"
    case hearAudio = "hear_audio"
    case addToStudyPlan = "add_to_study_plan"
    case rsvp = "rsvp"
    case addToCalendar = "add_to_calendar"
    case inviteFriend = "invite_friend"
    case getDirections = "get_directions"
    case volunteer = "volunteer"
    case assignVolunteer = "assign_volunteer"
    case messageUser = "message_user"
    case addToTeam = "add_to_team"
    case scheduleFollowUp = "schedule_follow_up"
    case createInitiative = "create_initiative"
    case inviteLeaders = "invite_leaders"
    case startFundraiser = "start_fundraiser"
    case createVolunteerEvent = "create_volunteer_event"
    case saveToChurchNotes = "save_to_church_notes"
    case createReadingPlan = "create_reading_plan"
    case createDiscussion = "create_discussion"
    case generateStudyQuestions = "generate_study_questions"
    case saveResource = "save_resource"
    case startLearning = "start_learning"
    case followCreator = "follow_creator"
    case markComplete = "mark_complete"
    case sendEncouragement = "send_encouragement"
    case releaseCommitment = "release_commitment"
    case answerQuestion = "answer_question"
    case dismissSuggestion = "dismiss_suggestion"

    var title: String {
        switch self {
        case .prayNow: return "Pray Now"
        case .commitToPray: return "Commit to Pray"
        case .setPrayerReminder: return "Prayer Reminder"
        case .followUpdates: return "Follow Updates"
        case .addToPrayerList: return "Prayer List"
        case .saveVerse: return "Save Verse"
        case .compareTranslations: return "Compare"
        case .hearAudio: return "Hear Audio"
        case .addToStudyPlan: return "Study Plan"
        case .rsvp: return "RSVP"
        case .addToCalendar: return "Calendar"
        case .inviteFriend: return "Invite"
        case .getDirections: return "Directions"
        case .volunteer: return "Volunteer"
        case .assignVolunteer: return "Assign"
        case .messageUser: return "Message"
        case .addToTeam: return "Add to Team"
        case .scheduleFollowUp: return "Follow Up"
        case .createInitiative: return "Initiative"
        case .inviteLeaders: return "Invite Leaders"
        case .startFundraiser: return "Fundraiser"
        case .createVolunteerEvent: return "Volunteer Event"
        case .saveToChurchNotes: return "Church Notes"
        case .createReadingPlan: return "Reading Plan"
        case .createDiscussion: return "Discussion"
        case .generateStudyQuestions: return "Questions"
        case .saveResource: return "Save"
        case .startLearning: return "Learn"
        case .followCreator: return "Follow"
        case .markComplete: return "Complete"
        case .sendEncouragement: return "Encourage"
        case .releaseCommitment: return "Release"
        case .answerQuestion: return "Answer"
        case .dismissSuggestion: return "Dismiss"
        }
    }

    var systemImage: String {
        switch self {
        case .prayNow, .commitToPray: return "hands.and.sparkles"
        case .setPrayerReminder, .scheduleFollowUp: return "bell.badge"
        case .followUpdates, .followCreator: return "person.crop.circle.badge.plus"
        case .addToPrayerList: return "list.bullet.clipboard"
        case .saveVerse, .saveResource: return "bookmark"
        case .compareTranslations: return "text.book.closed"
        case .hearAudio: return "speaker.wave.2"
        case .addToStudyPlan, .createReadingPlan: return "book.pages"
        case .rsvp: return "checkmark.seal"
        case .addToCalendar: return "calendar.badge.plus"
        case .inviteFriend, .inviteLeaders: return "person.2.badge.plus"
        case .getDirections: return "location"
        case .volunteer, .assignVolunteer: return "figure.2.and.child.holdinghands"
        case .messageUser, .sendEncouragement: return "message"
        case .addToTeam: return "person.3"
        case .createInitiative: return "flag"
        case .startFundraiser: return "dollarsign.circle"
        case .createVolunteerEvent: return "calendar"
        case .saveToChurchNotes: return "note.text"
        case .createDiscussion: return "bubble.left.and.bubble.right"
        case .generateStudyQuestions, .answerQuestion: return "questionmark.bubble"
        case .startLearning: return "play.circle"
        case .markComplete: return "checkmark.circle"
        case .releaseCommitment: return "arrow.uturn.backward.circle"
        case .dismissSuggestion: return "xmark"
        }
    }

    var fulfillmentRank: Int {
        switch self {
        case .prayNow, .rsvp, .volunteer, .assignVolunteer, .markComplete, .answerQuestion:
            return 100
        case .commitToPray, .addToCalendar, .createReadingPlan, .createInitiative, .sendEncouragement:
            return 90
        case .saveVerse, .saveToChurchNotes, .addToStudyPlan, .createVolunteerEvent, .messageUser:
            return 80
        case .setPrayerReminder, .scheduleFollowUp, .createDiscussion, .generateStudyQuestions:
            return 70
        case .inviteFriend, .inviteLeaders, .addToTeam, .getDirections:
            return 60
        case .followUpdates, .followCreator, .startFundraiser, .saveResource, .startLearning:
            return 50
        case .compareTranslations, .hearAudio, .addToPrayerList:
            return 45
        case .releaseCommitment, .dismissSuggestion:
            return 10
        }
    }
}

struct AmenActionSuggestion: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let verb: AmenActionVerb
    let title: String
    let systemImage: String
    let explanation: String
    let requiresConfirmation: Bool
    let createsServerObject: Bool
    let rank: Int

    init(
        id: String = UUID().uuidString,
        verb: AmenActionVerb,
        explanation: String,
        requiresConfirmation: Bool = true,
        createsServerObject: Bool = false,
        rankAdjustment: Int = 0
    ) {
        self.id = id
        self.verb = verb
        self.title = verb.title
        self.systemImage = verb.systemImage
        self.explanation = explanation
        self.requiresConfirmation = requiresConfirmation
        self.createsServerObject = createsServerObject
        self.rank = verb.fulfillmentRank + rankAdjustment
    }
}

struct AmenIntentAnalysis: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let sourceId: String
    let surface: ActionIntelligenceSurface
    let privacyTier: ActionIntelligencePrivacyTier
    let intentKind: AmenIntentKind
    let objectClass: CommitmentObjectClass
    let confidence: Double
    let sensitivityLevel: CareSensitivityLevel
    let detectedSignals: [String]
    let primaryActions: [AmenActionSuggestion]
    let secondaryActions: [AmenActionSuggestion]
    let explanation: String
    let shouldRenderCollapsed: Bool
    let shouldSuppressCapsule: Bool
    let createdAt: Date

    var allActions: [AmenActionSuggestion] { primaryActions + secondaryActions }
}

struct ActionIntelligenceSource: Sendable {
    let id: String
    let text: String
    let surface: ActionIntelligenceSurface
    let privacyTier: ActionIntelligencePrivacyTier
    let authorId: String?
    let currentUserId: String?
    let isAuthorLeader: Bool
    let isCurrentUserLeader: Bool
    let createdAt: Date

    init(
        id: String,
        text: String,
        surface: ActionIntelligenceSurface,
        privacyTier: ActionIntelligencePrivacyTier = .confidential,
        authorId: String? = nil,
        currentUserId: String? = nil,
        isAuthorLeader: Bool = false,
        isCurrentUserLeader: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.surface = surface
        self.privacyTier = privacyTier
        self.authorId = authorId
        self.currentUserId = currentUserId
        self.isAuthorLeader = isAuthorLeader
        self.isCurrentUserLeader = isCurrentUserLeader
        self.createdAt = createdAt
    }
}

struct AmenCommitmentObject: Identifiable, Codable, Equatable, Sendable {
    enum LifecycleState: String, Codable, CaseIterable, Sendable {
        case detected
        case proposed
        case acknowledged
        case active
        case fulfilled
        case released
        case resolved
        case archived
    }

    let id: String
    let sourceId: String
    let objectClass: CommitmentObjectClass
    let intentKind: AmenIntentKind
    var state: LifecycleState
    let privacyTier: ActionIntelligencePrivacyTier
    let createdAt: Date
    var dueAt: Date?
    var lastNudgedAt: Date?
    var nudgeCount: Int
    var witnessSummary: String?

    var canNudgeAgain: Bool {
        nudgeCount == 0 && state == .active
    }
}

struct AmenRoomBriefing: Identifiable, Codable, Equatable, Sendable {
    struct BriefingItem: Identifiable, Codable, Equatable, Sendable {
        enum Priority: String, Codable, Sendable { case low, normal, high, urgent }

        let id: String
        let title: String
        let count: Int
        let intentKind: AmenIntentKind
        let priority: Priority
        let suggestedAction: AmenActionVerb?
    }

    let id: String
    let roomId: String
    let title: String
    let generatedAt: Date
    let currentGoals: [String]
    let items: [BriefingItem]
    let openQuestions: Int
    let activePrayerNeeds: Int
    let upcomingEvents: Int
    let volunteerNeeds: Int
    let unresolvedCommitments: Int
}

// MARK: - Detector / Ranker

final class ActionIntelligenceEngine {
    static let shared = ActionIntelligenceEngine()

    private let minimumConfidence = 0.48
    private let highSensitivityConfidence = 0.68
    private let scriptureBooks: Set<String> = [
        "genesis", "exodus", "leviticus", "numbers", "deuteronomy", "joshua", "judges", "ruth",
        "samuel", "kings", "chronicles", "ezra", "nehemiah", "esther", "job", "psalm", "psalms",
        "proverbs", "ecclesiastes", "song", "isaiah", "jeremiah", "lamentations", "ezekiel", "daniel",
        "hosea", "joel", "amos", "obadiah", "jonah", "micah", "nahum", "habakkuk", "zephaniah",
        "haggai", "zechariah", "malachi", "matthew", "mark", "luke", "john", "acts", "romans",
        "corinthians", "galatians", "ephesians", "philippians", "colossians", "thessalonians", "timothy",
        "titus", "philemon", "hebrews", "james", "peter", "jude", "revelation"
    ]

    private init() {}

    func analyze(source: ActionIntelligenceSource) -> AmenIntentAnalysis? {
        let trimmed = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let risk = ContentRiskAnalyzer.shared.quickScan(text: trimmed)
        if shouldSuppressForRisk(risk) {
            return crisisSuppressionAnalysis(source: source, risk: risk)
        }

        let lowered = trimmed.lowercased()
        let candidates = buildCandidates(for: lowered, source: source)
        guard let best = candidates.max(by: { $0.confidence < $1.confidence }), best.confidence >= threshold(for: best.sensitivity) else {
            return nil
        }

        let rankedActions = best.actions.sorted { lhs, rhs in
            if lhs.rank == rhs.rank { return lhs.title < rhs.title }
            return lhs.rank > rhs.rank
        }
        let primary = Array(rankedActions.prefix(3))
        let secondary = Array(rankedActions.dropFirst(3)) + [
            AmenActionSuggestion(
                verb: .dismissSuggestion,
                explanation: "Teaches Amen not to suggest this action here.",
                requiresConfirmation: false
            )
        ]

        return AmenIntentAnalysis(
            id: UUID().uuidString,
            sourceId: source.id,
            surface: source.surface,
            privacyTier: source.privacyTier,
            intentKind: best.kind,
            objectClass: best.kind.commitmentClass,
            confidence: best.confidence,
            sensitivityLevel: best.sensitivity,
            detectedSignals: best.signals,
            primaryActions: primary,
            secondaryActions: secondary,
            explanation: explanation(for: best.kind, signals: best.signals, privacyTier: source.privacyTier),
            shouldRenderCollapsed: best.confidence < 0.72 || best.sensitivity != .standard,
            shouldSuppressCapsule: false,
            createdAt: Date()
        )
    }

    func analyzeText(
        _ text: String,
        id: String = UUID().uuidString,
        surface: ActionIntelligenceSurface,
        privacyTier: ActionIntelligencePrivacyTier = .confidential
    ) -> AmenIntentAnalysis? {
        analyze(source: ActionIntelligenceSource(id: id, text: text, surface: surface, privacyTier: privacyTier))
    }

    func buildRoomBriefing(roomId: String, title: String, analyses: [AmenIntentAnalysis]) -> AmenRoomBriefing {
        let visible = analyses.filter { !$0.shouldSuppressCapsule }
        let prayerNeeds = visible.filter { $0.intentKind == .prayerNeed }
        let events = visible.filter { $0.intentKind == .event }
        let volunteerNeeds = visible.filter { $0.intentKind == .volunteerNeed }
        let questions = visible.filter { $0.intentKind == .openQuestion }
        let commitments = visible.filter { $0.objectClass == .commitment }

        var items: [AmenRoomBriefing.BriefingItem] = []
        appendBriefingItem(&items, count: prayerNeeds.count, title: "active prayer requests", kind: .prayerNeed, priority: .high, action: .prayNow)
        appendBriefingItem(&items, count: events.count, title: "upcoming events", kind: .event, priority: .normal, action: .addToCalendar)
        appendBriefingItem(&items, count: volunteerNeeds.count, title: "volunteer needs", kind: .volunteerNeed, priority: .high, action: .volunteer)
        appendBriefingItem(&items, count: questions.count, title: "unanswered questions", kind: .openQuestion, priority: .normal, action: .answerQuestion)
        appendBriefingItem(&items, count: commitments.count, title: "open commitments", kind: .followUp, priority: .normal, action: .scheduleFollowUp)

        let goals = items.prefix(3).map { "\($0.count) \($0.title)" }
        return AmenRoomBriefing(
            id: UUID().uuidString,
            roomId: roomId,
            title: title,
            generatedAt: Date(),
            currentGoals: goals,
            items: items,
            openQuestions: questions.count,
            activePrayerNeeds: prayerNeeds.count,
            upcomingEvents: events.count,
            volunteerNeeds: volunteerNeeds.count,
            unresolvedCommitments: commitments.count
        )
    }

    private struct Candidate {
        let kind: AmenIntentKind
        let confidence: Double
        let sensitivity: CareSensitivityLevel
        let signals: [String]
        let actions: [AmenActionSuggestion]
    }

    private func buildCandidates(for text: String, source: ActionIntelligenceSource) -> [Candidate] {
        var candidates: [Candidate] = []

        addPrayerNeedCandidate(text, to: &candidates)
        addPrayerCommitmentCandidate(text, to: &candidates)
        addScriptureCandidate(text, to: &candidates)
        addEventCandidate(text, to: &candidates)
        addVolunteerCandidate(text, source: source, to: &candidates)
        addInitiativeCandidate(text, source: source, to: &candidates)
        addStudyCandidate(text, to: &candidates)
        addCreatorResourceCandidate(text, to: &candidates)
        addQuestionCandidate(text, to: &candidates)
        addFollowUpCandidate(text, to: &candidates)

        return candidates
    }

    private func addPrayerNeedCandidate(_ text: String, to candidates: inout [Candidate]) {
        let signals = matches(in: text, patterns: ["please pray", "pray for", "prayer request", "need prayer", "keep me in prayer", "surgery", "hospital", "diagnosis", "recovery"])
        guard !signals.isEmpty else { return }
        let sensitivity: CareSensitivityLevel = signals.contains(where: { ["surgery", "hospital", "diagnosis"].contains($0) }) ? .elevated : .standard
        candidates.append(Candidate(
            kind: .prayerNeed,
            confidence: min(0.92, 0.52 + Double(signals.count) * 0.1),
            sensitivity: sensitivity,
            signals: signals,
            actions: [
                AmenActionSuggestion(verb: .prayNow, explanation: "This directly fulfills the prayer need.", requiresConfirmation: false),
                AmenActionSuggestion(verb: .commitToPray, explanation: "Creates a private commitment lifecycle.", createsServerObject: true),
                AmenActionSuggestion(verb: .setPrayerReminder, explanation: "Creates one gentle follow-up reminder.", createsServerObject: true),
                AmenActionSuggestion(verb: .followUpdates, explanation: "Keeps you connected to future updates.", createsServerObject: true),
                AmenActionSuggestion(verb: .addToPrayerList, explanation: "Saves this request without making it public.", createsServerObject: true)
            ]
        ))
    }

    private func addPrayerCommitmentCandidate(_ text: String, to candidates: inout [Candidate]) {
        let signals = matches(in: text, patterns: ["i'll pray", "i will pray", "praying for you", "covering you in prayer", "keeping you in prayer"])
        guard !signals.isEmpty else { return }
        candidates.append(Candidate(
            kind: .prayerCommitment,
            confidence: min(0.9, 0.58 + Double(signals.count) * 0.12),
            sensitivity: .standard,
            signals: signals,
            actions: [
                AmenActionSuggestion(verb: .prayNow, explanation: "Fulfills the commitment immediately.", requiresConfirmation: false),
                AmenActionSuggestion(verb: .setPrayerReminder, explanation: "One gentle reminder, never a streak or public count.", createsServerObject: true),
                AmenActionSuggestion(verb: .sendEncouragement, explanation: "Closes the loop with care.", createsServerObject: true),
                AmenActionSuggestion(verb: .releaseCommitment, explanation: "Lets the user release an over-commitment without shame.", requiresConfirmation: false)
            ]
        ))
    }

    private func addScriptureCandidate(_ text: String, to candidates: inout [Candidate]) {
        let tokens = text.replacingOccurrences(of: ":", with: " ").split(separator: " ").map(String.init)
        let hasBook = tokens.contains { scriptureBooks.contains($0.trimmingCharacters(in: .punctuationCharacters)) }
        let hasChapterVerse = text.contains(":") && text.contains(where: { $0.isNumber })
        guard hasBook && hasChapterVerse else { return }
        candidates.append(Candidate(
            kind: .scriptureReference,
            confidence: 0.82,
            sensitivity: .standard,
            signals: ["scripture_reference"],
            actions: [
                AmenActionSuggestion(verb: .saveVerse, explanation: "Saves the passage to your study context.", createsServerObject: true),
                AmenActionSuggestion(verb: .addToStudyPlan, explanation: "Turns the reference into a study step.", createsServerObject: true),
                AmenActionSuggestion(verb: .compareTranslations, explanation: "Useful for Berean study.", requiresConfirmation: false),
                AmenActionSuggestion(verb: .hearAudio, explanation: "Lets the passage be heard instead of copied.", requiresConfirmation: false)
            ]
        ))
    }

    private func addEventCandidate(_ text: String, to candidates: inout [Candidate]) {
        let signals = matches(in: text, patterns: ["saturday", "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "tonight", "tomorrow", "breakfast", "youth night", "service", "meeting", " at "])
        let hasTime = text.contains("am") || text.contains("pm") || text.contains("tonight") || text.contains("tomorrow")
        guard hasTime && !signals.isEmpty else { return }
        candidates.append(Candidate(
            kind: .event,
            confidence: min(0.86, 0.48 + Double(signals.count) * 0.07),
            sensitivity: .standard,
            signals: signals,
            actions: [
                AmenActionSuggestion(verb: .rsvp, explanation: "Confirms participation before creating more workflow.", createsServerObject: true),
                AmenActionSuggestion(verb: .addToCalendar, explanation: "Moves the event out of chat and into time.", createsServerObject: true),
                AmenActionSuggestion(verb: .inviteFriend, explanation: "Shares the event with someone relevant.", createsServerObject: true),
                AmenActionSuggestion(verb: .getDirections, explanation: "The message appears to include a place or gathering.", requiresConfirmation: false),
                AmenActionSuggestion(verb: .saveToChurchNotes, explanation: "Keeps the event attached to church context.", createsServerObject: true)
            ]
        ))
    }

    private func addVolunteerCandidate(_ text: String, source: ActionIntelligenceSource, to candidates: inout [Candidate]) {
        let offerSignals = matches(in: text, patterns: ["i can help", "i'll help", "i can serve", "i can setup", "i can set up", "count me in"])
        if !offerSignals.isEmpty {
            candidates.append(Candidate(
                kind: .volunteerOffer,
                confidence: min(0.86, 0.54 + Double(offerSignals.count) * 0.12),
                sensitivity: .standard,
                signals: offerSignals,
                actions: [
                    AmenActionSuggestion(verb: source.isCurrentUserLeader ? .assignVolunteer : .volunteer, explanation: "People still confirm assignments; Amen only proposes.", createsServerObject: true),
                    AmenActionSuggestion(verb: .messageUser, explanation: "Connects the offer to a person.", createsServerObject: true),
                    AmenActionSuggestion(verb: .addToTeam, explanation: "Routes the offer through team permissions.", createsServerObject: true),
                    AmenActionSuggestion(verb: .scheduleFollowUp, explanation: "Keeps the offer from disappearing in comments.", createsServerObject: true)
                ]
            ))
        }

        let needSignals = matches(in: text, patterns: ["need volunteers", "need help", "looking for volunteers", "serve with us", "help with setup", "meal train"])
        guard !needSignals.isEmpty else { return }
        candidates.append(Candidate(
            kind: .volunteerNeed,
            confidence: min(0.86, 0.52 + Double(needSignals.count) * 0.11),
            sensitivity: .standard,
            signals: needSignals,
            actions: [
                AmenActionSuggestion(verb: .volunteer, explanation: "Directly answers the need.", createsServerObject: true),
                AmenActionSuggestion(verb: .createVolunteerEvent, explanation: "Turns the need into a coordinated event.", createsServerObject: true),
                AmenActionSuggestion(verb: .inviteLeaders, explanation: "Keeps leadership approval in the loop.", createsServerObject: true),
                AmenActionSuggestion(verb: .scheduleFollowUp, explanation: "Prevents the need from being lost.", createsServerObject: true)
            ]
        ))
    }

    private func addInitiativeCandidate(_ text: String, source: ActionIntelligenceSource, to candidates: inout [Candidate]) {
        let signals = matches(in: text, patterns: ["we should", "someone should", "what if we", "let's help", "lets help", "start a", "do something for", "support the"])
        guard !signals.isEmpty else { return }
        candidates.append(Candidate(
            kind: .initiativeIdea,
            confidence: min(0.84, 0.5 + Double(signals.count) * 0.11),
            sensitivity: .standard,
            signals: signals,
            actions: [
                AmenActionSuggestion(verb: .createInitiative, explanation: "Creates a draft initiative for people to approve.", createsServerObject: true),
                AmenActionSuggestion(verb: .inviteLeaders, explanation: "Initiatives need human authority before launch.", createsServerObject: true, rankAdjustment: source.isCurrentUserLeader ? -20 : 5),
                AmenActionSuggestion(verb: .createVolunteerEvent, explanation: "Scaffolds roles and next steps.", createsServerObject: true),
                AmenActionSuggestion(verb: .startFundraiser, explanation: "Available only after donation rails are configured.", createsServerObject: true)
            ]
        ))
    }

    private func addStudyCandidate(_ text: String, to candidates: inout [Candidate]) {
        let signals = matches(in: text, patterns: ["read ", "before sunday", "study", "discussion questions", "sermon prep", "acts ", "romans "])
        guard !signals.isEmpty && (text.contains("read ") || text.contains("study") || text.contains("before sunday")) else { return }
        candidates.append(Candidate(
            kind: .studyPrompt,
            confidence: min(0.82, 0.46 + Double(signals.count) * 0.09),
            sensitivity: .standard,
            signals: signals,
            actions: [
                AmenActionSuggestion(verb: .createReadingPlan, explanation: "Turns the note into staged preparation.", createsServerObject: true),
                AmenActionSuggestion(verb: .generateStudyQuestions, explanation: "Creates discussion prompts as drafts.", createsServerObject: true),
                AmenActionSuggestion(verb: .createDiscussion, explanation: "Starts a room only after confirmation.", createsServerObject: true),
                AmenActionSuggestion(verb: .saveToChurchNotes, explanation: "Keeps the study tied to church notes.", createsServerObject: true)
            ]
        ))
    }

    private func addCreatorResourceCandidate(_ text: String, to candidates: inout [Candidate]) {
        let signals = matches(in: text, patterns: ["course", "podcast", "book", "album", "sermon series", "released", "new teaching"])
        guard signals.count >= 2 else { return }
        candidates.append(Candidate(
            kind: .creatorResource,
            confidence: min(0.78, 0.44 + Double(signals.count) * 0.08),
            sensitivity: .standard,
            signals: signals,
            actions: [
                AmenActionSuggestion(verb: .saveResource, explanation: "Saves the creator resource to your catalog.", createsServerObject: true),
                AmenActionSuggestion(verb: .startLearning, explanation: "Starts consuming the resource intentionally.", createsServerObject: true),
                AmenActionSuggestion(verb: .addToStudyPlan, explanation: "Adds the resource to a learning plan.", createsServerObject: true),
                AmenActionSuggestion(verb: .followCreator, explanation: "Follows the creator without copying links.", createsServerObject: true)
            ]
        ))
    }

    private func addQuestionCandidate(_ text: String, to candidates: inout [Candidate]) {
        guard text.contains("?") else { return }
        candidates.append(Candidate(
            kind: .openQuestion,
            confidence: 0.58,
            sensitivity: .standard,
            signals: ["question_mark"],
            actions: [
                AmenActionSuggestion(verb: .answerQuestion, explanation: "Marks this as waiting for an answer.", createsServerObject: true),
                AmenActionSuggestion(verb: .createDiscussion, explanation: "Turns the question into a discussion thread.", createsServerObject: true),
                AmenActionSuggestion(verb: .scheduleFollowUp, explanation: "Resurfaces the question if no one answers.", createsServerObject: true)
            ]
        ))
    }

    private func addFollowUpCandidate(_ text: String, to candidates: inout [Candidate]) {
        let signals = matches(in: text, patterns: ["i'll follow up", "i will follow up", "check back", "circle back", "send an update", "let you know"])
        guard !signals.isEmpty else { return }
        candidates.append(Candidate(
            kind: .followUp,
            confidence: min(0.82, 0.5 + Double(signals.count) * 0.1),
            sensitivity: .standard,
            signals: signals,
            actions: [
                AmenActionSuggestion(verb: .scheduleFollowUp, explanation: "Creates one reminder for the promised follow-up.", createsServerObject: true),
                AmenActionSuggestion(verb: .sendEncouragement, explanation: "Sends a care-centered update.", createsServerObject: true),
                AmenActionSuggestion(verb: .markComplete, explanation: "Closes the loop when fulfilled.", createsServerObject: true)
            ]
        ))
    }

    private func matches(in text: String, patterns: [String]) -> [String] {
        patterns.filter { text.contains($0) }
    }

    private func threshold(for sensitivity: CareSensitivityLevel) -> Double {
        switch sensitivity {
        case .standard: return minimumConfidence
        case .elevated, .high, .critical: return highSensitivityConfidence
        }
    }

    private func shouldSuppressForRisk(_ risk: ContentRiskResult) -> Bool {
        switch risk.primaryCategory {
        case .selfHarmCrisis, .violenceThreat, .groomingTrafficking, .explicitSexual:
            return risk.totalScore > 0.32
        case .emotionalDistress:
            return risk.totalScore > 0.68
        default:
            return false
        }
    }

    private func crisisSuppressionAnalysis(source: ActionIntelligenceSource, risk: ContentRiskResult) -> AmenIntentAnalysis {
        AmenIntentAnalysis(
            id: UUID().uuidString,
            sourceId: source.id,
            surface: source.surface,
            privacyTier: source.privacyTier,
            intentKind: .followUp,
            objectClass: .commitment,
            confidence: min(1.0, risk.totalScore),
            sensitivityLevel: .critical,
            detectedSignals: risk.matchedSignals.isEmpty ? [risk.primaryCategory.rawValue] : risk.matchedSignals,
            primaryActions: [],
            secondaryActions: [],
            explanation: "Action capsules are suppressed because this may need a care or safety pathway.",
            shouldRenderCollapsed: true,
            shouldSuppressCapsule: true,
            createdAt: Date()
        )
    }

    private func explanation(for kind: AmenIntentKind, signals: [String], privacyTier: ActionIntelligencePrivacyTier) -> String {
        let lane = privacyTier.requiresLocalDetection ? "Detected on device" : "Detected in the community lane"
        let signalText = signals.prefix(3).joined(separator: ", ")
        return "\(lane): \(kind.title) from \(signalText)."
    }

    private func appendBriefingItem(
        _ items: inout [AmenRoomBriefing.BriefingItem],
        count: Int,
        title: String,
        kind: AmenIntentKind,
        priority: AmenRoomBriefing.BriefingItem.Priority,
        action: AmenActionVerb?
    ) {
        guard count > 0 else { return }
        items.append(.init(id: UUID().uuidString, title: title, count: count, intentKind: kind, priority: priority, suggestedAction: action))
    }
}

// MARK: - Liquid Glass Capsule

struct AmenActionIntelligenceCapsule: View {
    let analysis: AmenIntentAnalysis
    var startsExpanded: Bool = false
    var onAction: (AmenActionSuggestion) -> Void
    var onDismiss: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isExpanded: Bool = false

    private var visibleActions: [AmenActionSuggestion] {
        isExpanded ? analysis.allActions : analysis.primaryActions
    }

    var body: some View {
        if !analysis.shouldSuppressCapsule {
            VStack(alignment: .leading, spacing: 10) {
                header
                actionRow
                if isExpanded {
                    Text(analysis.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear { isExpanded = startsExpanded && !analysis.shouldRenderCollapsed }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Suggested actions for \(analysis.intentKind.title)")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: analysis.objectClass == .initiative ? "flag" : "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(analysis.intentKind.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .amenSpringBouncy) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse actions" : "Expand actions")
        }
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleActions) { action in
                    Button {
                        onAction(action)
                        if action.verb == .dismissSuggestion { onDismiss?() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: action.systemImage)
                            Text(action.title)
                                .lineLimit(1)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(action.verb == .dismissSuggestion ? Color.secondary : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                    }
                    .buttonStyle(.plain)
                    .amenGlassEffect(in: Capsule(style: .continuous))
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.explanation)
                }
            }
        }
    }
}

// MARK: - Bridges

extension AmenIntentAnalysis {
    var suggestedActionThreadType: ActionThreadType {
        switch intentKind {
        case .prayerNeed, .prayerCommitment: return .prayerCircle
        case .scriptureReference, .studyPrompt: return .scriptureSupport
        case .event: return .eventFollowup
        case .volunteerOffer, .volunteerNeed: return .volunteerCoordination
        case .initiativeIdea: return .initiative
        case .creatorResource: return .learningPath
        case .openQuestion, .followUp: return .careFollowup
        }
    }

    var suggestedSteps: [ActionSuggestion.SuggestedStep] {
        primaryActions.enumerated().map { index, action in
            ActionSuggestion.SuggestedStep(
                title: action.title,
                type: action.stepType,
                scheduledOffset: index == 0 ? nil : 86_400
            )
        }
    }
}

private extension AmenActionSuggestion {
    var stepType: ActionStep.StepType {
        switch verb {
        case .prayNow, .commitToPray, .setPrayerReminder, .followUpdates, .addToPrayerList:
            return .prayer
        case .saveVerse, .compareTranslations, .hearAudio, .addToStudyPlan, .createReadingPlan, .generateStudyQuestions:
            return .scripture
        case .rsvp, .addToCalendar, .inviteFriend, .getDirections:
            return .event
        case .volunteer, .assignVolunteer, .addToTeam, .createVolunteerEvent:
            return .volunteer
        case .createInitiative, .inviteLeaders, .startFundraiser:
            return .initiative
        case .messageUser, .scheduleFollowUp, .sendEncouragement, .markComplete, .releaseCommitment, .answerQuestion:
            return .checkIn
        case .saveToChurchNotes, .createDiscussion, .saveResource, .startLearning, .followCreator:
            return .resource
        case .dismissSuggestion:
            return .custom
        }
    }
}
