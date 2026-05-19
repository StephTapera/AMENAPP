import Foundation
import FirebaseFirestore

// MARK: - Feature 1: Unsent Thoughts

struct UnsentThought: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let sourceSurface: String          // "post_composer", "comment_composer", "berean_chat", "church_notes", "prayer_journal"
    var draftText: String
    var emotionalIntensityScore: Double  // 0.0-1.0, server-computed
    var riskFlags: [String]              // server-computed: "rapid_typing", "repeated_delete", "conflict_language", "late_night", "shame_language"
    var suggestedAction: String?         // server-computed: "save_draft", "turn_to_prayer", "run_peace_check", "revisit_later"
    var resolvedAt: Date?
    var resolutionType: String?          // "continued_writing", "saved_draft", "turned_to_prayer", "peace_checked", "revisited", "shared"
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

// MARK: - Feature 2: Scripture Drift

struct ScriptureDriftSignal: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let signalType: ScriptureDriftType
    var confidence: Double               // 0.0-1.0, server-computed
    var evidenceSummary: String?         // server-computed
    var balancingScriptureSuggestions: [String]  // server-computed scripture refs
    var recommendedReflection: String?   // server-computed
    var relatedThreadIds: [String]
    var scriptureRefs: [String]
    var dismissed: Bool
    @ServerTimestamp var createdAt: Date?
}

enum ScriptureDriftType: String, Codable, CaseIterable, Identifiable {
    case selectiveUse = "selective_use"
    case graceWithoutTruth = "grace_without_truth"
    case truthWithoutGrace = "truth_without_grace"
    case selfJustification = "self_justification"
    case avoidsForgiveness = "avoids_forgiveness"
    case condemnationLanguage = "condemnation_language"
    case distortedApplication = "distorted_application"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selectiveUse: return "Selective Scripture Use"
        case .graceWithoutTruth: return "Grace Without Truth"
        case .truthWithoutGrace: return "Truth Without Grace"
        case .selfJustification: return "Self-Justification Pattern"
        case .avoidsForgiveness: return "Avoiding Forgiveness"
        case .condemnationLanguage: return "Condemnation Language"
        case .distortedApplication: return "Distorted Application"
        }
    }

    // Gentle framing — never accusatory
    var gentleDescription: String {
        switch self {
        case .selectiveUse: return "A possible pattern of emphasizing certain scriptures while avoiding others"
        case .graceWithoutTruth: return "A possible pattern of emphasizing grace while avoiding difficult truths"
        case .truthWithoutGrace: return "A possible pattern of emphasizing truth without much grace or compassion"
        case .selfJustification: return "A possible pattern of using scripture to justify personal positions"
        case .avoidsForgiveness: return "A possible pattern of avoiding forgiveness-related scriptures"
        case .condemnationLanguage: return "A possible pattern of scriptures used in a condemning way"
        case .distortedApplication: return "A possible pattern where scripture may be applied outside its context"
        }
    }
}

// MARK: - Feature 3: Silence Intelligence

struct SilenceSignal: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let targetType: SilenceTargetType
    let targetId: String
    var avoidanceCount: Int
    var lastAvoidedAt: Date?
    var suggestedAction: String?         // server-computed gentle prompt
    var status: SilenceSignalStatus
    @ServerTimestamp var createdAt: Date?
}

enum SilenceTargetType: String, Codable, CaseIterable, Identifiable {
    case prayerThread = "prayer_thread"
    case discernmentItem = "discernment_item"
    case savedVerse = "saved_verse"
    case avoidedConversation = "avoided_conversation"
    case walkWithChristPath = "walk_with_christ_path"
    case dismissedPrompt = "dismissed_prompt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prayerThread: return "Prayer Thread"
        case .discernmentItem: return "Discernment Item"
        case .savedVerse: return "Saved Verse"
        case .avoidedConversation: return "Conversation"
        case .walkWithChristPath: return "Walk Path"
        case .dismissedPrompt: return "Repeated Prompt"
        }
    }
}

enum SilenceSignalStatus: String, Codable, CaseIterable {
    case active
    case resolved
    case dismissed
}

// MARK: - Feature 4: Relational Gravity

struct RelationalGravityNode: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let personId: String
    var displayName: String
    var relationshipType: RelationshipType
    var currentState: RelationshipState
    var stateConfidence: Double          // 0.0-1.0, server-computed
    var unresolvedThreadIds: [String]
    var encouragementScore: Double       // 0.0-1.0
    var conflictScore: Double            // 0.0-1.0
    var prayerCount: Int
    var lastInteractionAt: Date?
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

enum RelationshipType: String, Codable, CaseIterable, Identifiable {
    case friend
    case family
    case mentor
    case mentee
    case churchMember = "church_member"
    case colleague
    case pastor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .friend: return "Friend"
        case .family: return "Family"
        case .mentor: return "Mentor"
        case .mentee: return "Mentee"
        case .churchMember: return "Church Member"
        case .colleague: return "Colleague"
        case .pastor: return "Pastor"
        }
    }
}

