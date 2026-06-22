import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
enum AmenConnectLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case offline
    case failed(String)
}

@MainActor
final class AmenConnectViewModel: ObservableObject {
    @Published var selectedRoom: AmenConnectRoom = .lobby
    @Published var searchText = ""
    @Published var isShowingCatchUp = false
    @Published var isShowingCommandSheet = false
    @Published var loadState: AmenConnectLoadState = .idle
    @Published var actionMessage: String?
    @Published var spaces: [AmenConnectSpace] = []
    @Published var channels: [AmenConnectChannel] = []
    @Published var meetings: [AmenConnectMeeting] = []
    @Published var listings: [AmenConnectMarketplaceListing] = []
    @Published var creators: [AmenConnectCreatorProfile] = []
    @Published var tiers: [AmenConnectMembershipTier] = []
    @Published var boards: [AmenConnectBoard] = []
    @Published var activityItems: [AmenConnectActivityItem] = []
    @Published var backendContracts: [AmenConnectBackendContract] = AmenConnectService.contracts

    private let service: AmenConnectServicing

    init(service: AmenConnectServicing? = nil) {
        self.service = service ?? AmenConnectService()
    }

    deinit {
        service.stopListening()
    }

    func load() async {
        loadState = .loading
        service.startListening { [weak self] snapshot, isFromCache in
            guard let self else { return }
            self.spaces = snapshot.spaces
            self.channels = snapshot.channels
            self.meetings = snapshot.meetings
            self.listings = snapshot.listings
            self.creators = snapshot.creators
            self.tiers = snapshot.tiers
            self.boards = snapshot.boards
            self.activityItems = snapshot.activityItems
            // C: ConnectBadgeStore feed — count action-required activity per section
            let activityBadge = snapshot.activityItems.filter { $0.requiresAction }.count
            ConnectBadgeStore.shared.setBadge(activityBadge, for: .activity)
            let spacesBadge  = snapshot.spaces.filter { $0.unreadCount > 0 }.count
            ConnectBadgeStore.shared.setBadge(spacesBadge, for: .spaces)
            if activityBadge == 0 { ConnectBadgeStore.shared.clearBadge(for: .activity) }
            if spacesBadge  == 0 { ConnectBadgeStore.shared.clearBadge(for: .spaces) }
            if isFromCache && !snapshot.hasContent {
                self.loadState = .offline
            } else {
                self.loadState = snapshot.hasContent ? .loaded : .empty
            }
        } onError: { [weak self] message in
            self?.loadState = .failed(message)
        }
    }

    func retry() async {
        service.stopListening()
        await load()
    }

    func perform(_ action: AmenConnectCallableAction, payload: [String: Any] = [:]) async -> Bool {
        do {
            actionMessage = nil
            _ = try await service.call(action, payload: payload)
            actionMessage = action.successMessage
            return true
        } catch {
            actionMessage = AmenConnectService.userSafeMessage(for: error)
            return false
        }
    }

    func createSpace(name: String, type: AmenConnectSpaceType, description: String) async -> Bool {
        await perform(.createConnectSpace, payload: ["name": name, "type": type.rawValue, "description": description])
    }

    func createChannel(spaceId: String, name: String) async -> Bool {
        await perform(.createConnectChannel, payload: ["spaceId": spaceId, "name": name, "type": "public", "visibility": "publicToSpace"])
    }

    func sendMessage(spaceId: String, channelId: String, body: String) async -> Bool {
        await perform(.sendConnectMessage, payload: ["spaceId": spaceId, "channelId": channelId, "body": body])
    }

    func createMarketplaceListing(spaceId: String, title: String, category: AmenConnectMarketplaceCategory, description: String, compensation: String) async -> Bool {
        await perform(.createMarketplaceListing, payload: [
            "spaceId": spaceId,
            "title": title,
            "category": category.rawValue,
            "description": description,
            "compensation": compensation
        ])
    }

    func generateCatchUp() async -> Bool {
        let spaceId = spaces.first?.id ?? ""
        return await perform(.generateConnectCatchUp, payload: ["spaceId": spaceId, "accessScope": "currentUserVisibleContentOnly"])
    }

    func canAccessPaidContent(userTierIds: Set<String>, requiredTierId: String?) -> Bool {
        service.canAccessPaidContent(userTierIds: userTierIds, requiredTierId: requiredTierId)
    }

