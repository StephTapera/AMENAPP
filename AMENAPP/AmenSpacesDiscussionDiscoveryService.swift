import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum AmenSpacesDiscussionDiscoveryCallable: String, CaseIterable, Identifiable {
    case generateAmenSpacesDiscovery
    case joinAmenSpaceDiscussion
    case requestAmenSpaceDiscussionAccess
    case leaveAmenSpaceDiscussion
    case reportAmenSpaceDiscussion
    case saveAmenSpaceDiscussion
    case muteAmenSpaceDiscussion
    case rankAmenSpacesDiscussions
    case moderateAmenSpacesDiscussionPreview

    var id: String { rawValue }
}

protocol AmenSpacesDiscussionDiscoveryServicing: AnyObject {
    func startListening(onChange: @escaping @MainActor ([AmenSpacesDiscussionDiscoveryItem], [AmenSpacesOrganizationSpotlightItem], Bool) -> Void, onError: @escaping @MainActor (String) -> Void)
    func stopListening()
    func joinAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws
    func requestAmenSpaceDiscussionAccess(_ item: AmenSpacesDiscussionDiscoveryItem) async throws
    func leaveAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws
    func markDiscussionInterested(_ item: AmenSpacesDiscussionDiscoveryItem) async throws
    func reportAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem, reason: String) async throws
    func muteAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws
    func saveAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws
}

final class AmenSpacesDiscussionDiscoveryService: AmenSpacesDiscussionDiscoveryServicing {
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()
    private var listeners: [ListenerRegistration] = []
    private var currentItems = AmenSpacesDiscussionDiscoveryService.sampleItems
    private var currentOrganizations = AmenSpacesDiscussionDiscoveryService.sampleOrganizations

    static let callableContracts = AmenSpacesDiscussionDiscoveryCallable.allCases

    func startListening(
        onChange: @escaping @MainActor ([AmenSpacesDiscussionDiscoveryItem], [AmenSpacesOrganizationSpotlightItem], Bool) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        stopListening()

        guard let uid = Auth.auth().currentUser?.uid else {
            Task { @MainActor in onChange(Self.sampleItems, Self.sampleOrganizations, true) }
            return
        }

        let discoveryListener = db.collection("amenSpacesDiscovery")
            .document(uid)
            .collection("items")
            .order(by: "lastActivityAt", descending: true)
            .limit(to: 80)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in onError(Self.userSafeMessage(for: error)) }
                    return
                }
                let items = snap?.documents.compactMap(Self.discoveryItem(from:)) ?? []
                self.currentItems = items.isEmpty ? Self.sampleItems : items
                let currentItems = self.currentItems
                let currentOrgs = self.currentOrganizations
                Task { @MainActor in onChange(currentItems, currentOrgs, snap?.metadata.isFromCache ?? false) }
            }
        listeners.append(discoveryListener)

        let organizationListener = db.collection("amenSpacesOrganizations")
            .whereField("isDiscoverable", isEqualTo: true)
            .limit(to: 24)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in onError(Self.userSafeMessage(for: error)) }
                    return
                }
                let organizations = snap?.documents.compactMap(Self.organization(from:)) ?? []
                self.currentOrganizations = organizations.isEmpty ? Self.sampleOrganizations : organizations
                let currentItems = self.currentItems
                let currentOrgs = self.currentOrganizations
                Task { @MainActor in onChange(currentItems, currentOrgs, snap?.metadata.isFromCache ?? false) }
            }
        listeners.append(organizationListener)
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    func joinAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws {
        try await call(.joinAmenSpaceDiscussion, item: item)
    }

    func requestAmenSpaceDiscussionAccess(_ item: AmenSpacesDiscussionDiscoveryItem) async throws {
        try await call(.requestAmenSpaceDiscussionAccess, item: item)
    }

    func leaveAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws {
        try await call(.leaveAmenSpaceDiscussion, item: item)
    }

    func markDiscussionInterested(_ item: AmenSpacesDiscussionDiscoveryItem) async throws {
        try await call(.rankAmenSpacesDiscussions, item: item, extra: ["intent": "interested"])
    }

    func reportAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem, reason: String) async throws {
        try await call(.reportAmenSpaceDiscussion, item: item, extra: ["reason": reason])
    }

    func muteAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws {
        try await call(.muteAmenSpaceDiscussion, item: item)
    }

    func saveAmenSpaceDiscussion(_ item: AmenSpacesDiscussionDiscoveryItem) async throws {
        try await call(.saveAmenSpaceDiscussion, item: item)
    }

    private func call(_ callable: AmenSpacesDiscussionDiscoveryCallable, item: AmenSpacesDiscussionDiscoveryItem, extra: [String: Any] = [:]) async throws {
        guard Auth.auth().currentUser != nil else { throw URLError(.userAuthenticationRequired) }
        var payload: [String: Any] = [
            "discussionId": item.id,
            "spaceId": item.spaceId,
            "organizationId": item.organizationId as Any,
            "visibility": item.visibility.rawValue,
            "joinPolicy": item.joinPolicy.rawValue
        ]
        extra.forEach { payload[$0.key] = $0.value }
        _ = try await functions.httpsCallable(callable.rawValue).call(payload)
    }

    deinit { stopListening() }
}