enum RelationshipState: String, Codable, CaseIterable, Identifiable {
    case peaceful
    case tense
    case growing
    case drifting
    case unresolved
    case needsPrayer = "needs_prayer"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .peaceful: return "Peaceful"
        case .tense: return "Tense"
        case .growing: return "Growing"
        case .drifting: return "Drifting"
        case .unresolved: return "Unresolved"
        case .needsPrayer: return "Needs Prayer"
        }
    }

    var icon: String {
        switch self {
        case .peaceful: return "leaf"
        case .tense: return "exclamationmark.circle"
        case .growing: return "arrow.up.heart"
        case .drifting: return "wind"
        case .unresolved: return "questionmark.circle"
        case .needsPrayer: return "hands.sparkles"
        }
    }
}

// MARK: - Feature 5: Moment Interception

struct MomentInterceptionEvent: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let triggerType: MomentTriggerType
    let sourceSurface: String
    var riskScore: Double               // 0.0-1.0, server-computed
    var userAction: MomentUserAction?
    @ServerTimestamp var createdAt: Date?
}

enum MomentTriggerType: String, Codable, CaseIterable, Identifiable {
    case lateNightPosting = "late_night_posting"
    case rapidTyping = "rapid_typing"
    case repeatedDeleteRewrite = "repeated_delete_rewrite"
    case highAngerScore = "high_anger_score"
    case spiritualManipulationRisk = "spiritual_manipulation_risk"
    case harshPublicCorrection = "harsh_public_correction"
    case impulsiveSend = "impulsive_send"

    var id: String { rawValue }
}

enum MomentUserAction: String, Codable, CaseIterable {
    case breathed
    case prayedFirst = "prayed_first"
    case savedDraft = "saved_draft"
    case ranPeaceCheck = "ran_peace_check"
    case continuedAnyway = "continued_anyway"
    case dismissed
}

// MARK: - Feature 6: Post-Action Reflection

struct PostActionReflection: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let sourceActionId: String
    let actionType: ReflectionActionType
    var intentBefore: String?           // user-written, optional
    var outcomeReflection: String?      // user-written, optional
    var lessonLearned: String?          // user-written, optional
    var completedAt: Date?
    @ServerTimestamp var createdAt: Date?
}

enum ReflectionActionType: String, Codable, CaseIterable, Identifiable {
    case sentSensitiveMessage = "sent_sensitive_message"
    case postedPublicThought = "posted_public_thought"
    case resolvedConflict = "resolved_conflict"
    case completedPrayer = "completed_prayer"
    case finishedWalkWithChrist = "finished_walk_with_christ"
    case madeDiscernmentDecision = "made_discernment_decision"

    var id: String { rawValue }

    var reflectionQuestion: String {
        switch self {
        case .sentSensitiveMessage: return "How do you feel about how that conversation went?"
        case .postedPublicThought: return "Did your words match your intent?"
        case .resolvedConflict: return "Would you handle anything differently?"
        case .completedPrayer: return "What did you sense during that prayer?"
        case .finishedWalkWithChrist: return "What stood out to you today?"
        case .madeDiscernmentDecision: return "What helped you reach that decision?"
        }
    }
}

// MARK: - Feature 7: Truth vs Emotion

struct TruthEmotionAnalysis: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let sourceText: String             // stored ephemerally, never logged to analytics
    var emotionalClaim: String?        // server-computed
    var factualPossibility: String?    // server-computed
    var assumptions: [String]          // server-computed
    var reframes: [String]             // server-computed
    var scriptureAnchor: String?       // server-computed scripture ref
    var scriptureText: String?         // server-computed scripture text
    @ServerTimestamp var createdAt: Date?
}

// MARK: - Feature 8: Weight of Words

struct WeightOfWordsScore: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let sourceText: String             // never logged to analytics
    var scoreLabel: WordWeightLabel
    var scoreValue: Double             // 0.0-1.0, server-computed (higher = heavier/more harmful)
    var flags: [WordWeightFlag]        // server-computed
    var suggestedRewrite: String?      // server-computed
    @ServerTimestamp var createdAt: Date?
}

enum WordWeightLabel: String, Codable, CaseIterable, Identifiable {
    case light
    case encouraging
    case heavy
    case sharp
    case harmful

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .encouraging: return "Encouraging"
        case .heavy: return "Heavy"
        case .sharp: return "Sharp"
        case .harmful: return "Needs Revision"
        }
    }

    var icon: String {
        switch self {
        case .light: return "feather"
        case .encouraging: return "heart"
        case .heavy: return "scalemass"
        case .sharp: return "bolt"
        case .harmful: return "exclamationmark.triangle"
        }
    }

    // Mirror metaphor — private feedback, not a grade
    var mirrorMessage: String {
        switch self {
        case .light: return "These words feel gentle and clear."
        case .encouraging: return "These words carry real encouragement."
        case .heavy: return "These words may land heavily. That might be okay."
        case .sharp: return "These words have a sharp edge. Consider the impact."
        case .harmful: return "These words may cause harm. A revision could help."
        }
    }
}