    func canAIUseContent(userRole: AmenConnectRole, visibility: AmenConnectVisibility, isAIExcluded: Bool, requiredTierId: String?, userTierIds: Set<String>) -> Bool {
        service.canAIUseContent(
            userRole: userRole,
            visibility: visibility,
            isAIExcluded: isAIExcluded,
            requiredTierId: requiredTierId,
            userTierIds: userTierIds
        )
    }
}

struct AmenConnectSnapshot {
    var spaces: [AmenConnectSpace] = []
    var channels: [AmenConnectChannel] = []
    var meetings: [AmenConnectMeeting] = []
    var listings: [AmenConnectMarketplaceListing] = []
    var creators: [AmenConnectCreatorProfile] = []
    var tiers: [AmenConnectMembershipTier] = []
    var boards: [AmenConnectBoard] = []
    var activityItems: [AmenConnectActivityItem] = []

    var hasContent: Bool {
        !spaces.isEmpty || !channels.isEmpty || !meetings.isEmpty || !listings.isEmpty || !creators.isEmpty || !tiers.isEmpty || !boards.isEmpty || !activityItems.isEmpty
    }
}

enum AmenConnectCallableAction: String, CaseIterable {
    case createConnectSpace
    case inviteConnectMember
    case acceptConnectInvite
    case createConnectChannel
    case sendConnectMessage
    case moderateConnectMessageBeforeSend
    case createConnectAnnouncement
    case createConnectMeeting
    case joinConnectMeeting
    case generateMeetingRecap
    case createConnectEvent
    case createConnectBoard
    case createMarketplaceListing
    case applyToMarketplaceListing
    case reportConnectContent
    case reviewConnectReport
    case generateConnectCatchUp
    case summarizeConnectChannel
    case summarizeConnectDM
    case classifyConnectIntent
    case extractTasksFromConnectThread
    case createJobListingFromMessage
    case createBabysittingListingFromMessage
    case createTutoringListingFromMessage
    case createConnectCreatorProfile
    case createConnectTier
    case subscribeToConnectTier
    case createConnectProduct
    case purchaseConnectProduct
    case createConnectLiveSession
    case createConnectBooking
    case moderateConnectMonetizedOffer

    var successMessage: String {
        switch self {
        case .generateConnectCatchUp, .summarizeConnectChannel, .summarizeConnectDM, .classifyConnectIntent, .extractTasksFromConnectThread:
            return "Amen Guide request started."
        case .subscribeToConnectTier, .purchaseConnectProduct:
            return "Payment request created. Access unlocks only after server confirmation."
        default:
            return "Amen Connect action completed."
        }
    }
}

protocol AmenConnectServicing: AnyObject {
    func startListening(onChange: @escaping @MainActor (AmenConnectSnapshot, Bool) -> Void, onError: @escaping @MainActor (String) -> Void)
    func stopListening()
    func call(_ action: AmenConnectCallableAction, payload: [String: Any]) async throws -> [String: Any]
    func canAccessPaidContent(userTierIds: Set<String>, requiredTierId: String?) -> Bool
    func canAIUseContent(userRole: AmenConnectRole, visibility: AmenConnectVisibility, isAIExcluded: Bool, requiredTierId: String?, userTierIds: Set<String>) -> Bool
}

final class AmenConnectService: AmenConnectServicing {
    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listeners: [ListenerRegistration] = []
    private var snapshot = AmenConnectSnapshot()
    private var onChange: (@MainActor (AmenConnectSnapshot, Bool) -> Void)?
    private var onError: (@MainActor (String) -> Void)?
    private var observedSpaceIds = Set<String>()

    func startListening(onChange: @escaping @MainActor (AmenConnectSnapshot, Bool) -> Void, onError: @escaping @MainActor (String) -> Void) {
        stopListening()
        self.onChange = onChange
        self.onError = onError

        guard let uid = Auth.auth().currentUser?.uid else {
            Task { @MainActor in onError("Sign in to use Amen Connect.") }
            return
        }

        listenToSpaces()
        listenToActivity(uid: uid)
        listenToDirectMessages(uid: uid)
        listenToCreatorProfiles()
        listenToMemberships(uid: uid)
        listenToTrust(uid: uid)
        listenToSafety(uid: uid)
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        observedSpaceIds.removeAll()
    }

    func call(_ action: AmenConnectCallableAction, payload: [String: Any]) async throws -> [String: Any] {
        guard Auth.auth().currentUser != nil else {
            throw AmenConnectClientError.notAuthenticated
        }
        do {
            let result = try await functions.httpsCallable(action.rawValue).call(payload)
            return result.data as? [String: Any] ?? [:]
        } catch {
            throw error
        }
    }

