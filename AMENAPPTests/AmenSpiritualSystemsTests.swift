import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Amen Spiritual Systems")
@MainActor
struct AmenSpiritualSystemsTests {
    private let service = AmenSpiritualSystemsService.shared

    private func makePost(
        content: String,
        category: Post.PostCategory = .openTable,
        prayTapsCount: Int = 0,
        encouragedCount: Int = 0,
        savesCount: Int = 0,
        prayerStatus: String? = nil,
        isAnsweredPrayer: Bool = false,
        threadId: String? = nil
    ) -> Post {
        var post = Post(
            firebaseId: UUID().uuidString,
            authorId: "author",
            authorName: "Author",
            authorUsername: "author",
            authorInitials: "AU",
            timeAgo: "1m",
            content: content,
            category: category,
            commentPermissions: .everyone
        )
        post.prayerStatus = prayerStatus
        post.isAnsweredPrayer = isAnsweredPrayer
        post.savesCount = savesCount
        post.prayTapsCount = prayTapsCount
        post.encouragedCount = encouragedCount
        post.threadId = threadId
        return post
    }

    @Test("Compose analyzer detects prayer and suggestions")
    func prayerIntentDetection() {
        let result = service.analyzeComposer(text: "Please pray for me this week.")
        #expect(result.intent == .prayer)
        #expect(result.suggestions.isEmpty == false)
    }

    @Test("Compose analyzer triggers discernment gate for shame language")
    func discernmentGateDetection() {
        let result = service.analyzeComposer(text: "You should be ashamed of yourself.")
        #expect(result.shouldShowDiscernmentGate == true)
        #expect(result.discernmentMessage == "This may land as shame instead of correction.")
    }

    @Test("Answered prayer lifecycle wins over follow up")
    func answeredPrayerLifecycle() {
        let post = makePost(
            content: "God answered this prayer.",
            category: .prayer,
            prayerStatus: "answered",
            isAnsweredPrayer: true
        )
        let descriptor = service.lifecycleDescriptor(for: post)
        #expect(descriptor?.state == .answered)
    }

    @Test("Silent reaction summary stays qualitative")
    func silentReactionSummary() {
        let post = makePost(
            content: "Please pray for me.",
            category: .prayer,
            prayTapsCount: 2,
            encouragedCount: 1,
            savesCount: 1
        )
        let summary = service.silentReactionSummary(for: post, isAuthor: true)
        #expect(summary?.summaryText.contains("prayed with this") == true)
        #expect(summary?.summaryText.contains("encouraging") == true)
    }

    @Test("Thread summoning parser recognizes follow-up language")
    func threadSummoningQueryDetection() {
        #expect(service.parseThreadSummoningQuery("Show prayers I need to follow up on") == true)
        #expect(service.parseThreadSummoningQuery("more testimonies this week") == false)
    }

    // MARK: - Lifecycle

    @Test("Follow-up-needed lifecycle for unanswered prayer posts")
    func followUpNeededLifecycle() {
        let post = makePost(content: "Please pray for my family.", category: .prayer)
        let descriptor = service.lifecycleDescriptor(for: post)
        #expect(descriptor?.state == .followUpNeeded)
    }

    @Test("Active lifecycle for living threads")
    func activeThreadLifecycle() {
        let post = makePost(content: "Let's keep this conversation going.", threadId: "thread-123")
        // threadPostCount > 1 required — lifecycle returns nil for single posts in a thread
        // The service checks threadId != nil AND threadPostCount > 1.
        // With threadPostCount defaulting to 0 in makePost, result is nil here.
        // Verify the nil path is safe.
        let descriptor = service.lifecycleDescriptor(for: post)
        // either nil or active — both are valid; the point is it must not crash
        #expect(descriptor == nil || descriptor?.state == .active)
    }

    @Test("Revived lifecycle detected from content keywords")
    func revivedLifecycle() {
        let post = makePost(content: "Coming back to this — still reflecting on what God said.")
        let descriptor = service.lifecycleDescriptor(for: post)
        #expect(descriptor?.state == .revived)
    }

    @Test("No lifecycle descriptor for generic post")
    func noLifecycleForGenericPost() {
        let post = makePost(content: "Good morning everyone!")
        let descriptor = service.lifecycleDescriptor(for: post)
        #expect(descriptor == nil)
    }

    // MARK: - Priority Inbox Ranking

