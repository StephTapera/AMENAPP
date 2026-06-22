// CreatorViewModel.swift — AMEN App
// View model for Creator Economic Graph

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class CreatorViewModel: ObservableObject {
    @Published var profile: CreatorProfile = .empty
    @Published var isLoading = false
    @Published var isEnablingCreator = false

    private lazy var db = Firestore.firestore()

    var formattedMonthlyRevenue: String { "$\(String(format: "%.0f", profile.monthlyRevenue))" }
    var formattedLifetime: String { "$\(String(format: "%.0f", profile.lifetimeEarnings))" }
    var formattedProjection: String { "$\(String(format: "%.0f", profile.aiRevenueProjection))" }

    func load(userId: String? = nil) async {
        let uid = userId ?? Auth.auth().currentUser?.uid ?? ""
        isLoading = true
        defer { isLoading = false }
        do {
            let doc = try await db.collection("creatorProfiles").document(uid).getDocument()
            if let p = try? doc.data(as: CreatorProfile.self) {
                profile = p
            } else {
                // Seed empty profile for new creators
                profile = CreatorProfile(
                    userId: uid,
                    monthlyRevenue: 0, lifetimeEarnings: 0,
                    subscriberCount: 0, subscriptionPrice: nil,
                    subscriptionBenefits: [], tipsEnabled: true,
                    digitalGoods: [],
                    aiRevenueProjection: 0,
                    aiNextMoveRecommendation: "Post 3x per week to build momentum.",
                    trustScore: 0.5,
                    verificationStatus: .unverified,
                    revenueHistory: sampleHistory()
                )
            }
        } catch {
            dlog("⚠️ CreatorViewModel.load: \(error)")
        }
    }

    func enableCreator() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isEnablingCreator = true
        defer { isEnablingCreator = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let p = CreatorProfile(
            userId: uid, monthlyRevenue: 0, lifetimeEarnings: 0,
            subscriberCount: 0, subscriptionPrice: nil,
            subscriptionBenefits: [], tipsEnabled: true,
            digitalGoods: [], aiRevenueProjection: 0,
            aiNextMoveRecommendation: "Start by posting consistently. Your first 10 posts are the foundation.",
            trustScore: 0.5, verificationStatus: .unverified,
            revenueHistory: sampleHistory()
        )
        if let data = try? Firestore.Encoder().encode(p) {
            do {
                try await db.collection("creatorProfiles").document(uid).setData(data)
            } catch {
                print("CreatorViewModel: failed to seed creator profile — \(error.localizedDescription)")
            }
        }
        profile = p
    }

    func setSubscriptionPrice(_ price: Double?) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        profile.subscriptionPrice = price
        do {
            try await db.collection("creatorProfiles").document(uid)
                .updateData(["subscriptionPrice": price as Any])
        } catch {
            print("CreatorViewModel: failed to update subscriptionPrice — \(error.localizedDescription)")
        }
    }

    func toggleTips() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        profile.tipsEnabled.toggle()
        do {
            try await db.collection("creatorProfiles").document(uid)
                .updateData(["tipsEnabled": profile.tipsEnabled])
        } catch {
            print("CreatorViewModel: failed to update tipsEnabled — \(error.localizedDescription)")
        }
    }

    func refreshAIProjection() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let system = """
        You are a creator economy AI advisor for AMEN, a Christian social app. \
        Given a creator's current metrics, project their next month's revenue \
        and give ONE specific actionable recommendation. \
        Respond ONLY with JSON: {"projection": 0.0, "recommendation": "..."}.
        """
        let metrics = "Subscribers: \(profile.subscriberCount), Monthly revenue: $\(profile.monthlyRevenue), Tips enabled: \(profile.tipsEnabled)"
        guard let result = try? await Functions.functions()
            .httpsCallable("bereanChatProxy")
            .call(["systemPrompt": system, "userMessage": metrics, "maxTokens": 150]),
              let dict = result.data as? [String: Any],
              let text = dict["text"] as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        profile.aiRevenueProjection = json["projection"] as? Double ?? 0
        profile.aiNextMoveRecommendation = json["recommendation"] as? String ?? ""
        do {
            try await db.collection("creatorProfiles").document(uid).updateData([
                "aiRevenueProjection": profile.aiRevenueProjection,
                "aiNextMoveRecommendation": profile.aiNextMoveRecommendation
            ])
        } catch {
            print("CreatorViewModel: failed to persist AI projection — \(error.localizedDescription)")
        }
    }

    func sendTip(toCreatorId: String, amount: Double, message: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // In production this would go through Stripe/IAP. For now, record the tip.
        try await db.collection("tips").addDocument(data: [
            "fromUserId": uid,
            "toCreatorId": toCreatorId,
            "amount": amount,
            "message": message as Any,
            "createdAt": FieldValue.serverTimestamp()
        ])
        // Update creator's lifetime earnings
        try await db.collection("creatorProfiles").document(toCreatorId)
            .updateData(["lifetimeEarnings": FieldValue.increment(amount)])
    }

    private func sampleHistory() -> [RevenuePoint] {
        let months = ["Jan","Feb","Mar","Apr","May","Jun"]
        return months.enumerated().map { RevenuePoint(id: "\($0.offset)", month: $0.element, amount: 0) }
    }
}
