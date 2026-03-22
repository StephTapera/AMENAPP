// SpiritualSeasonService.swift
// AMENAPP
//
// Spiritual season detection:
//   - Fetches last 10 prayer requests + 5 church note key points
//   - Sends to Claude (via bereanChatProxy) → classified season
//   - Caches in UserDefaults with 7-day TTL
//   - Used by FindChurchView ranking: +0.25 boost for matching churches
//   - Adds "Recommended for your current season" text on boosted cards

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - SpiritualSeason

enum SpiritualSeason: String, CaseIterable {
    case searching    = "searching"
    case grieving     = "grieving"
    case rebuilding   = "rebuilding"
    case hungry       = "hungry"
    case plateaued    = "plateaued"
    case serving      = "serving"
    case doubting     = "doubting"
    case thriving     = "thriving"
    case unknown      = ""
}

// MARK: - SpiritualSeasonService

@MainActor
final class SpiritualSeasonService: ObservableObject {
    static let shared = SpiritualSeasonService()

    @Published var season: SpiritualSeason = .unknown
    @AppStorage("spiritualSeasonRaw")   private var seasonRaw: String     = ""
    @AppStorage("spiritualSeasonDate")  private var seasonDateTS: Double  = 0

    private let db = Firestore.firestore()
    private let cacheTTL: TimeInterval = 7 * 86400  // 7 days

    // MARK: - Public API

    func detectIfNeeded() async {
        if !seasonRaw.isEmpty,
           Date().timeIntervalSince1970 - seasonDateTS < cacheTTL {
            season = SpiritualSeason(rawValue: seasonRaw) ?? .unknown
            return
        }
        await detect()
    }

    func detect() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let combined = await gatherContext(uid: uid)
        guard !combined.isEmpty else { return }
        let classified = await classifySeason(context: combined)
        season      = classified
        seasonRaw   = classified.rawValue
        seasonDateTS = Date().timeIntervalSince1970
        // Also write to AppStorage key used by SeasonRecommendationText
        UserDefaults.standard.set(classified.rawValue, forKey: "spiritualSeason")
    }

    // MARK: - Boost score

    /// Returns additional 0.25 match score boost if church specializes in current season.
    func seasonBoost(for church: ChurchEntity, enhancements: ChurchEnhancementData?) -> Double {
        guard season != .unknown,
              let specs = enhancements?.seasonSpecializations,
              specs.contains(season.rawValue) else { return 0 }
        return 0.25
    }

    // MARK: - Private

    private func gatherContext(uid: String) async -> String {
        var parts: [String] = []

        // Last 10 prayer requests
        if let snap = try? await db.collection("prayers")
            .whereField("userId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .getDocuments() {
            let prayers = snap.documents.compactMap { $0.data()["text"] as? String }
            if !prayers.isEmpty {
                parts.append("Prayer requests:\n" + prayers.joined(separator: "\n"))
            }
        }

        // Last 5 church note key points
        if let snap = try? await db.collection("churchNotes")
            .whereField("userId", isEqualTo: uid)
            .order(by: "date", descending: true)
            .limit(to: 5)
            .getDocuments() {
            let kps = snap.documents.flatMap { ($0.data()["keyPoints"] as? [String]) ?? [] }
            if !kps.isEmpty {
                parts.append("Recent sermon key points:\n" + kps.prefix(15).joined(separator: "\n"))
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private func classifySeason(context: String) async -> SpiritualSeason {
        let prompt = """
        Based on these prayer requests and sermon notes, classify this person's current spiritual season into exactly one of: searching, grieving, rebuilding, hungry, plateaued, serving, doubting, thriving. Return only the single word.

        \(context.prefix(2000))
        """
        guard let result = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar) else {
            return .unknown
        }
        let word = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.whitespaces)
            .first ?? ""
        return SpiritualSeason(rawValue: word) ?? .unknown
    }
}