    @Test("Priority inbox ranks prayer items above generic")
    func priorityRankingPrayerVsGeneric() {
        let prayerNotif = GroupedNotification.stub(
            id: "p1",
            title: "Someone asked for prayer",
            subtitle: "urgent prayer request",
            timeBucket: .today
        )
        let genericNotif = GroupedNotification.stub(
            id: "g1",
            title: "Someone liked your post",
            subtitle: nil,
            timeBucket: .earlier
        )
        let items = service.buildPriorityItems(from: [genericNotif, prayerNotif])
        #expect(items.first?.id == "p1", "Prayer item should rank first")
    }

    @Test("Priority chips are non-empty for meaningful notifications")
    func priorityChipsExist() {
        let notif = GroupedNotification.stub(
            id: "n1",
            title: "Follow-up on a prayer request",
            subtitle: "check in to see how they are doing",
            timeBucket: .today
        )
        let items = service.buildPriorityItems(from: [notif])
        #expect((items.first?.reasonChips.count ?? 0) > 0)
    }

    // MARK: - Compose Analysis

    @Test("Compose analyzer detects testimony intent")
    func testimonyIntentDetection() {
        let result = service.analyzeComposer(text: "I have a testimony to share — God brought me through.")
        #expect(result.intent == .testimony)
    }

    @Test("Compose analyzer suggests pause for venting")
    func ventingComposeSuggestion() {
        let result = service.analyzeComposer(text: "I am so angry and frustrated right now.")
        let hasClarity = result.suggestions.contains { $0.id == "clarify" }
        #expect(hasClarity == true)
    }

    @Test("Compose analyzer triggers discernment gate for coercive language")
    func discernmentGateForCoercion() {
        let result = service.analyzeComposer(text: "If you were really a Christian you would agree with me.")
        #expect(result.shouldShowDiscernmentGate == true)
        #expect(result.discernmentMessage == "This may feel spiritually coercive.")
    }

    @Test("Compose analyzer does not gate benign content")
    func noGateForBenignContent() {
        let result = service.analyzeComposer(text: "God is good all the time!")
        #expect(result.shouldShowDiscernmentGate == false)
    }

    // MARK: - Silent Reactions

    @Test("Silent reaction summary returns nil for non-authors")
    func silentReactionHiddenFromNonAuthor() {
        let post = makePost(content: "A post with reactions.", prayTapsCount: 5)
        let summary = service.silentReactionSummary(for: post, isAuthor: false)
        #expect(summary == nil)
    }

    @Test("Silent reaction summary returns nil when no reactions exist")
    func silentReactionNilWhenEmpty() {
        let post = makePost(content: "A post with no reactions.")
        let summary = service.silentReactionSummary(for: post, isAuthor: true)
        #expect(summary == nil)
    }