extension AmenSpacesDiscussionDiscoveryService {
    static func rankedDiscoveryItems(
        from items: [AmenSpacesDiscussionDiscoveryItem],
        filters: AmenSpacesDiscussionFilters,
        context: AmenSpacesDiscussionAccessContext
    ) -> [AmenSpacesDiscussionDiscoveryItem] {
        filters.apply(to: items, context: context)
    }

    static func heroItem(from items: [AmenSpacesDiscussionDiscoveryItem], context: AmenSpacesDiscussionAccessContext) -> AmenSpacesDiscussionDiscoveryItem? {
        items
            .filter { $0.canSurface(in: context) }
            .filter { $0.accessAction(in: context) != .unavailable }
            .sorted { lhs, rhs in
                if lhs.isLive != rhs.isLive { return lhs.isLive && !rhs.isLive }
                return lhs.trendingScore > rhs.trendingScore
            }
            .first
    }

    static func userSafeMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code) {
            switch code {
            case .unauthenticated: return "Sign in to join this discussion."
            case .permissionDenied: return "You do not have access to that discussion."
            case .failedPrecondition: return "This discussion needs an access check before you can join."
            case .resourceExhausted: return "Please slow down and try again in a moment."
            default: return "Amen Spaces could not complete that action."
            }
        }
        return "Amen Spaces could not complete that action."
    }
}

private extension AmenSpacesDiscussionDiscoveryService {
    nonisolated static func discoveryItem(from document: QueryDocumentSnapshot) -> AmenSpacesDiscussionDiscoveryItem? {
        let data = document.data()
        let title = string(data, "title")
        guard !title.isEmpty else { return nil }
        return AmenSpacesDiscussionDiscoveryItem(
            id: document.documentID,
            spaceId: string(data, "spaceId"),
            organizationId: data["organizationId"] as? String,
            sourceType: AmenSpacesDiscussionSourceType(rawValue: string(data, "sourceType", "organization")) ?? .organization,
            title: title,
            subtitle: string(data, "subtitle"),
            descriptionPreview: string(data, "descriptionPreview"),
            bannerImageURL: data["bannerImageURL"] as? String,
            avatarURL: data["avatarURL"] as? String,
            category: AmenSpacesDiscussionCategory(rawValue: string(data, "category", "All")) ?? .all,
            tags: strings(data, "tags"),
            visibility: AmenSpacesDiscussionVisibility(rawValue: string(data, "visibility", "publicOpen")) ?? .publicOpen,
            joinPolicy: AmenSpacesDiscussionJoinPolicy(rawValue: string(data, "joinPolicy", "open")) ?? .open,
            membershipStatus: AmenSpacesDiscussionMembershipStatus(rawValue: string(data, "membershipStatus", "notJoined")) ?? .notJoined,
            participantCount: int(data, "participantCount"),
            unreadCount: int(data, "unreadCount"),
            trendingScore: double(data, "trendingScore"),
            safetyStatus: AmenSpacesDiscussionSafetyStatus(rawValue: string(data, "safetyStatus", "allowed")) ?? .allowed,
            moderationStatus: AmenSpacesDiscussionModerationStatus(rawValue: string(data, "moderationStatus", "visible")) ?? .visible,
            trustBadges: strings(data, "trustBadges").compactMap(AmenSpacesDiscussionTrustBadge.init(rawValue:)),
            isLive: bool(data, "isLive"),
            isVerified: bool(data, "isVerified"),
            isYouthProtected: bool(data, "isYouthProtected"),
            isConfidential: bool(data, "isConfidential"),
            requiresTier: data["requiresTier"] as? String,
            createdAt: date(data, "createdAt"),
            lastActivityAt: date(data, "lastActivityAt"),
            recommendationReason: data["recommendationReason"] as? String,
            aiSummary: data["aiSummary"] as? String,
            deepLink: (data["deepLink"] as? String).flatMap(URL.init(string:)),
            isAIExcluded: bool(data, "isAIExcluded"),
            isReportedByViewer: bool(data, "isReportedByViewer"),
            approximateRegion: data["approximateRegion"] as? String
        )
    }