    func canAccessPaidContent(userTierIds: Set<String>, requiredTierId: String?) -> Bool {
        guard let requiredTierId, !requiredTierId.isEmpty else { return true }
        return userTierIds.contains(requiredTierId)
    }

    func canAIUseContent(
        userRole: AmenConnectRole,
        visibility: AmenConnectVisibility,
        isAIExcluded: Bool,
        requiredTierId: String?,
        userTierIds: Set<String>
    ) -> Bool {
        guard !isAIExcluded else { return false }
        guard canAccessPaidContent(userTierIds: userTierIds, requiredTierId: requiredTierId) else { return false }
        switch visibility {
        case .publicToSpace, .channelOnly:
            return true
        case .leadersOnly:
            return [.owner, .admin, .moderator, .leader].contains(userRole)
        case .privateGroup, .confidential, .youthProtected:
            return [.owner, .admin, .moderator].contains(userRole)
        case .anonymous:
            return [.owner, .admin, .moderator, .leader].contains(userRole)
        case .paidTier:
            return requiredTierId == nil || userTierIds.contains(requiredTierId ?? "")
        }
    }

    static func userSafeMessage(for error: Error) -> String {
        if let clientError = error as? AmenConnectClientError {
            return clientError.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code) {
            switch code {
            case .unauthenticated:
                return "Sign in to continue."
            case .permissionDenied:
                return "You do not have permission to do that in this space."
            case .failedPrecondition:
                return "This action needs additional verification before it can continue."
            case .resourceExhausted:
                return "Please slow down and try again in a moment."
            case .invalidArgument:
                return "Check the required fields and try again."
            default:
                return "Amen Connect could not complete that action. Please try again."
            }
        }
        return "Amen Connect could not complete that action. Please try again."
    }

    private func listenToSpaces() {
        let listener = db.collection("connectSpaces")
            .whereField("visibility", isEqualTo: "publicToSpace")
            .limit(to: 50)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    self.emitError(error)
                    return
                }
                let spaces = snap?.documents.compactMap { Self.space(from: $0) } ?? []
                self.snapshot.spaces = spaces
                spaces.prefix(3).forEach { self.listenToSpaceChildren(spaceId: $0.id) }
                self.emit(isFromCache: snap?.metadata.isFromCache ?? false)
            }
        listeners.append(listener)
    }

    private func listenToSpaceChildren(spaceId: String) {
        guard !observedSpaceIds.contains(spaceId) else { return }
        observedSpaceIds.insert(spaceId)
        listen(spaceId: spaceId, collection: "channels", limit: 40) { [weak self] docs, cache in
            guard let self else { return }
            let parsed = docs.compactMap { Self.channel(from: $0, spaceId: spaceId) }
            self.snapshot.channels.removeAll { $0.spaceId == spaceId }
            self.snapshot.channels.append(contentsOf: parsed)
            self.emit(isFromCache: cache)
        }
        listen(spaceId: spaceId, collection: "meetings", limit: 20) { [weak self] docs, cache in
            guard let self else { return }
            self.snapshot.meetings = docs.compactMap(Self.meeting)
            self.emit(isFromCache: cache)
        }
        listen(spaceId: spaceId, collection: "events", limit: 20) { [weak self] docs, cache in
            guard let self else { return }
            let events = docs.compactMap(Self.meetingFromEvent)
            self.snapshot.meetings.append(contentsOf: events.filter { event in !self.snapshot.meetings.contains(where: { $0.id == event.id }) })
            self.emit(isFromCache: cache)
        }
        listen(spaceId: spaceId, collection: "boards", limit: 20) { [weak self] docs, cache in
            guard let self else { return }
            self.snapshot.boards = docs.compactMap(Self.board)
            self.emit(isFromCache: cache)
        }
        listen(spaceId: spaceId, collection: "marketplaceListings", limit: 25) { [weak self] docs, cache in
            guard let self else { return }
            self.snapshot.listings = docs.compactMap(Self.listing)
            self.emit(isFromCache: cache)
        }
    }

    private func listen(spaceId: String, collection: String, limit: Int, handler: @escaping ([QueryDocumentSnapshot], Bool) -> Void) {
        let listener = db.collection("connectSpaces").document(spaceId).collection(collection)
            .limit(to: limit)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                if let error {
                    self?.emitError(error)
                    return
                }
                handler(snap?.documents ?? [], snap?.metadata.isFromCache ?? false)
            }
        listeners.append(listener)
    }

    private func listenToActivity(uid: String) {
        let listener = db.collection("connectActivity").document(uid).collection("items")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                guard let self else { return }
                if let error { self.emitError(error); return }
                self.snapshot.activityItems = snap?.documents.compactMap(Self.activity) ?? []
                self.emit(isFromCache: snap?.metadata.isFromCache ?? false)
            }
        listeners.append(listener)
    }

    private func listenToDirectMessages(uid: String) {
        let listener = db.collection("connectDMs")
            .whereField("participantIds", arrayContains: uid)
            .limit(to: 30)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                if let error { self?.emitError(error); return }
                self?.emit(isFromCache: snap?.metadata.isFromCache ?? false)
            }
        listeners.append(listener)
    }

    private func listenToCreatorProfiles() {
        let listener = db.collection("connectCreatorProfiles")
            .limit(to: 30)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                guard let self else { return }
                if let error { self.emitError(error); return }
                self.snapshot.creators = snap?.documents.compactMap(Self.creator) ?? []
                self.emit(isFromCache: snap?.metadata.isFromCache ?? false)
            }
        listeners.append(listener)
    }

    private func listenToMemberships(uid: String) {
        let listener = db.collection("connectMemberships")
            .whereField("userId", isEqualTo: uid)
            .limit(to: 50)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                guard let self else { return }
                if let error { self.emitError(error); return }
                self.snapshot.tiers = snap?.documents.compactMap(Self.membershipTier) ?? []
                self.emit(isFromCache: snap?.metadata.isFromCache ?? false)
            }
        listeners.append(listener)
    }

    private func listenToTrust(uid: String) {
        let listener = db.collection("connectUserTrust").document(uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] _, error in
                if let error { self?.emitError(error); return }
            }
        listeners.append(listener)
    }

    private func listenToSafety(uid: String) {
        let listener = db.collection("connectUserSafety").document(uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] _, error in
                if let error { self?.emitError(error); return }
            }
        listeners.append(listener)
    }

    private func emit(isFromCache: Bool) {
        let snapshot = snapshot
        Task { @MainActor in self.onChange?(snapshot, isFromCache) }
    }

    private func emitError(_ error: Error) {
        let message = Self.userSafeMessage(for: error)
        Task { @MainActor in self.onError?(message) }
    }
}