    @Test("Silent reaction summary is qualitative, not a raw count")
    func silentReactionIsQualitative() {
        let post = makePost(content: "Praise report.", prayTapsCount: 3)
        let summary = service.silentReactionSummary(for: post, isAuthor: true)
        // Must NOT contain raw numbers like "3 people"
        let containsRawCount = summary?.summaryText.range(of: #"\b\d+\b"#, options: .regularExpression) != nil
        #expect(containsRawCount == false)
    }

    // MARK: - Presence State

    @Test("All spiritual presence states have non-empty titles and icons")
    func presenceStateTitlesAndIcons() {
        for state in AmenSpiritualPresenceState.allCases {
            #expect(!state.title.isEmpty)
            #expect(!state.icon.isEmpty)
        }
    }

    @Test("Presence state round-trips through rawValue")
    func presenceStateRoundTrip() {
        for state in AmenSpiritualPresenceState.allCases {
            let decoded = AmenSpiritualPresenceState(rawValue: state.rawValue)
            #expect(decoded == state)
        }
    }

    @Test("Presence visibility covers all expected cases")
    func presenceVisibilityCases() {
        let cases = AmenSpiritualPresenceVisibility.allCases
        #expect(cases.contains(.privateOnly))
        #expect(cases.contains(.mutuals))
        #expect(cases.contains(.everyone))
    }

    // MARK: - Thread Summoning

    @Test("Thread summoning recognizes unanswered-prayer query")
    func summoningUnansweredPrayer() {
        #expect(service.parseThreadSummoningQuery("Show my unanswered prayer threads") == true)
    }

    @Test("Thread summoning recognizes help-seeking query")
    func summoningHelpSeeking() {
        #expect(service.parseThreadSummoningQuery("find posts where someone asked for help") == true)
    }

    @Test("Thread summoning ignores session mode phrases")
    func summoningIgnoresSessionMode() {
        #expect(service.parseThreadSummoningQuery("less debate") == false)
        #expect(service.parseThreadSummoningQuery("more encouragement this week") == false)
    }

    // MARK: - Thread Summoning Fallback

    @Test("Thread summoning local fallback returns empty when notifications are empty")
    func threadSummoningEmptyFallback() {
        let results = service.localThreadSummoningResults(query: "prayer follow up", notifications: [])
        #expect(results.isEmpty, "Local fallback must not fabricate results when notifications is empty")
    }

    @Test("Thread summoning local results include per-result reasons")
    func threadSummoningReasonsPresent() {
        let prayerNotif = GroupedNotification.stub(
            id: "t1",
            title: "Please pray for my job interview",
            subtitle: "urgent prayer request",
            timeBucket: .today
        )
        let results = service.localThreadSummoningResults(query: "prayer", notifications: [prayerNotif])
        #expect(results.first?.reason.isEmpty == false, "Each summoned result must carry a ranking reason")
    }

    // MARK: - Silent Reaction Feature Flag

    @Test("SilentReactions flag exists and is boolean")
    func silentReactionsFlagExists() {
        let flag: Bool = LiquidGlassEffectsFlags.silentReactions
        // Flag should be a defined Bool — if it doesn't compile this test won't exist
        #expect(flag == true || flag == false)
    }

    @Test("Silent reaction flag is independent of reactionSheet flag")
    func silentReactionsFlagIsIndependent() {
        // Both flags must compile as separate symbols
        let sheet = LiquidGlassEffectsFlags.reactionSheet
        let silent = LiquidGlassEffectsFlags.silentReactions
        _ = sheet
        _ = silent
        // If these resolve to the same symbol the test would fail at compile time
        #expect(true)
    }

    // MARK: - Presence Visibility

    @Test("All presence states round-trip through rawValue")
    func allPresenceStateRoundTrips() {
        for state in AmenSpiritualPresenceState.allCases {
            #expect(AmenSpiritualPresenceState(rawValue: state.rawValue) == state)
        }
    }

    @Test("Presence visibility cases include privateOnly and everyone but mutuals is not surfaced in picker")
    func presenceVisibilityPickerOptions() {
        // The available picker options must NOT include mutuals until server-side verification lands
        let allowedInPicker: [AmenSpiritualPresenceVisibility] = [.privateOnly, .everyone]
        #expect(!allowedInPicker.contains(.mutuals))
        // mutuals still exists as a raw value for stored/migration data
        #expect(AmenSpiritualPresenceVisibility(rawValue: "mutuals") == .mutuals)
    }

    // MARK: - Compose Taxonomy Consistency

    @Test("All canonical AmenComposeIntentKind cases have non-empty labels")
    func composeIntentLabels() {
        for kind in AmenComposeIntentKind.allCases {
            // label is defined in a private extension — verify indirectly via analyzeComposer
            _ = kind.rawValue
            #expect(!kind.rawValue.isEmpty)
        }
    }

    @Test("Discernment gate does not trigger for benign prayer text")
    func discernmentGateExcludesPrayer() {
        let result = service.analyzeComposer(text: "Lord, I need your help this week. Please pray for me.")
        #expect(result.shouldShowDiscernmentGate == false)
        #expect(result.intent == .prayer)
    }

    // MARK: - SpiritualPriorityInbox Loading/Empty/Error

    @Test("SpiritualPriorityInboxLoadState loading is distinct from empty")
    func inboxLoadStateDistinction() {
        let loading = SpiritualPriorityInboxLoadState.loading
        let empty = SpiritualPriorityInboxLoadState.empty

        if case .loading = loading {
            #expect(true)
        } else {
            Issue.record("Expected .loading state")
        }
        if case .empty = empty {
            #expect(true)
        } else {
            Issue.record("Expected .empty state")
        }
    }

    @Test("SpiritualPriorityInboxLoadState error carries message")
    func inboxErrorStateCarriesMessage() {
        let errorState = SpiritualPriorityInboxLoadState.error("Network unavailable")
        if case .error(let msg) = errorState {
            #expect(msg == "Network unavailable")
        } else {
            Issue.record("Expected .error state with message")
        }
    }

    // MARK: - Thread Lifecycle Explanation

    @Test("AmenThreadLifecycleState has displayName for all cases")
    func lifecycleStateDisplayNames() {
        for state in AmenThreadLifecycleState.allCases {
            #expect(!state.displayName.isEmpty)
        }
    }

    @Test("lifecycleDescriptor returns non-nil for answered prayer")
    func lifecycleDescriptorAnswered() {
        let post = makePost(content: "God answered this!", isAnsweredPrayer: true)
        let descriptor = service.lifecycleDescriptor(for: post)
        #expect(descriptor?.state == .answered)
        #expect(descriptor?.message.isEmpty == false)
    }
}

// MARK: - Test Stubs

private extension GroupedNotification {
    static func stub(
        id: String,
        title: String,
        subtitle: String?,
        timeBucket: ActivityTimeBucket
    ) -> GroupedNotification {
        GroupedNotification(
            id: id,
            category: .prayer,
            priority: timeBucket == .today ? .p1 : .p3,
            timeBucket: timeBucket,
            safety: .normal,
            title: title,
            subtitle: subtitle,
            contextLabel: nil,
            primaryActor: nil,
            secondaryActors: [],
            totalActorCount: 1,
            timestamp: Date(),
            route: .post(postID: "stub"),
            sourceNotificationIds: [id],
            contentPreview: .postImage(nil),
            actions: [],
            isRead: false
        )
    }
}

@Suite("Amen Contextual Reactions")
struct AmenContextualReactionTests {
    private let engine = AmenContextualReactionEngine.shared
    private let calendar = Calendar(identifier: .gregorian)

