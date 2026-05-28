import Foundation
import Testing
@testable import AMENAPP

@Suite("Amen Spaces Discussion Discovery")
struct AmenSpacesDiscussionDiscoveryTests {
    @Test("Discovery excludes private unauthorized discussions")
    func excludesPrivateUnauthorizedDiscussions() {
        let privateItem = item(visibility: .privateRestricted, joinPolicy: .inviteOnly)
        let filters = AmenSpacesDiscussionFilters()

        let result = filters.apply(to: [privateItem], context: .guest)

        #expect(result.isEmpty)
    }

    @Test("Paid discussion shows paid gate and does not leak preview")
    func paidDiscussionShowsGateWithoutPreviewLeak() {
        let paid = item(
            title: "Paid Mentor Circle",
            descriptionPreview: "Restricted salary negotiation details",
            visibility: .paidMemberOnly,
            joinPolicy: .paidOnly,
            requiresTier: "mentor-circle"
        )

        #expect(paid.accessAction(in: .guest) == .join)
        #expect(!paid.preview(in: .guest).contains("Restricted salary"))
        #expect(paid.preview(in: .guest).contains("Member-only"))
    }

    @Test("Confidential discussion does not leak preview")
    func confidentialDiscussionDoesNotLeakPreview() {
        let confidential = item(
            title: "Care Team Review",
            descriptionPreview: "Private pastoral care names",
            visibility: .confidential,
            joinPolicy: .roleRestricted,
            isConfidential: true
        )

        #expect(confidential.canSurface(in: .guest) == false)
        #expect(!confidential.preview(in: .guest).contains("Private pastoral care"))
    }

    @Test("Youth-protected discussion hidden unless permitted")
    func youthProtectedDiscussionHiddenUnlessPermitted() {
        let youth = item(visibility: .youthProtected, isYouthProtected: true)
        var context = AmenSpacesDiscussionAccessContext.guest

        #expect(youth.canSurface(in: context) == false)
        context.canAccessYouthProtected = true
        #expect(youth.canSurface(in: context) == true)
    }

    @Test("Join button states map from access policy")
    func joinButtonStatesMapFromAccessPolicy() {
        #expect(item(joinPolicy: .open).accessAction(in: .guest) == .join)
        #expect(item(joinPolicy: .requestRequired).accessAction(in: .guest) == .request)
        #expect(item(joinPolicy: .readOnly).accessAction(in: .guest) == .view)
        #expect(item(joinPolicy: .open, membershipStatus: .joined).accessAction(in: .guest) == .joined)
        #expect(item(joinPolicy: .open, membershipStatus: .requested).accessAction(in: .guest) == .request)
    }

    @Test("Reported or under-review discussions are hidden or disabled")
    func reportedOrUnderReviewDiscussionsAreHidden() {
        let reported = item(isReportedByViewer: true)
        let underReview = item(moderationStatus: .underReview)
        let blocked = item(safetyStatus: .blocked)

        let result = AmenSpacesDiscussionFilters().apply(to: [reported, underReview, blocked], context: .guest)

        #expect(result.isEmpty)
    }

    @Test("Recommendation reason does not include restricted content")
    func recommendationReasonDoesNotLeakRestrictedContent() {
        let confidential = item(
            visibility: .confidential,
            isConfidential: true,
            recommendationReason: "Because of a private care report"
        )

        #expect(confidential.recommendationReason(in: .guest) == nil)
    }

    @Test("Category filtering and search query work")
    func categoryFilteringAndSearchQueryWork() {
        let career = item(title: "Career Circle: Internships", category: .career, tags: ["Internships"])
        let bible = item(title: "Romans 8 Discussion", category: .bibleStudy, tags: ["Bible"])
        let filters = AmenSpacesDiscussionFilters(selectedCategory: .career, searchQuery: "intern")

        let result = filters.apply(to: [career, bible], context: .guest)

        #expect(result.map(\.id) == [career.id])
    }

    @Test("Hero banner chooses safe trending data")
    func heroBannerChoosesSafeTrendingData() {
        let unsafe = item(id: "unsafe", title: "Unsafe", trendingScore: 100, safetyStatus: .needsReview)
        let safe = item(id: "safe", title: "Safe", trendingScore: 90, isLive: true)

        let hero = AmenSpacesDiscussionDiscoveryService.heroItem(from: [unsafe, safe], context: .guest)

        #expect(hero?.id == "safe")
    }

