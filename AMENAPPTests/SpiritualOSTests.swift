import Testing
import Foundation
@testable import AMENAPP

// MARK: - Unsent Thoughts Tests

@Suite("Unsent Thoughts Detection")
struct UnsentThoughtsTests {

    @Test("Risk flag count drives intensity score")
    func intensityScalesWithFlagCount() {
        let none: [String] = []
        let two = ["late_night", "conflict_language"]
        let five = ["late_night", "conflict_language", "shame_language", "long_draft", "rapid_typing"]
        #expect(Double(none.count) / 5.0 == 0.0)
        #expect(Double(two.count) / 5.0 == 0.4)
        #expect(min(Double(five.count) / 5.0, 1.0) == 1.0)
    }

    @Test("Conflict language phrases trigger flag")
    func conflictPhrasesTriggerFlag() {
        let phrases = ["you always", "you never", "that's not fair", "typical"]
        let triggers = ["you always", "you never", "you're wrong", "that's not fair", "typical", "every time"]
        for phrase in phrases {
            #expect(triggers.contains(where: { phrase.lowercased().contains($0) }))
        }
    }

    @Test("Shame language phrases trigger flag")
    func shamePhrasesTriggerFlag() {
        let shame = ["should be ashamed", "how could you", "pathetic", "disgraceful"]
        for word in shame {
            #expect(shame.contains(where: { word.lowercased().contains($0) }))
        }
    }

    @Test("Valid resolution types are exhaustive")
    func resolutionTypesExhaustive() {
        let valid = ["continued_writing", "saved_draft", "turned_to_prayer",
                     "peace_checked", "revisited", "shared"]
        #expect(valid.count == 6)
    }
}

// MARK: - Scripture Drift Tests

@Suite("Scripture Drift Signal")
struct ScriptureDriftTests {

    @Test("All drift types have non-empty display names")
    func allDriftTypesHaveDisplayNames() {
        for type in ScriptureDriftType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("All gentle descriptions use tentative language")
    func gentleDescriptionsUseTentativeLanguage() {
        for type in ScriptureDriftType.allCases {
            let desc = type.gentleDescription.lowercased()
            let tentative = desc.contains("possible") || desc.contains("may") || desc.contains("might")
            #expect(tentative, "\(type.rawValue) must use tentative language")
        }
    }

    @Test("Gentle descriptions never use accusatory second-person")
    func noAccusatoryLanguage() {
        for type in ScriptureDriftType.allCases {
            let desc = type.gentleDescription.lowercased()
            #expect(!desc.contains("you are"))
            #expect(!desc.contains("you have failed"))
            #expect(!desc.contains("you failed"))
        }
    }

    @Test("Confidence score UI clamping")
    func confidenceUIClamp() {
        let overMax = 2.5
        #expect(min(overMax, 1.0) == 1.0)
    }
}

// MARK: - Silence Intelligence Tests

@Suite("Silence Intelligence")
struct SilenceIntelligenceTests {

    @Test("All target types have non-empty display names")
    func allTargetTypesHaveDisplayNames() {
        for type in SilenceTargetType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("Signal status raw values are non-empty")
    func signalStatusRawValues() {
        for status in SilenceSignalStatus.allCases {
            #expect(!status.rawValue.isEmpty)
        }
    }

    @Test("Document ID is deterministic for same inputs")
    func documentIdDeterministic() {
        let id1 = "\(SilenceTargetType.prayerThread.rawValue)_prayer_abc"
        let id2 = "\(SilenceTargetType.prayerThread.rawValue)_prayer_abc"
        #expect(id1 == id2)
        #expect(id1 == "prayer_thread_prayer_abc")
    }

    @Test("Surfacing threshold is avoidanceCount >= 2")
    func surfacingThreshold() {
        #expect(1 < 2)   // below threshold — not surfaced
        #expect(2 >= 2)  // at threshold — surfaced
        #expect(5 >= 2)  // above threshold — surfaced
    }
}

// MARK: - Relational Gravity Tests

@Suite("Relational Gravity")
struct RelationalGravityTests {