enum WordWeightFlag: String, Codable, CaseIterable {
    case highCorrectionIntensity = "high_correction_intensity"
    case sarcasmDetected = "sarcasm_detected"
    case shameLanguage = "shame_language"
    case spiritualManipulation = "spiritual_manipulation"
    case condemnationTone = "condemnation_tone"
    case highEncouragement = "high_encouragement"
    case lowHumility = "low_humility"
    case scriptureIntegrityRisk = "scripture_integrity_risk"
}

// MARK: - Feature 9: Community Discernment

struct CommunityDiscernmentSignal: Codable, Identifiable {
    @DocumentID var id: String?
    let contentId: String
    let signalType: DiscernmentSignalType
    var aggregateCount: Int            // server-managed, never client-writable
    var thresholdMet: Bool             // server-managed
    var generatedSummary: String?      // server-generated, never reveals individual users
    var expiresAt: Date?
    @ServerTimestamp var createdAt: Date?
}

enum DiscernmentSignalType: String, Codable, CaseIterable, Identifiable {
    case clarificationNeeded = "clarification_needed"
    case concernRaised = "concern_raised"
    case communityEncouragement = "community_encouragement"
    case confusionSignal = "confusion_signal"
    case bereanAnalysisRequested = "berean_analysis_requested"
    case scriptureShared = "scripture_shared"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clarificationNeeded: return "Many asked for clarity"
        case .concernRaised: return "Some had concerns"
        case .communityEncouragement: return "Many found this encouraging"
        case .confusionSignal: return "Some found this confusing"
        case .bereanAnalysisRequested: return "Many requested Berean review"
        case .scriptureShared: return "Many saved this scripture"
        }
    }
}

// MARK: - Feature 10: Eternal Weight

struct EternalWeightSignal: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let contentId: String
    var state: EternalWeightState
    var supportingSignals: [String]     // server-computed signal keys
    var confidenceScore: Double         // 0.0-1.0, server-computed
    var reflectionPrompt: String?       // server-computed
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

enum EternalWeightState: String, Codable, CaseIterable, Identifiable {
    case growing
    case neutral
    case misaligned
    case needsReflection = "needs_reflection"
    case bearingFruit = "bearing_fruit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .growing: return "Growing"
        case .neutral: return "Neutral"
        case .misaligned: return "Misaligned"
        case .needsReflection: return "Needs Reflection"
        case .bearingFruit: return "Bearing Fruit"
        }
    }

    var icon: String {
        switch self {
        case .growing: return "arrow.up.heart.fill"
        case .neutral: return "circle"
        case .misaligned: return "arrow.triangle.2.circlepath"
        case .needsReflection: return "thought.bubble"
        case .bearingFruit: return "leaf.fill"
        }
    }

    var description: String {
        switch self {
        case .growing: return "This content shows signs of spiritual growth over time."
        case .neutral: return "This content doesn't show strong signals either way."
        case .misaligned: return "This content may benefit from reflection on its direction."
        case .needsReflection: return "There are patterns here worth sitting with."
        case .bearingFruit: return "This content has generated encouragement, prayer, and reflection."
        }
    }
}

// MARK: - Orchestrator Output

struct SpiritualOSPrompt: Identifiable {
    let id: UUID = UUID()
    let promptType: SpiritualOSPromptType
    let confidence: Double
    let userFacingMessage: String
    let suggestedActions: [SpiritualOSAction]
    let privateSignalIds: [String]
    let safetyFlags: [String]
    let shouldSurfacePrompt: Bool
}

enum SpiritualOSPromptType: String, CaseIterable {
    case unsentThoughtWarning = "unsent_thought_warning"
    case scriptureDriftInsight = "scripture_drift_insight"
    case silencePattern = "silence_pattern"
    case relationshipAttention = "relationship_attention"
    case momentIntercept = "moment_intercept"
    case postActionReflection = "post_action_reflection"
    case truthEmotionCheck = "truth_emotion_check"
    case weightOfWordsAlert = "weight_of_words_alert"
    case communityDiscernment = "community_discernment"
    case eternalWeightReflection = "eternal_weight_reflection"
}

enum SpiritualOSAction: String, CaseIterable {
    case continueWriting = "continue_writing"
    case saveAsDraft = "save_as_draft"
    case turnToPrayer = "turn_to_prayer"
    case runPeaceCheck = "run_peace_check"
    case revisitLater = "revisit_later"
    case shareAnyway = "share_anyway"
    case breathe
    case prayFirst = "pray_first"
    case dismiss
    case openReflection = "open_reflection"
    case rewriteWithGrace = "rewrite_with_grace"
    case prayForPerson = "pray_for_person"
    case seekReconciliation = "seek_reconciliation"
}
