// CharityNavigatorService.swift
// AMENAPP
//
// Live Charity Navigator API integration.
// Fetches financial health scores, accountability ratings, and program expense ratios.
//
// SETUP: Replace `apiKey` with your Charity Navigator API key from:
// https://www.charitynavigator.org/index.cfm?bay=content.view&cpid=1397
//
// Free tier: 1,000 requests/day
// Caches results to Firestore for 30 days to minimize API usage.
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - Charity Navigator Rating

struct CharityRating: Codable {
    let ein: String              // IRS Employer ID
    let name: String
    let overallScore: Double?    // 0–100
    let starRating: Int?         // 0–4 stars
    let financialScore: Double?
    let accountabilityScore: Double?
    let programExpensePercent: Double? // % spent on programs vs admin
    let fundraisingExpensePercent: Double?
    let adminExpensePercent: Double?
    let cachedAt: Date?

    var starString: String {
        guard let stars = starRating else { return "" }
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: max(0, 4 - stars))
    }

    var programLabel: String {
        guard let pct = programExpensePercent else { return "" }
        return String(format: "%.0f%% to programs", pct)
    }
}

// MARK: - Service

@MainActor
class CharityNavigatorService: ObservableObject {
    static let shared = CharityNavigatorService()

    // REPLACE with your actual Charity Navigator API key
    private let apiKey = "YOUR_CHARITY_NAVIGATOR_API_KEY"
    private let baseURL = "https://api.charitynavigator.org/v2"
    private let db = Firestore.firestore()
    private let cacheTTLDays: Double = 30

    @Published var ratings: [String: CharityRating] = [:]
    @Published var isLoading: Bool = false

    private init() {}

    // MARK: - Public API

    /// Fetch rating for a nonprofit by EIN (Employer Identification Number).
    /// Returns cached value if fresh, otherwise fetches from API.
    func rating(for ein: String) -> CharityRating? {
        ratings[ein]
    }

    func fetchRating(ein: String) async {
        if let cached = ratings[ein], let cachedAt = cached.cachedAt,
           Date().timeIntervalSince(cachedAt) < cacheTTLDays * 86400 {
            return // fresh cache
        }

        // Check Firestore cache first
        if let firestoreCached = await loadFromFirestore(ein: ein) {
            ratings[ein] = firestoreCached
            return
        }

        // Fetch from API
        await fetchFromAPI(ein: ein)
    }

    func prefetchAll(eins: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for ein in eins {
                group.addTask { await self.fetchRating(ein: ein) }
            }
        }
    }

    // MARK: - API Fetch

    private func fetchFromAPI(ein: String) async {
        guard apiKey != "YOUR_CHARITY_NAVIGATOR_API_KEY" else { return }

        guard let url = URL(string: "\(baseURL)/Organizations/\(ein)?apikey=\(apiKey)&app_id=amen_app") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let rating = parseRating(ein: ein, json: json)
                ratings[ein] = rating
                await saveToFirestore(rating: rating)
            }
        } catch {
            dlog("⚠️ CharityNavigator fetch failed for \(ein): \(error.localizedDescription)")
        }
    }

    private func parseRating(ein: String, json: [String: Any]) -> CharityRating {
        let overallScore = json["overallScore"] as? Double
        let starRating = json["currentRating"] as? Int
        let financialScore = (json["financialRating"] as? [String: Any])?["score"] as? Double
        let accountabilityScore = (json["accountabilityRating"] as? [String: Any])?["score"] as? Double

        var programPct: Double? = nil
        var fundraisingPct: Double? = nil
        var adminPct: Double? = nil

        if let financials = json["financialRating"] as? [String: Any],
           let breakdown = financials["expenseBreakdown"] as? [String: Any] {
            programPct     = breakdown["programExpenses"] as? Double
            fundraisingPct = breakdown["fundraisingExpenses"] as? Double
            adminPct       = breakdown["managementExpenses"] as? Double
        }

        return CharityRating(
            ein: ein,
            name: json["charityName"] as? String ?? "",
            overallScore: overallScore,
            starRating: starRating,
            financialScore: financialScore,
            accountabilityScore: accountabilityScore,
            programExpensePercent: programPct,
            fundraisingExpensePercent: fundraisingPct,
            adminExpensePercent: adminPct,
            cachedAt: Date()
        )
    }

    // MARK: - Firestore Cache

    private func loadFromFirestore(ein: String) async -> CharityRating? {
        do {
            let doc = try await db.collection("charityRatings").document(ein).getDocument()
            guard let data = doc.data() else { return nil }
            let cachedDate = (data["cachedAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
            guard Date().timeIntervalSince(cachedDate) < cacheTTLDays * 86400 else { return nil }
            return CharityRating(
                ein: ein,
                name: data["name"] as? String ?? "",
                overallScore: data["overallScore"] as? Double,
                starRating: data["starRating"] as? Int,
                financialScore: data["financialScore"] as? Double,
                accountabilityScore: data["accountabilityScore"] as? Double,
                programExpensePercent: data["programExpensePercent"] as? Double,
                fundraisingExpensePercent: data["fundraisingExpensePercent"] as? Double,
                adminExpensePercent: data["adminExpensePercent"] as? Double,
                cachedAt: cachedDate
            )
        } catch {
            return nil
        }
    }

    private func saveToFirestore(rating: CharityRating) async {
        var data: [String: Any] = [
            "ein": rating.ein,
            "name": rating.name,
            "cachedAt": Timestamp(date: Date())
        ]
        if let v = rating.overallScore          { data["overallScore"] = v }
        if let v = rating.starRating            { data["starRating"] = v }
        if let v = rating.financialScore        { data["financialScore"] = v }
        if let v = rating.accountabilityScore   { data["accountabilityScore"] = v }
        if let v = rating.programExpensePercent { data["programExpensePercent"] = v }
        if let v = rating.fundraisingExpensePercent { data["fundraisingExpensePercent"] = v }
        if let v = rating.adminExpensePercent   { data["adminExpensePercent"] = v }
        try? await db.collection("charityRatings").document(rating.ein).setData(data, merge: true)
    }
}

// MARK: - EIN Map for known nonprofits

extension ChristianNonprofit {
    /// IRS Employer Identification Number for Charity Navigator lookup.
    /// Add more as needed: https://www.charitynavigator.org
    var ein: String? {
        switch name {
        case "Samaritan's Purse":      return "58-1437002"
        case "World Vision":           return "95-1922279"
        case "Convoy of Hope":         return "44-0709921"
        case "charity: water":         return "22-3936753"
        case "Compassion International": return "36-2423707"
        case "Food for the Hungry":    return "95-2681452"
        case "World Relief":           return "23-6393344"
        case "International Justice Mission": return "54-1722887"
        case "A21 Campaign":           return "27-0373544"
        case "Open Doors USA":         return "95-6111498"
        default: return nil
        }
    }
}