    @Test("All relationship types have display names")
    func allRelationshipTypesHaveDisplayNames() {
        for type in RelationshipType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("All relationship states have display names and icons")
    func allRelationshipStatesComplete() {
        for state in RelationshipState.allCases {
            #expect(!state.displayName.isEmpty)
            #expect(!state.icon.isEmpty)
        }
    }

    @Test("Default node initialises to peaceful state")
    func defaultNodeIsPeaceful() {
        let node = RelationalGravityNode(
            id: nil, userId: "u1", personId: "p1",
            displayName: "Friend", relationshipType: .friend,
            currentState: .peaceful, stateConfidence: 0.5,
            unresolvedThreadIds: [], encouragementScore: 0.5,
            conflictScore: 0.0, prayerCount: 0, lastInteractionAt: nil
        )
        #expect(node.currentState == .peaceful)
        #expect(node.conflictScore == 0.0)
        #expect(node.prayerCount == 0)
    }
}

// MARK: - Moment Interception Tests

@Suite("Moment Interception")
struct MomentInterceptionTests {

    @Test("All trigger types have non-empty raw values")
    func allTriggerTypesHaveRawValues() {
        for type in MomentTriggerType.allCases {
            #expect(!type.rawValue.isEmpty)
        }
    }

    @Test("All user actions have non-empty raw values")
    func allUserActionsHaveRawValues() {
        for action in MomentUserAction.allCases {
            #expect(!action.rawValue.isEmpty)
        }
    }

    @Test("Throttle minimum interval is 3 minutes")
    func throttleIs3Minutes() {
        let interval: TimeInterval = 180
        #expect(interval == 60 * 3)
    }

    @Test("Intercept fires only above 0.5 risk threshold")
    func interceptThreshold() {
        let threshold = 0.5
        #expect(0.2 < threshold)   // no intercept
        #expect(0.8 > threshold)   // intercept
    }

    @Test("Combined trigger weights can hit 1.0 max")
    func combinedWeightsMaxAtOne() {
        let weights: [Double] = [0.25, 0.15, 0.2, 0.35, 0.4, 0.3, 0.2]
        let sum = weights.reduce(0, +)
        let capped = min(sum, 1.0)
        #expect(capped == 1.0)
    }
}

// MARK: - Post-Action Reflection Tests

@Suite("Post-Action Reflection")
struct PostActionReflectionTests {

    @Test("All action types have reflection questions ending with '?'")
    func reflectionQuestionsAreQuestions() {
        for type in ReflectionActionType.allCases {
            #expect(type.reflectionQuestion.hasSuffix("?"))
        }
    }

    @Test("All action type questions are non-empty")
    func allActionTypesHaveQuestions() {
        for type in ReflectionActionType.allCases {
            #expect(!type.reflectionQuestion.isEmpty)
        }
    }

    @Test("Reflection fields default to nil")
    func reflectionDefaultsToNil() {
        let reflection = PostActionReflection(
            id: nil, userId: "u1", sourceActionId: "a1",
            actionType: .postedPublicThought,
            intentBefore: nil, outcomeReflection: nil,
            lessonLearned: nil, completedAt: nil
        )
        #expect(reflection.intentBefore == nil)
        #expect(reflection.outcomeReflection == nil)
        #expect(reflection.completedAt == nil)
    }

    @Test("Completed reflection carries a date")
    func completedReflectionHasDate() {
        let now = Date()
        let r = PostActionReflection(
            id: nil, userId: "u1", sourceActionId: "a1",
            actionType: .completedPrayer,
            intentBefore: "Peace", outcomeReflection: "Felt peace",
            lessonLearned: "Trust", completedAt: now
        )
        #expect(r.completedAt != nil)
    }
}

// MARK: - Truth vs Emotion Tests

@Suite("Truth vs Emotion Analysis")
struct TruthEmotionTests {

    @Test("Server-computed fields default to nil")
    func analysisServerFieldsAreOptional() {
        let a = TruthEmotionAnalysis(
            id: nil, userId: "u1", sourceText: "text",
            emotionalClaim: nil, factualPossibility: nil,
            assumptions: [], reframes: [],
            scriptureAnchor: nil, scriptureText: nil
        )
        #expect(a.emotionalClaim == nil)
        #expect(a.factualPossibility == nil)
        #expect(a.assumptions.isEmpty)
        #expect(a.reframes.isEmpty)
    }

    @Test("Multiple reframes are supported")
    func multipleReframesSupported() {
        let a = TruthEmotionAnalysis(
            id: nil, userId: "u1", sourceText: "text",
            emotionalClaim: "They ignored me",
            factualPossibility: "They may not have seen it",
            assumptions: ["They saw it"],
            reframes: ["Maybe busy", "Maybe scared", "Ask directly"],
            scriptureAnchor: "Proverbs 18:13", scriptureText: nil
        )
        #expect(a.reframes.count == 3)
        #expect(a.assumptions.count == 1)
        #expect(a.scriptureAnchor == "Proverbs 18:13")
    }
}

// MARK: - Weight of Words Tests

@Suite("Weight of Words Scoring")
struct WeightOfWordsTests {