    nonisolated static func organization(from document: QueryDocumentSnapshot) -> AmenSpacesOrganizationSpotlightItem? {
        let data = document.data()
        let name = string(data, "name")
        guard !name.isEmpty else { return nil }
        return AmenSpacesOrganizationSpotlightItem(
            id: document.documentID,
            name: name,
            subtitle: string(data, "subtitle"),
            bannerImageURL: data["bannerImageURL"] as? String,
            avatarURL: data["avatarURL"] as? String,
            isVerified: bool(data, "isVerified"),
            openDiscussionCount: int(data, "openDiscussionCount"),
            upcomingEventCount: int(data, "upcomingEventCount"),
            trustBadges: strings(data, "trustBadges").compactMap(AmenSpacesDiscussionTrustBadge.init(rawValue:))
        )
    }

    nonisolated static func string(_ data: [String: Any], _ key: String, _ fallback: String = "") -> String {
        data[key] as? String ?? fallback
    }

    nonisolated static func strings(_ data: [String: Any], _ key: String) -> [String] {
        data[key] as? [String] ?? []
    }

    nonisolated static func int(_ data: [String: Any], _ key: String) -> Int {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? NSNumber { return value.intValue }
        return 0
    }

    nonisolated static func double(_ data: [String: Any], _ key: String) -> Double {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? NSNumber { return value.doubleValue }
        return 0
    }

    nonisolated static func bool(_ data: [String: Any], _ key: String) -> Bool {
        if let value = data[key] as? Bool { return value }
        if let value = data[key] as? NSNumber { return value.boolValue }
        return false
    }

    nonisolated static func date(_ data: [String: Any], _ key: String) -> Date {
        if let value = data[key] as? Timestamp { return value.dateValue() }
        if let value = data[key] as? TimeInterval { return Date(timeIntervalSince1970: value) }
        if let value = data[key] as? NSNumber { return Date(timeIntervalSince1970: value.doubleValue) }
        return Date(timeIntervalSince1970: 0)
    }
}