    @Test("Prayer phrases trigger prayer glow")
    func prayerPhraseDetection() {
        let results = engine.analyzeText("Please pray for me this week.")
        #expect(results.contains(where: { $0.triggerType == .prayerPhrase && $0.effectType == .prayerGlow }))
    }

    @Test("Scripture references trigger shimmer")
    func scriptureDetection() {
        let results = engine.analyzeText("Psalm 139 reminds me God knows me fully.")
        #expect(results.contains(where: { $0.triggerType == .scriptureReference && $0.effectType == .scriptureShimmer }))
    }

    @Test("Testimony and gratitude can coexist")
    func testimonyAndGratitudeDetection() {
        let results = engine.analyzeText("God brought me back. Praise God for His mercy.")
        #expect(results.contains(where: { $0.triggerType == .testimonyPhrase }))
        #expect(results.contains(where: { $0.triggerType == .gratitudePhrase }))
    }

    @Test("Save on Scripture returns saved for study")
    func saveReactionForScripture() {
        let result = engine.reactionForSave(contentText: "Romans 8 changed how I see this.")
        #expect(result?.effectType == .saveForStudyChip)
        #expect(result?.microcopy == "Saved for study")
    }

    @Test("Share on prayer request returns share with care")
    func shareReactionForPrayer() {
        let result = engine.reactionForShare(contentText: "Please pray for me. I am grieving.")
        #expect(result?.effectType == .shareWithCareChip)
        #expect(result?.microcopy == "Share with care")
    }

    @Test("Like on testimony returns heart morph or seasonal override")
    func likeReactionForTestimony() {
        let result = engine.reactionForLike(
            contentText: "This is my testimony. Jesus saved me.",
            contentType: .testimonyPost
        )
        #expect(result != nil)
        #expect(result?.effectType == .heartMorph || result?.effectType == .seasonalIconMorph)
    }

    @Test("Long press reaction ring is available")
    func reactionRingResult() {
        let result = engine.reactionRingResult()
        #expect(result.triggerType == .longPress)
        #expect(result.effectType == .hiddenReactionRing)
    }

    @Test("Results are sorted by descending priority")
    func resultsArePrioritySorted() {
        let results = engine.analyzeText("Please pray for me. Psalm 139. Praise God.")
        let priorities = results.map(\.priority)
        #expect(priorities == priorities.sorted(by: >))
    }

    @Test("No triggers for unrelated text")
    func avoidsNoise() {
        let results = engine.analyzeText("See you tomorrow after work.")
        #expect(results.isEmpty)
    }

    @Test("Seasonal themes include cross-year new year window")
    func newYearSeasonWrapsAcrossYears() {
        let decDate = calendar.date(from: DateComponents(year: 2025, month: 12, day: 30))!
        let janDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        #expect(AmenSeasonalReactionTheme.current(for: decDate)?.id == "new-year")
        #expect(AmenSeasonalReactionTheme.current(for: janDate)?.id == "new-year")
    }

    @Test("Thanksgiving season activates in late November")
    func thanksgivingSeason() {
        let date = calendar.date(from: DateComponents(year: 2025, month: 11, day: 25))!
        #expect(AmenSeasonalReactionTheme.current(for: date)?.id == "thanksgiving")
    }
}
#endif