enum AmenConnectClientError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to continue."
        }
    }
}

private extension AmenConnectService {
    static func string(_ data: [String: Any], _ key: String, _ fallback: String = "") -> String {
        data[key] as? String ?? fallback
    }

    static func int(_ data: [String: Any], _ key: String, _ fallback: Int = 0) -> Int {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? NSNumber { return value.intValue }
        return fallback
    }

    static func bool(_ data: [String: Any], _ key: String, _ fallback: Bool = false) -> Bool {
        if let value = data[key] as? Bool { return value }
        if let value = data[key] as? NSNumber { return value.boolValue }
        return fallback
    }

    static func strings(_ data: [String: Any], _ key: String) -> [String] {
        data[key] as? [String] ?? []
    }

    static func visibility(_ value: String) -> AmenConnectVisibility {
        AmenConnectVisibility(rawValue: value) ?? .publicToSpace
    }

    static func safety(_ value: String) -> AmenConnectSafetyStatus {
        switch value {
        case "allow_with_warning": return .allowWithWarning
        case "needs_review": return .needsReview
        default: return AmenConnectSafetyStatus(rawValue: value) ?? .pending
        }
    }

    static func badges(_ values: [String]) -> [AmenConnectTrustBadge] {
        values.compactMap { AmenConnectTrustBadge(rawValue: $0) }
    }

    static func roles(_ values: [String]) -> [AmenConnectRole] {
        values.compactMap { AmenConnectRole(rawValue: $0) }
    }

    static func space(from document: QueryDocumentSnapshot) -> AmenConnectSpace {
        let data = document.data()
        return AmenConnectSpace(
            id: document.documentID,
            name: string(data, "name", "Untitled Space"),
            type: AmenConnectSpaceType(rawValue: string(data, "type", "Personal Group")) ?? .personalGroup,
            description: string(data, "description"),
            ownerId: string(data, "ownerId"),
            visibility: visibility(string(data, "visibility", "publicToSpace")),
            safetyMode: string(data, "safetyMode", "standard"),
            aiEnabled: bool(data, "aiEnabled", true),
            aiExclusions: strings(data, "aiExclusions"),
            memberCount: int(data, "memberCount"),
            unreadCount: int(data, "unreadCount"),
            nextEventTitle: data["nextEventTitle"] as? String,
            trustBadges: badges(strings(data, "trustBadges"))
        )
    }