extension AmenSpacesDiscussionDiscoveryService {
    static let sampleItems: [AmenSpacesDiscussionDiscoveryItem] = [
        AmenSpacesDiscussionDiscoveryItem(
            id: "ucf-romans-8",
            spaceId: "ucf-campus-ministry",
            organizationId: "ucf-campus-ministry",
            sourceType: .university,
            title: "UCF Bible Study: Romans 8 Discussion",
            subtitle: "UCF Campus Ministry",
            descriptionPreview: "Students are discussing tonight's service, rides, and volunteer needs.",
            bannerImageURL: nil,
            avatarURL: nil,
            category: .bibleStudy,
            tags: ["UCF", "Bible Study", "Romans", "Campus"],
            visibility: .publicOpen,
            joinPolicy: .open,
            membershipStatus: .notJoined,
            participantCount: 128,
            unreadCount: 24,
            trendingScore: 96,
            safetyStatus: .allowed,
            moderationStatus: .visible,
            trustBadges: [.verified, .moderated],
            isLive: true,
            isVerified: true,
            isYouthProtected: false,
            isConfidential: false,
            requiresTier: nil,
            createdAt: Date().addingTimeInterval(-2 * 24 * 60 * 60),
            lastActivityAt: Date().addingTimeInterval(-12 * 60),
            recommendationReason: "Because you follow UCF Campus Ministry",
            aiSummary: nil,
            deepLink: URL(string: "amen://spaces/ucf-campus-ministry/discussions/ucf-romans-8"),
            isAIExcluded: false,
            isReportedByViewer: false,
            approximateRegion: "Orlando area"
        ),
        AmenSpacesDiscussionDiscoveryItem(
            id: "parents-babysitting-weekend",
            spaceId: "parents-local-help",
            organizationId: nil,
            sourceType: .marketplace,
            title: "Parents: Trusted Babysitters",
            subtitle: "Local Help Marketplace",
            descriptionPreview: "Parents are sharing vetted sitter needs and weekend availability by approximate area.",
            bannerImageURL: nil,
            avatarURL: nil,
            category: .babysitting,
            tags: ["Parents", "Babysitting", "Local Help"],
            visibility: .publicOpen,
            joinPolicy: .requestRequired,
            membershipStatus: .notJoined,
            participantCount: 74,
            unreadCount: 12,
            trendingScore: 84,
            safetyStatus: .allowed,
            moderationStatus: .visible,
            trustBadges: [.moderated, .backgroundChecked],
            isLive: false,
            isVerified: true,
            isYouthProtected: false,
            isConfidential: false,
            requiresTier: nil,
            createdAt: Date().addingTimeInterval(-4 * 24 * 60 * 60),
            lastActivityAt: Date().addingTimeInterval(-90 * 60),
            recommendationReason: "Popular with local parent groups",
            aiSummary: nil,
            deepLink: nil,
            isAIExcluded: false,
            isReportedByViewer: false,
            approximateRegion: "Nearby community"
        ),
        AmenSpacesDiscussionDiscoveryItem(
            id: "career-internships",
            spaceId: "career-circle",
            organizationId: "career-circle",
            sourceType: .mentor,
            title: "Career Circle: Internship Openings",
            subtitle: "Mentorship Circle",
            descriptionPreview: "Mentors are collecting internship leads and resume feedback for students this week.",
            bannerImageURL: nil,
            avatarURL: nil,
            category: .career,
            tags: ["Career", "Mentorship", "Jobs", "Internships"],
            visibility: .publicOpen,
            joinPolicy: .open,
            membershipStatus: .notJoined,
            participantCount: 203,
            unreadCount: 31,
            trendingScore: 90,
            safetyStatus: .allowed,
            moderationStatus: .visible,
            trustBadges: [.verified, .moderated],
            isLive: false,
            isVerified: true,
            isYouthProtected: false,
            isConfidential: false,
            requiresTier: nil,
            createdAt: Date().addingTimeInterval(-6 * 24 * 60 * 60),
            lastActivityAt: Date().addingTimeInterval(-35 * 60),
            recommendationReason: "Because career and mentorship discussions are trending",
            aiSummary: nil,
            deepLink: nil,
            isAIExcluded: false,
            isReportedByViewer: false,
            approximateRegion: nil
        ),
        AmenSpacesDiscussionDiscoveryItem(
            id: "young-adults-friday",
            spaceId: "young-adults",
            organizationId: "grace-church",
            sourceType: .church,
            title: "Young Adults: Friday Night Plans",
            subtitle: "Grace Church Young Adults",
            descriptionPreview: "Open planning thread for dinner, worship night rides, and volunteer roles.",
            bannerImageURL: nil,
            avatarURL: nil,
            category: .churches,
            tags: ["Young Adults", "Church", "Volunteering"],
            visibility: .publicOpen,
            joinPolicy: .open,
            membershipStatus: .joined,
            participantCount: 61,
            unreadCount: 3,
            trendingScore: 78,
            safetyStatus: .allowed,
            moderationStatus: .visible,
            trustBadges: [.organizationVerified, .moderated],
            isLive: false,
            isVerified: true,
            isYouthProtected: false,
            isConfidential: false,
            requiresTier: nil,
            createdAt: Date().addingTimeInterval(-3 * 24 * 60 * 60),
            lastActivityAt: Date().addingTimeInterval(-20 * 60),
            recommendationReason: "Because you are already a member",
            aiSummary: nil,
            deepLink: nil,
            isAIExcluded: false,
            isReportedByViewer: false,
            approximateRegion: "Nearby community"
        ),
        AmenSpacesDiscussionDiscoveryItem(
            id: "worship-team-rehearsal",
            spaceId: "worship-team",
            organizationId: "grace-church",
            sourceType: .church,
            title: "Worship Team: Rehearsal Updates",
            subtitle: "Grace Church Worship",
            descriptionPreview: "Schedule, set list, and arrival details for this week's rehearsal.",
            bannerImageURL: nil,
            avatarURL: nil,
            category: .churches,
            tags: ["Worship", "Church", "Music"],
            visibility: .organizationOnly,
            joinPolicy: .requestRequired,
            membershipStatus: .notJoined,
            participantCount: 38,
            unreadCount: 8,
            trendingScore: 73,
            safetyStatus: .allowed,
            moderationStatus: .visible,
            trustBadges: [.organizationVerified, .moderated],
            isLive: false,
            isVerified: true,
            isYouthProtected: false,
            isConfidential: false,
            requiresTier: nil,
            createdAt: Date().addingTimeInterval(-8 * 24 * 60 * 60),
            lastActivityAt: Date().addingTimeInterval(-3 * 60 * 60),
            recommendationReason: "From an organization connected to your memberships",
            aiSummary: nil,
            deepLink: nil,
            isAIExcluded: false,
            isReportedByViewer: false,
            approximateRegion: nil
        )
    ]

    static let sampleOrganizations: [AmenSpacesOrganizationSpotlightItem] = [
        AmenSpacesOrganizationSpotlightItem(id: "ucf-campus-ministry", name: "UCF Campus Ministry", subtitle: "University community", bannerImageURL: nil, avatarURL: nil, isVerified: true, openDiscussionCount: 12, upcomingEventCount: 3, trustBadges: [.organizationVerified]),
        AmenSpacesOrganizationSpotlightItem(id: "grace-church", name: "Grace Church", subtitle: "Church community", bannerImageURL: nil, avatarURL: nil, isVerified: true, openDiscussionCount: 9, upcomingEventCount: 5, trustBadges: [.organizationVerified, .moderated]),
        AmenSpacesOrganizationSpotlightItem(id: "career-circle", name: "Career Circle", subtitle: "Mentorship and jobs", bannerImageURL: nil, avatarURL: nil, isVerified: true, openDiscussionCount: 7, upcomingEventCount: 1, trustBadges: [.verified, .moderated])
    ]
}