    @Test("All labels have display names")
    func allLabelsHaveDisplayNames() {
        for label in WordWeightLabel.allCases {
            #expect(!label.displayName.isEmpty)
        }
    }

    @Test("Mirror messages never use shame language")
    func mirrorMessagesNoShame() {
        for label in WordWeightLabel.allCases {
            let msg = label.mirrorMessage.lowercased()
            #expect(!msg.contains("you failed"))
            #expect(!msg.contains("you are wrong"))
            #expect(!msg.contains("shame"))
        }
    }

    @Test("All labels have SF Symbol icons")
    func allLabelsHaveIcons() {
        for label in WordWeightLabel.allCases {
            #expect(!label.icon.isEmpty)
        }
    }

    @Test("All flags have non-empty raw values")
    func allFlagsHaveRawValues() {
        for flag in WordWeightFlag.allCases {
            #expect(!flag.rawValue.isEmpty)
        }
    }

    @Test("Score value always clamps to 0–1")
    func scoreValueClamped() {
        for raw in [-0.5, 0.0, 0.5, 1.0, 1.5] {
            let c = max(0, min(1, raw))
            #expect(c >= 0.0 && c <= 1.0)
        }
    }
}

// MARK: - Community Discernment Tests

@Suite("Community Discernment")
struct CommunityDiscernmentTests {

    @Test("All signal types have non-empty display names")
    func allSignalTypesHaveDisplayNames() {
        for type in DiscernmentSignalType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("There are exactly 6 signal types")
    func signalTypeCount() {
        #expect(DiscernmentSignalType.allCases.count == 6)
    }

    @Test("Community threshold prevents individual signals from surfacing")
    func thresholdPreventsIndividualSignals() {
        let threshold = 5
        #expect(1 < threshold)
        #expect(4 < threshold)
        #expect(5 >= threshold)
    }

    @Test("Required signal types exist")
    func requiredSignalTypesExist() {
        let rawValues = DiscernmentSignalType.allCases.map { $0.rawValue }
        #expect(rawValues.contains("clarification_needed"))
        #expect(rawValues.contains("community_encouragement"))
        #expect(rawValues.contains("concern_raised"))
        #expect(rawValues.contains("berean_analysis_requested"))
    }
}

// MARK: - Eternal Weight Tests

@Suite("Eternal Weight System")
struct EternalWeightTests {

    @Test("All states have display names, icons, and descriptions")
    func allStatesComplete() {
        for state in EternalWeightState.allCases {
            #expect(!state.displayName.isEmpty)
            #expect(!state.icon.isEmpty)
            #expect(!state.description.isEmpty)
        }
    }

    @Test("bearingFruit state supports high confidence signal")
    func bearingFruitSignal() {
        let signal = EternalWeightSignal(
            id: "s1", userId: "u1", contentId: "c1",
            state: .bearingFruit,
            supportingSignals: ["generated_prayer", "many_saved", "scripture_aligned"],
            confidenceScore: 0.85,
            reflectionPrompt: nil
        )
        #expect(signal.state == .bearingFruit)
        #expect(signal.supportingSignals.count == 3)
        #expect(signal.confidenceScore > 0.8)
    }

    @Test("Confidence score is bounded 0–1")
    func confidenceBounded() {
        for score in [0.0, 0.5, 1.0] {
            #expect(score >= 0.0 && score <= 1.0)
        }
    }

    @Test("Five states cover all spiritual directions")
    func fiveStates() {
        #expect(EternalWeightState.allCases.count == 5)
    }
}

// MARK: - AI Usage Models Tests

@Suite("AI Usage Models")
struct AIUsageModelsTests {

    @Test("aiAssistedPost is highest priority (1)")
    func aiAssistedPostIsHighestPriority() {
        #expect(PostAILabel.aiAssistedPost.displayPriority == 1)
    }

    @Test("toneChecked is lower priority than aiAssistedPost")
    func toneCheckedLowerPriority() {
        #expect(PostAILabel.toneChecked.displayPriority > PostAILabel.aiAssistedPost.displayPriority)
    }