    @Test("Cloud Function contracts cover discovery actions")
    func cloudFunctionContractsCoverDiscoveryActions() {
        let names = Set(AmenSpacesDiscussionDiscoveryService.callableContracts.map(\.rawValue))

        #expect(names.contains("generateAmenSpacesDiscovery"))
        #expect(names.contains("joinAmenSpaceDiscussion"))
        #expect(names.contains("requestAmenSpaceDiscussionAccess"))
        #expect(names.contains("leaveAmenSpaceDiscussion"))
        #expect(names.contains("reportAmenSpaceDiscussion"))
        #expect(names.contains("saveAmenSpaceDiscussion"))
        #expect(names.contains("muteAmenSpaceDiscussion"))
        #expect(names.contains("rankAmenSpacesDiscussions"))
        #expect(names.contains("moderateAmenSpacesDiscussionPreview"))
    }

    @Test("Amen Spaces discovery does not model global bottom tabs")
    func noGlobalBottomTabChanges() {
        let categories = AmenSpacesDiscussionCategory.allCases.map(\.rawValue)

        #expect(categories.contains("Churches"))
        #expect(categories.contains("Live Now"))
        #expect(!categories.contains("Home"))
        #expect(!categories.contains("Resources"))
        #expect(!categories.contains("Feed"))
    }

    @Test("Editorial banner contracts cover backend sizing and routing")
    func editorialBannerContractsCoverBackendSizingAndRouting() {
        let names = Set(AmenSpaceBannerService.callableContracts.map(\.rawValue))

        #expect(names.contains("resolveBannerRail"))
        #expect(names.contains("getAmenSpaceBanners"))
        #expect(names.contains("setAmenSpaceBannerDisplayPreference"))
        #expect(names.contains("setAmenSpaceDefaultBannerSize"))
        #expect(names.contains("logAmenSpaceBannerEvent"))
        #expect(names.contains("validateAmenSpaceBannerCTA"))
    }

    @Test("Editorial banner rail removes duplicate target routes")
    func editorialBannerRailRemovesDuplicateTargetRoutes() {
        let first = banner(id: "first", targetRoute: "selah://space/space-1")
        let duplicate = banner(id: "duplicate", targetRoute: "selah://space/space-1")
        let unique = banner(id: "unique", targetRoute: "selah://event/event-1/rsvp")

        let result = AmenSpaceBannerRailViewModel.deduplicated([first, duplicate, unique])

        #expect(result.map(\.id) == ["first", "unique"])
    }

    @Test("All editorial banner sizes are supported")
    func allEditorialBannerSizesAreSupported() {
        #expect(AmenSpaceBannerSize.allCases.map(\.rawValue) == ["compact", "standard", "large", "hero"])
        #expect(AmenSpaceBannerSurface.spacesHome.defaultSize == .standard)
        #expect(AmenSpaceBannerSurface.homeFeed.defaultSize == .compact)
    }

    @Test("Editorial banner size resolution honors user server surface fallback order")
    func editorialBannerSizeResolutionHonorsFallbackOrder() {
        #expect(AmenSpaceBannerRailViewModel.resolvedSize(userPreference: .hero, serverResolvedSize: .compact, surfaceDefault: .standard) == .hero)
        #expect(AmenSpaceBannerRailViewModel.resolvedSize(userPreference: nil, serverResolvedSize: .large, surfaceDefault: .standard) == .large)
        #expect(AmenSpaceBannerRailViewModel.resolvedSize(userPreference: nil, serverResolvedSize: nil, surfaceDefault: .compact) == .compact)
    }

    @Test("Editorial banner analytics events cover impression tap dismissal completion and hidden reasons")
    func editorialBannerAnalyticsEventsCoverRequiredLifecycle() {
        let events = Set(AmenSpaceBannerAnalyticsEvent.allCases.map(\.rawValue))

        #expect(events.contains("banner_impression"))
        #expect(events.contains("banner_tap"))
        #expect(events.contains("banner_dismiss"))
        #expect(events.contains("banner_cta_complete"))
        #expect(events.contains("banner_hidden_reason"))
    }

