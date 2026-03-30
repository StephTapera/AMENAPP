// StudioService.swift
// AMEN Studio — Backend Service Layer
// Handles all Firestore reads/writes for Studio features

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class StudioDataService: ObservableObject {
    static let shared = StudioDataService()

    // MARK: - Published State

    @Published var myProfile: StudioProfile?
    @Published var myWorkItems: [StudioWorkItem] = []
    @Published var myServices: [StudioService_] = []
    @Published var myProducts: [StudioProduct] = []
    @Published var myCommissionProfile: StudioCommissionProfile?
    @Published var myCommissionRequests: [StudioCommissionRequest] = []
    @Published var myBookingRequests: [StudioBookingRequest] = []
    @Published var mySupportProfile: StudioSupportProfile?
    @Published var myInquiryThreads: [StudioInquiryThread] = []
    @Published var myEarningsSummary: StudioEarningsSummary?
    @Published var myTestimonials: [StudioTestimonial] = []

    // Discovery
    @Published var featuredCreators: [StudioProfile] = []
    @Published var featuredServices: [StudioService_] = []
    @Published var featuredProducts: [StudioProduct] = []
    @Published var openCommissions: [StudioProfile] = []

    // Loading states
    @Published var isLoadingProfile = false
    @Published var isLoadingWork = false
    @Published var isLoadingServices = false
    @Published var isLoadingProducts = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // Unread inquiry count (for badge)
    @Published var unreadInquiryCount: Int = 0

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var isListening = false

    private init() { }

    // MARK: - Current User ID

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Setup / Teardown

    func setupListeners() {
        guard !isListening, let userId = currentUserId else { return }
        isListening = true

        // Profile listener
        let profileListener = db.collection("studioProfiles")
            .document(userId)
            .addSnapshotListener { [weak self] snap, _ in
                self?.myProfile = try? snap?.data(as: StudioProfile.self)
            }
        listeners.append(profileListener)

        // Work items listener
        let workListener = db.collection("studioItems")
            .whereField("creatorId", isEqualTo: userId)
            .whereField("isPublic", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snap, _ in
                self?.myWorkItems = snap?.documents.compactMap {
                    try? $0.data(as: StudioWorkItem.self)
                } ?? []
            }
        listeners.append(workListener)

        // Unread inquiries
        let inquiryListener = db.collection("inquiryThreads")
            .whereField("creatorId", isEqualTo: userId)
            .whereField("isReadByCreator", isEqualTo: false)
            .addSnapshotListener { [weak self] snap, _ in
                self?.unreadInquiryCount = snap?.documents.count ?? 0
            }
        listeners.append(inquiryListener)
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
        isListening = false
    }

    // MARK: - Profile CRUD

    func fetchProfile(for userId: String) async -> StudioProfile? {
        guard let snap = try? await db.collection("studioProfiles").document(userId).getDocument() else {
            return nil
        }
        return try? snap.data(as: StudioProfile.self)
    }

    func saveProfile(_ profile: StudioProfile) async throws {
        guard let userId = currentUserId else { return }
        isSaving = true
        defer { isSaving = false }
        var updated = profile
        updated.updatedAt = Date()
        let encoded = try Firestore.Encoder().encode(updated)
        try await db.collection("studioProfiles").document(userId).setData(encoded, merge: true)
    }

    func createProfile(displayName: String, tagline: String, creatorType: CreatorType, categories: [StudioCategory]) async throws {
        guard let userId = currentUserId else { return }
        let profile = StudioProfile(
            userId: userId,
            displayName: displayName,
            handle: "",
            tagline: tagline,
            bio: "",
            bannerColor: "#1A1A2E",
            creatorType: creatorType,
            categories: categories,
            specialties: [],
            locationVisible: false,
            socialLinks: [:],
            isVerified: false,
            verifiedAs: .none,
            isOpenForWork: true,
            isOpenForCommissions: false,
            inquiryPolicy: .everyone,
            trustScore: 0.5,
            moderationState: .active,
            planTier: .free,
            isPublished: true,
            createdAt: Date(),
            updatedAt: Date(),
            analyticsOptIn: true,
            searchKeywords: []
        )
        let encoded = try Firestore.Encoder().encode(profile)
        try await db.collection("studioProfiles").document(userId).setData(encoded)
    }

    // MARK: - Work Items CRUD

    func fetchWorkItems(for userId: String) async -> [StudioWorkItem] {
        guard let snap = try? await db.collection("studioItems")
            .whereField("creatorId", isEqualTo: userId)
            .whereField("isPublic", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioWorkItem.self) }
    }

    func saveWorkItem(_ item: StudioWorkItem) async throws {
        guard let userId = currentUserId else { return }
        isSaving = true
        defer { isSaving = false }
        var updated = item
        updated.updatedAt = Date()
        let docId = item.id ?? UUID().uuidString
        let encoded = try Firestore.Encoder().encode(updated)
        try await db.collection("studioItems").document(docId).setData(encoded, merge: true)
        // Update search keywords
        try await db.collection("studioItems").document(docId).updateData([
            "creatorId": userId,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func deleteWorkItem(_ itemId: String) async throws {
        try await db.collection("studioItems").document(itemId).delete()
    }

    // MARK: - Services CRUD

    func fetchServices(for userId: String) async -> [StudioService_] {
        guard let snap = try? await db.collection("studioServices")
            .whereField("creatorId", isEqualTo: userId)
            .whereField("isAvailable", isEqualTo: true)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioService_.self) }
    }

    func saveService(_ service: StudioService_) async throws {
        isSaving = true
        defer { isSaving = false }
        var updated = service
        updated.updatedAt = Date()
        let docId = service.id ?? UUID().uuidString
        let encoded = try Firestore.Encoder().encode(updated)
        try await db.collection("studioServices").document(docId).setData(encoded, merge: true)
    }

    // MARK: - Products CRUD

    func fetchProducts(for userId: String) async -> [StudioProduct] {
        guard let snap = try? await db.collection("studioProducts")
            .whereField("creatorId", isEqualTo: userId)
            .whereField("isPublished", isEqualTo: true)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioProduct.self) }
    }

    func saveProduct(_ product: StudioProduct) async throws {
        isSaving = true
        defer { isSaving = false }
        var updated = product
        updated.updatedAt = Date()
        let docId = product.id ?? UUID().uuidString
        let encoded = try Firestore.Encoder().encode(updated)
        try await db.collection("studioProducts").document(docId).setData(encoded, merge: true)
    }

    // MARK: - Commission CRUD

    func fetchCommissionProfile(for userId: String) async -> StudioCommissionProfile? {
        guard let snap = try? await db.collection("commissionProfiles").document(userId).getDocument() else {
            return nil
        }
        return try? snap.data(as: StudioCommissionProfile.self)
    }

    func toggleCommissionsOpen(_ isOpen: Bool) async throws {
        guard let userId = currentUserId else { return }
        try await db.collection("commissionProfiles").document(userId).setData([
            "isOpen": isOpen,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func submitCommissionRequest(_ request: StudioCommissionRequest) async throws {
        let docId = UUID().uuidString
        let encoded = try Firestore.Encoder().encode(request)
        try await db.collection("commissionRequests").document(docId).setData(encoded)
        // Notify creator
        await sendStudioNotification(
            toUserId: request.creatorId,
            type: .commissionRequest,
            title: "New Commission Request",
            body: "\(request.requesterName) wants to commission work from you.",
            relatedId: docId
        )
    }

    func updateCommissionStatus(_ requestId: String, status: CommissionStatus, note: String?) async throws {
        var data: [String: Any] = [
            "status": status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let note = note { data["creatorNote"] = note }
        try await db.collection("commissionRequests").document(requestId).updateData(data)
    }

    // MARK: - Booking CRUD

    func submitBookingRequest(_ request: StudioBookingRequest) async throws {
        let docId = UUID().uuidString
        let encoded = try Firestore.Encoder().encode(request)
        try await db.collection("bookingRequests").document(docId).setData(encoded)
        await sendStudioNotification(
            toUserId: request.creatorId,
            type: .bookingRequest,
            title: "New Booking Request",
            body: "\(request.requesterName) wants to book you for: \(request.title)",
            relatedId: docId
        )
    }

    func updateBookingStatus(_ bookingId: String, status: BookingStatus, response: String?) async throws {
        var data: [String: Any] = [
            "status": status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let response = response { data["creatorResponse"] = response }
        try await db.collection("bookingRequests").document(bookingId).updateData(data)
    }

    // MARK: - Inquiry Threads

    func sendInquiry(
        toCreatorId: String,
        subject: String,
        message: String,
        type: InquiryType,
        relatedItemId: String? = nil
    ) async throws {
        guard let userId = currentUserId,
              let userName = Auth.auth().currentUser?.displayName ?? Auth.auth().currentUser?.email else { return }
        let threadId = UUID().uuidString
        let thread = StudioInquiryThread(
            creatorId: toCreatorId,
            inquirerId: userId,
            inquirerName: userName,
            subject: subject,
            threadType: type,
            relatedItemId: relatedItemId,
            status: InquiryStatus.open,
            lastMessage: message,
            lastMessageAt: Date(),
            isReadByCreator: false,
            isReadByInquirer: true,
            isArchived: false,
            moderationFlag: false,
            createdAt: Date()
        )
        let encoded = try Firestore.Encoder().encode(thread)
        try await db.collection("inquiryThreads").document(threadId).setData(encoded)
    }

    func fetchMyInquiryThreads() async -> [StudioInquiryThread] {
        guard let userId = currentUserId else { return [] }
        guard let snap = try? await db.collection("inquiryThreads")
            .whereField("creatorId", isEqualTo: userId)
            .order(by: "lastMessageAt", descending: true)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioInquiryThread.self) }
    }

    func markThreadRead(_ threadId: String, asCreator: Bool) async throws {
        let field = asCreator ? "isReadByCreator" : "isReadByInquirer"
        try await db.collection("inquiryThreads").document(threadId).updateData([field: true])
    }

    // MARK: - Discovery

    func fetchFeaturedCreators(limit: Int = 10) async -> [StudioProfile] {
        guard let snap = try? await db.collection("studioProfiles")
            .whereField("isPublished", isEqualTo: true)
            .whereField("moderationState", isEqualTo: ModerationState.active.rawValue)
            .order(by: "featuredOrder")
            .limit(to: limit)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioProfile.self) }
    }

    func fetchFeaturedServices(limit: Int = 10) async -> [StudioService_] {
        guard let snap = try? await db.collection("studioServices")
            .whereField("isAvailable", isEqualTo: true)
            .whereField("isPromoted", isEqualTo: true)
            .limit(to: limit)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioService_.self) }
    }

    func fetchOpenCommissions(limit: Int = 20) async -> [StudioProfile] {
        guard let snap = try? await db.collection("studioProfiles")
            .whereField("isOpenForCommissions", isEqualTo: true)
            .whereField("isPublished", isEqualTo: true)
            .limit(to: limit)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioProfile.self) }
    }

    func searchCreators(query: String, category: StudioCategory? = nil) async -> [StudioProfile] {
        var ref: Query = db.collection("studioProfiles")
            .whereField("isPublished", isEqualTo: true)
            .whereField("moderationState", isEqualTo: ModerationState.active.rawValue)

        if let category = category {
            ref = ref.whereField("categories", arrayContains: category.rawValue)
        }

        guard let snap = try? await ref.limit(to: 30).getDocuments() else { return [] }
        let all = snap.documents.compactMap { try? $0.data(as: StudioProfile.self) }

        // Client-side text filter (Algolia handles production search)
        let lowQuery = query.lowercased()
        return all.filter { profile in
            profile.displayName.lowercased().contains(lowQuery) ||
            profile.tagline.lowercased().contains(lowQuery) ||
            profile.searchKeywords.contains { $0.lowercased().contains(lowQuery) }
        }
    }

    // MARK: - Analytics Logging

    func logAnalyticsEvent(_ event: StudioAnalyticsEvent) {
        Task {
            let docId = UUID().uuidString
            guard let encoded = try? Firestore.Encoder().encode(event) else { return }
            try? await db.collection("studioAnalyticsEvents").document(docId).setData(encoded)
        }
    }

    func logView(creatorId: String, targetId: String, targetType: String, surface: String) {
        guard let userId = currentUserId else { return }
        let event = StudioAnalyticsEvent(
            creatorId: creatorId,
            eventType: .profileView,
            targetId: targetId,
            targetType: targetType,
            viewerId: userId,
            referrerSurface: surface,
            sessionId: UUID().uuidString,
            createdAt: Date()
        )
        logAnalyticsEvent(event)
    }

    // MARK: - Moderation: Report

    func reportStudioContent(
        targetId: String,
        targetType: String,
        reason: ModerationReason,
        description: String?
    ) async throws {
        guard let userId = currentUserId else { return }
        let flag = StudioModerationFlag(
            targetId: targetId,
            targetType: targetType,
            reporterId: userId,
            reason: reason,
            flagDescription: description,
            status: .pending,
            createdAt: Date()
        )
        let docId = UUID().uuidString
        let encoded = try Firestore.Encoder().encode(flag)
        try await db.collection("studioModerationFlags").document(docId).setData(encoded)
    }

    // MARK: - Private: Notifications

    private func sendStudioNotification(
        toUserId: String,
        type: StudioNotificationType,
        title: String,
        body: String,
        relatedId: String?
    ) async {
        var data: [String: Any] = [
            "userId": toUserId,
            "type": "studio_\(type.rawValue)",
            "title": title,
            "body": body,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let relatedId = relatedId { data["relatedId"] = relatedId }
        _ = try? await db.collection("studioNotifications").addDocument(data: data)
    }

    // MARK: - Earnings

    func fetchEarningsSummary() async -> StudioEarningsSummary? {
        guard let userId = currentUserId else { return nil }
        guard let snap = try? await db.collection("creatorEarnings")
            .whereField("creatorId", isEqualTo: userId)
            .order(by: "periodEnd", descending: true)
            .limit(to: 1)
            .getDocuments() else { return nil }
        return snap.documents.first.flatMap { try? $0.data(as: StudioEarningsSummary.self) }
    }

    func fetchTransactions(limit: Int = 50) async -> [StudioTransaction] {
        guard let userId = currentUserId else { return [] }
        guard let snap = try? await db.collection("creatorTransactions")
            .whereField("creatorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: StudioTransaction.self) }
    }
}

// MARK: - StudioService_ (Firestore model, renamed to avoid naming conflict with StudioService class)

struct StudioService_: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var title: String
    var category: StudioCategory
    var shortDescription: String
    var fullDescription: String
    var pricingType: ServicePricingType
    var startingPrice: Double?
    var currency: String
    var turnaroundDays: Int?
    var revisionsIncluded: Int
    var deliveryMethod: DeliveryMethod
    var sampleWorkIds: [String]
    var isAvailable: Bool
    var availabilityNote: String?
    var requiresDeposit: Bool
    var depositPercent: Int
    var moderationState: ModerationState
    var inquiryCount: Int
    var completionCount: Int
    var responseRatePercent: Int
    var createdAt: Date
    var updatedAt: Date
    var searchKeywords: [String]
    var isPromoted: Bool
    var promotionExpiry: Date?
}