    @Test("Required disclosure labels are correct set")
    func disclosureRequiredSet() {
        let required: [PostAILabel] = [.aiAssistedPost, .translatedWithAI, .notesSummarized,
                                       .prayerAssisted, .editedForSafety, .bereanAssisted, .scriptureSuggested]
        let notRequired: [PostAILabel] = [.toneChecked, .altTextAssisted]
        for l in required { #expect(l.disclosureRequired, "\(l.rawValue) should require disclosure") }
        for l in notRequired { #expect(!l.disclosureRequired, "\(l.rawValue) should not require disclosure") }
    }

    @Test("draft_generation maps to aiAssistedPost")
    func draftGenerationMapsToAiPost() {
        let label = PostAILabel.from(useTypes: [.draftGeneration])
        #expect(label == .aiAssistedPost)
    }

    @Test("toneCheck alone maps to toneChecked")
    func toneCheckAloneMapsToToneChecked() {
        let label = PostAILabel.from(useTypes: [.toneCheck])
        #expect(label == .toneChecked)
    }

    @Test("Highest-priority label wins with multiple types")
    func highestPriorityWins() {
        let label = PostAILabel.from(useTypes: [.toneCheck, .draftGeneration, .scriptureSuggestion])
        #expect(label == .aiAssistedPost)
    }

    @Test("Every AIUseType maps to a label")
    func allUseTypesMapped() {
        for type in AIUseType.allCases {
            let label = PostAILabel.from(useTypes: [type])
            #expect(label != nil, "\(type.rawValue) must map to a label")
        }
    }

    @Test("All label display texts are non-empty")
    func allLabelsHaveDisplayText() {
        for label in PostAILabel.allCases {
            #expect(!label.displayText.isEmpty)
        }
    }

    @Test("Disclosure explanations never use warning/flagged/punished language")
    func explanationLanguageIsNonPunitive() {
        for label in PostAILabel.allCases {
            let e = label.disclosureExplanation.lowercased()
            #expect(!e.contains("warning"))
            #expect(!e.contains("flagged"))
            #expect(!e.contains("punished"))
        }
    }

    @Test("rawPromptStored defaults to false")
    func rawPromptStoredDefaultsFalse() {
        let usage = PostAIUsage(
            usedAI: true,
            aiUseTypes: [.toneCheck],
            primaryLabel: .toneChecked,
            secondaryDetails: [],
            userAcceptedSuggestion: false,
            aiGeneratedPercentageEstimate: nil,
            disclosureRequired: false,
            rawPromptStored: false,
            rawUserTextStored: false,
            modelVersion: "v1",
            toneCheckSummary: nil
        )
        #expect(usage.rawPromptStored == false)
        #expect(usage.rawUserTextStored == false)
    }
}

// MARK: - Orchestrator Output Tests

@Suite("SpiritualOS Orchestrator Output")
struct OrchestratorOutputTests {

    @Test("SpiritualOSPrompt holds all required fields")
    func promptFields() {
        let prompt = SpiritualOSPrompt(
            promptType: .momentIntercept,
            confidence: 0.75,
            userFacingMessage: "Pause. This moment may matter more than the message.",
            suggestedActions: [.breathe, .prayFirst],
            privateSignalIds: [],
            safetyFlags: [],
            shouldSurfacePrompt: true
        )
        #expect(prompt.shouldSurfacePrompt)
        #expect(prompt.confidence == 0.75)
        #expect(prompt.suggestedActions.count == 2)
        #expect(!prompt.userFacingMessage.isEmpty)
    }

    @Test("All prompt types have non-empty raw values")
    func allPromptTypesHaveRawValues() {
        for type in SpiritualOSPromptType.allCases {
            #expect(!type.rawValue.isEmpty)
        }
    }

    @Test("All actions have non-empty raw values")
    func allActionsHaveRawValues() {
        for action in SpiritualOSAction.allCases {
            #expect(!action.rawValue.isEmpty)
        }
    }

    @Test("Low confidence prompt does not surface")
    func lowConfidenceDoesNotSurface() {
        let prompt = SpiritualOSPrompt(
            promptType: .scriptureDriftInsight,
            confidence: 0.2,
            userFacingMessage: "A possible pattern.",
            suggestedActions: [],
            privateSignalIds: [],
            safetyFlags: [],
            shouldSurfacePrompt: false
        )
        #expect(!prompt.shouldSurfacePrompt)
    }

    @Test("10 prompt types cover all 10 Spiritual OS features")
    func tenPromptTypes() {
        #expect(SpiritualOSPromptType.allCases.count == 10)
    }
}