    @Test("Selah banner routes validate all CTA actions before render")
    func selahBannerRoutesValidateAllCTAActionsBeforeRender() {
        #expect(AmenSpaceBannerRoute(route: "selah://group/group-1", cta: .join) == .joinGroup(id: "group-1"))
        #expect(AmenSpaceBannerRoute(route: "selah://event/event-1/rsvp", cta: .rsvp) == .rsvpEvent(id: "event-1"))
        #expect(AmenSpaceBannerRoute(route: "selah://job/job-1/apply", cta: .apply) == .applyJob(id: "job-1"))
        #expect(AmenSpaceBannerRoute(route: "selah://space/space-1", cta: .open) == .openSpace(id: "space-1"))
        #expect(AmenSpaceBannerRoute(route: "selah://prayer/prayer-1", cta: .pray) == .pray(id: "prayer-1"))
        #expect(AmenSpaceBannerRoute(route: "selah://sermon/sermon-1", cta: .watch) == .watchSermon(id: "sermon-1"))
        #expect(AmenSpaceBannerRoute(route: "amen://spaces/space-1", cta: .open) == nil)
        #expect(AmenSpaceBannerRoute(route: "selah://event/event-1", cta: .rsvp) == nil)
        #expect(AmenSpaceBannerRoute(route: "selah://space/space-1?utm=1", cta: .open) == nil)
    }

    @Test("Editorial banner surfaces cover approved rollout placements")
    func editorialBannerSurfacesCoverApprovedRolloutPlacements() {
        let surfaces = Set(AmenSpaceBannerSurface.allCases.map(\.rawValue))

        #expect(surfaces.contains("spacesHome"))
        #expect(surfaces.contains("spaceDetail"))
        #expect(surfaces.contains("churchProfile"))
        #expect(surfaces.contains("schoolProfile"))
        #expect(surfaces.contains("businessProfile"))
        #expect(surfaces.contains("discovery"))
        #expect(surfaces.contains("events"))
        #expect(surfaces.contains("jobs"))
        #expect(surfaces.contains("messagesRooms"))
        #expect(surfaces.contains("bereanSuggestions"))
        #expect(surfaces.contains("homeFeed"))
        #expect(surfaces.contains("userProfile"))
    }

    @Test("National directory contracts cover schools, churches, organizations, claims, and paid spaces")
    func nationalDirectoryContractsCoverSchoolsChurchesOrganizationsAndPaidSpaces() {
        let callables = Set(AmenNationalDirectoryService.callableContracts.map(\.rawValue))
        let sourceIds = Set(AmenNationalDirectorySourceDescriptor.officialUSSources.map(\.id))

        #expect(callables.contains("searchAmenNationalDirectory"))
        #expect(callables.contains("claimAmenNationalDirectoryProfile"))
        #expect(callables.contains("createAmenSpaceFromDirectoryProfile"))
        #expect(callables.contains("createDirectorySubscriptionCheckout"))
        #expect(callables.contains("createCheckoutSessionForOrganizationPlan"))
        #expect(callables.contains("listOrganizationReviewQueue"))
        #expect(callables.contains("suggestOrganizationEdit"))
        #expect(callables.contains("approveOrganizationEdit"))
        #expect(callables.contains("rejectOrganizationEdit"))
        #expect(callables.contains("updateOrganizationBanner"))
        #expect(callables.contains("moderateOrganizationBanner"))
        #expect(callables.contains("ingestSchoolDirectoryBatch"))
        #expect(callables.contains("ingestNonprofitDirectoryBatch"))
        #expect(callables.contains("ingestDirectoryManifestSource"))
        #expect(callables.contains("geocodeOrganizationBatch"))
        #expect(callables.contains("runCensusGeocoderWorker"))
        #expect(callables.contains("classifyOrganizationType"))
        #expect(callables.contains("getOrganizationDirectoryImportManifest"))
        #expect(callables.contains("scheduledAmenNationalDirectoryImports"))
        #expect(callables.contains("scheduledAmenNationalDirectoryGeocoding"))
        #expect(callables.contains("syncAmenNationalDirectoryToAlgolia"))
        #expect(callables.contains("scheduledAmenNationalDirectoryAlgoliaSync"))
        #expect(sourceIds == [.ncesCCD, .ncesPSS, .ncesIPEDS, .irsEOBMF, .censusGeocoder, .osmStaticExtract])
        #expect(AmenNationalDirectoryKind.publicK12School.organizationType == .school)
        #expect(AmenNationalDirectoryKind.privateK12School.organizationType == .school)
        #expect(AmenNationalDirectoryKind.church.organizationType == .church)
        #expect(AmenNationalDirectoryNormalizer.normalizedName(" St. Mary's   School! ") == "st mary s school")
        #expect(AmenOrganizationSource.googlePlaces.canBeBulkStored == false)
        #expect(Set(AmenSmartNotesMode.allCases).isSuperset(of: [.churchNotes, .schoolNotes, .bibleStudyNotes, .meetingNotes, .sermonNotes, .classNotes, .eventNotes]))
    }