    static func channel(from document: QueryDocumentSnapshot, spaceId: String) -> AmenConnectChannel {
        let data = document.data()
        return AmenConnectChannel(
            id: document.documentID,
            spaceId: spaceId,
            name: string(data, "name", document.documentID),
            type: string(data, "type", "public"),
            visibility: visibility(string(data, "visibility", "publicToSpace")),
            allowedRoles: roles(strings(data, "allowedRoles")),
            aiSummaryEnabled: bool(data, "aiSummaryEnabled", true),
            unreadCount: int(data, "unreadCount"),
            pinnedMessage: data["pinnedMessage"] as? String
        )
    }

    static func meeting(from document: QueryDocumentSnapshot) -> AmenConnectMeeting {
        let data = document.data()
        return AmenConnectMeeting(
            id: document.documentID,
            title: string(data, "title", "Untitled meeting"),
            hostName: string(data, "hostName", string(data, "createdBy", "Host")),
            type: string(data, "type", "Meeting"),
            startsIn: string(data, "startsIn", "Scheduled"),
            attendeeCount: int(data, "attendeeCount"),
            isPaid: bool(data, "isPaid"),
            requiresRecordingConsent: bool(data, "requiresRecordingConsent", true),
            safetyStatus: safety(string(data, "safetyStatus", "pending"))
        )
    }

    static func meetingFromEvent(from document: QueryDocumentSnapshot) -> AmenConnectMeeting {
        let data = document.data()
        return AmenConnectMeeting(
            id: "event-\(document.documentID)",
            title: string(data, "title", "Untitled event"),
            hostName: string(data, "hostName", "Space calendar"),
            type: "Event",
            startsIn: string(data, "startsIn", "Scheduled"),
            attendeeCount: int(data, "attendeeCount"),
            isPaid: bool(data, "isPaid"),
            requiresRecordingConsent: false,
            safetyStatus: safety(string(data, "safetyStatus", "pending"))
        )
    }

    static func board(from document: QueryDocumentSnapshot) -> AmenConnectBoard {
        let data = document.data()
        return AmenConnectBoard(
            id: document.documentID,
            title: string(data, "title", "Untitled board"),
            type: string(data, "type", "Community Dashboard"),
            blocks: strings(data, "blocks"),
            visibility: visibility(string(data, "visibility", "publicToSpace")),
            aiEligible: bool(data, "aiEligible", true)
        )
    }

    static func listing(from document: QueryDocumentSnapshot) -> AmenConnectMarketplaceListing {
        let data = document.data()
        let categoryName = string(data, "category", "Local Help")
        return AmenConnectMarketplaceListing(
            id: document.documentID,
            title: string(data, "title", "Untitled listing"),
            category: AmenConnectMarketplaceCategory(rawValue: categoryName) ?? .localHelp,
            locationLabel: string(data, "locationLabel", string(data, "location", "Location protected")),
            compensation: string(data, "compensation", string(data, "price", "Not listed")),
            posterName: string(data, "posterName", "Community member"),
            verificationLevel: string(data, "verificationLevel", "Verification pending"),
            safetyStatus: safety(string(data, "safetyStatus", "pending")),
            expiresLabel: string(data, "expiresLabel", "Expiration required"),
            trustBadges: badges(strings(data, "trustBadges"))
        )
    }

    static func creator(from document: QueryDocumentSnapshot) -> AmenConnectCreatorProfile {
        let data = document.data()
        return AmenConnectCreatorProfile(
            id: document.documentID,
            displayName: string(data, "displayName", string(data, "name", "Creator")),
            type: AmenConnectProfileType(rawValue: string(data, "type", "creator")) ?? .creator,
            bio: string(data, "bio"),
            memberCount: int(data, "memberCount"),
            isPaidEnabled: bool(data, "isPaidEnabled"),
            liveSoonLabel: data["liveSoonLabel"] as? String,
            trustBadges: badges(strings(data, "trustBadges")),
            safetyStatus: safety(string(data, "safetyStatus", "pending"))
        )
    }