// MARK: - Studio Notification Types

enum StudioNotificationType: String {
    case newInquiry, commissionRequest, bookingRequest, productSold
    case payoutSent, payoutFailed, supportReceived, collaborationInvite
    case opportunityMatch, promotionApproved, moderationAction
}

// MARK: - Discovery Ranking

struct StudioRankingEngine {
    /// Rank creators by quality signals, not vanity
    static func rank(_ profiles: [StudioProfile], context: RankingContext) -> [StudioProfile] {
        return profiles.sorted { a, b in
            let scoreA = computeScore(a, context: context)
            let scoreB = computeScore(b, context: context)
            return scoreA > scoreB
        }
    }

    static func computeScore(_ profile: StudioProfile, context: RankingContext) -> Double {
        var score = 0.0

        // Trust score (most important: 40%)
        score += profile.trustScore * 0.40

        // Verification bonus (15%)
        if profile.isVerified { score += 0.15 }

        // Open for work bonus (10%)
        if profile.isOpenForWork || profile.isOpenForCommissions { score += 0.10 }

        // Boosted placement (15%) — transparent, not hidden
        if let expiry = profile.boostExpiry, expiry > Date() { score += 0.15 }

        // Featured order bonus (20%)
        if let order = profile.featuredOrder {
            score += max(0.0, 0.20 - Double(order) * 0.01)
        }

        // Recency bonus (up to 5%)
        let daysSinceUpdate = Date().timeIntervalSince(profile.updatedAt) / 86400
        score += max(0.0, 0.05 - daysSinceUpdate * 0.001)

        return score
    }

    enum RankingContext {
        case discovery, search, category, local
    }
}