    @Test("Organization identity is module-driven and school is not a user account silo")
    func organizationIdentityIsModuleDrivenAndSchoolIsNotAccountSilo() {
        let accountTypes = Set(AMENAccountType.allCases.map(\.rawValue))
        let school = AmenOrganizationProfile(
            id: "org-school-1",
            type: .school,
            name: "Example School",
            normalizedName: "example school",
            description: nil,
            address: AmenOrganizationAddress(line1: nil, city: "Atlanta", state: "GA", zip: nil, latitude: nil, longitude: nil),
            website: "https://example.edu",
            phone: nil,
            verifiedStatus: "sourceImported",
            claimStatus: .unclaimed,
            source: .ncesCCD,
            sourceId: "1300001",
            sourceUpdatedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            createdBy: nil,
            ownerUid: nil,
            visibility: "public",
            bannerConfig: [:],
            spaceDefaults: [:],
            billing: nil,
            safetyStatus: "allowed",
            modules: [],
            schemaVersion: 1
        )

        #expect(!accountTypes.contains("School"))
        #expect(AmenOrganizationType.school.defaultModules.contains(.schoolNotesPreview))
        #expect(school.effectiveModules.contains(.claimCTA))
        #expect(AmenOrganizationModulePolicy.canRender(.adminTools, for: school, isOwner: false) == false)
    }

    private func banner(id: String, targetRoute: String) -> AmenSpaceBannerItem {
        AmenSpaceBannerItem(
            id: id,
            type: .discussion,
            title: "Join Bible Study",
            subtitle: "Amen Spaces",
            imageURL: nil,
            iconURL: nil,
            spaceId: "space-1",
            targetRoute: targetRoute,
            ctaLabel: .join,
            priority: 10,
            startsAt: nil,
            endsAt: nil,
            location: nil,
            moderationStatus: "approved",
            visibility: "authenticated",
            createdBy: "uid-1",
            trustedContext: "member",
            rankingReason: "Because your trusted community is active",
            resolvedSize: .standard
        )
    }

    private func item(
        id: String = UUID().uuidString,
        title: String = "Open Discussion",
        subtitle: String = "Amen Space",
        descriptionPreview: String = "Safe public preview",
        category: AmenSpacesDiscussionCategory = .all,
        tags: [String] = [],
        visibility: AmenSpacesDiscussionVisibility = .publicOpen,
        joinPolicy: AmenSpacesDiscussionJoinPolicy = .open,
        membershipStatus: AmenSpacesDiscussionMembershipStatus = .notJoined,
        trendingScore: Double = 10,
        safetyStatus: AmenSpacesDiscussionSafetyStatus = .allowed,
        moderationStatus: AmenSpacesDiscussionModerationStatus = .visible,
        isLive: Bool = false,
        isYouthProtected: Bool = false,
        isConfidential: Bool = false,
        requiresTier: String? = nil,
        recommendationReason: String? = nil,
        isReportedByViewer: Bool = false
    ) -> AmenSpacesDiscussionDiscoveryItem {
        AmenSpacesDiscussionDiscoveryItem(
            id: id,
            spaceId: "space-1",
            organizationId: nil,
            sourceType: .organization,
            title: title,
            subtitle: subtitle,
            descriptionPreview: descriptionPreview,
            bannerImageURL: nil,
            avatarURL: nil,
            category: category,
            tags: tags,
            visibility: visibility,
            joinPolicy: joinPolicy,
            membershipStatus: membershipStatus,
            participantCount: 12,
            unreadCount: 0,
            trendingScore: trendingScore,
            safetyStatus: safetyStatus,
            moderationStatus: moderationStatus,
            trustBadges: [.moderated],
            isLive: isLive,
            isVerified: true,
            isYouthProtected: isYouthProtected,
            isConfidential: isConfidential,
            requiresTier: requiresTier,
            createdAt: Date(timeIntervalSince1970: 1),
            lastActivityAt: Date(timeIntervalSince1970: 2),
            recommendationReason: recommendationReason,
            aiSummary: nil,
            deepLink: nil,
            isAIExcluded: false,
            isReportedByViewer: isReportedByViewer,
            approximateRegion: nil
        )
    }
}