    static func membershipTier(from document: QueryDocumentSnapshot) -> AmenConnectMembershipTier {
        let data = document.data()
        return AmenConnectMembershipTier(
            id: string(data, "tierId", document.documentID),
            name: string(data, "tierName", string(data, "name", "Membership")),
            priceLabel: string(data, "priceLabel", string(data, "price", "Server confirmed")),
            benefits: strings(data, "benefits"),
            accessRules: strings(data, "accessRules"),
            safetyFlags: strings(data, "safetyFlags"),
            moderationStatus: safety(string(data, "moderationStatus", "pending"))
        )
    }

    static func activity(from document: QueryDocumentSnapshot) -> AmenConnectActivityItem {
        let data = document.data()
        return AmenConnectActivityItem(
            id: document.documentID,
            title: string(data, "title", "Amen Connect update"),
            detail: string(data, "detail", string(data, "body")),
            room: AmenConnectRoom(rawValue: string(data, "room", "Activity")) ?? .activity,
            isPriority: bool(data, "isPriority"),
            requiresAction: bool(data, "requiresAction")
        )
    }
}

extension AmenConnectService {
    static let contracts: [AmenConnectBackendContract] = [
        .init(functionName: "createConnectSpace", purpose: "Create an Amen Space, owner membership, starter channels, and audit log.", serverAuthoritativeFields: ["ownerId", "memberCount", "moderationStatus", "auditLogs"], collectionsTouched: ["connectSpaces", "connectSpaces/{spaceId}/members", "connectSpaces/{spaceId}/auditLogs"]),
        .init(functionName: "sendConnectMessage", purpose: "Moderate and publish a channel message with mention, thread, unread, and activity fan-out.", serverAuthoritativeFields: ["safetyStatus", "moderationStatus", "aiEligible", "createdAt"], collectionsTouched: ["connectSpaces/{spaceId}/channels/{channelId}/messages", "connectActivity"]),
        .init(functionName: "generateConnectCatchUp", purpose: "Generate a permission-filtered AI catch-up from only visible, non-excluded content.", serverAuthoritativeFields: ["summary", "sourceRefs", "accessScope", "aiExcluded"], collectionsTouched: ["connectSpaces/{spaceId}/aiSummaries", "connectActivity"]),
        .init(functionName: "createMarketplaceListing", purpose: "Create jobs, babysitting, tutoring, services, housing, rides, volunteering, items, and local help listings after safety review.", serverAuthoritativeFields: ["safetyStatus", "moderationStatus", "verificationLevel", "expiresAt"], collectionsTouched: ["connectSpaces/{spaceId}/marketplaceListings", "connectMarketplaceGlobal", "connectSpaces/{spaceId}/auditLogs"]),
        .init(functionName: "createConnectCreatorProfile", purpose: "Create server-owned creator, mentor, teacher, organization, tutor, babysitter, coach, or service-provider profile.", serverAuthoritativeFields: ["trustBadges", "verificationBadges", "safetyStatus"], collectionsTouched: ["connectCreatorProfiles", "connectUserTrust"]),
        .init(functionName: "subscribeToConnectTier", purpose: "Attach a server-authoritative free or paid membership tier after payment/subscription state is confirmed.", serverAuthoritativeFields: ["paymentState", "membershipStatus", "tierAccess", "renewalState"], collectionsTouched: ["connectMemberships", "connectPayments", "connectCreatorProfiles/{creatorId}/memberships"]),
        .init(functionName: "moderateConnectMonetizedOffer", purpose: "Review tiers, sessions, products, bookings, jobs, babysitting, and services for scams, coercion, unsafe claims, youth risk, and off-platform pressure.", serverAuthoritativeFields: ["moderationStatus", "safetyStatus", "riskReasons"], collectionsTouched: ["connectCreatorProfiles", "connectMarketplaceGlobal", "connectSpaces/{spaceId}/reports"])
    ]
}

#if DEBUG
extension AmenConnectSnapshot {
    static let preview = AmenConnectSnapshot(
        spaces: [AmenConnectSpace(id: "preview", name: "Preview Space", type: .personalGroup, description: "DEBUG preview only.", ownerId: "preview", visibility: .publicToSpace, safetyMode: "preview", aiEnabled: true, aiExclusions: [], memberCount: 1, unreadCount: 0, nextEventTitle: nil, trustBadges: [])],
        channels: [],
        meetings: [],
        listings: [],
        creators: [],
        tiers: [],
        boards: [],
        activityItems: []
    )
}
#endif
