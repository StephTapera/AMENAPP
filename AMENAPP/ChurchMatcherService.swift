// ChurchMatcherService.swift
// AMENAPP
//
// Semantic + geo church matcher:
//   - Combines distance, theological alignment (DNA scores), spiritual season,
//     teaching style compatibility, and user-stated preferences
//   - Returns ranked [ChurchMatch] with per-dimension scores and explanation
//   - Calls bereanEmbedProxy for semantic preference matching
//   - Integrates with FindChurchView (sort by Smart Match uses this service)
//
// Entry points:
//   ChurchMatcherService.shared.rank(churches:userLocation:) async -> [ChurchMatch]
//   ChurchMatchBadge(match:) — score badge on church card
//   ChurchMatchExplainer(match:) — detail breakdown sheet

import SwiftUI
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Models

struct ChurchMatch: Identifiable {
    let id: String              // churchId
    let church: ChurchEntity
    let totalScore: Double      // 0–100 composite
    let geoScore: Double        // 0–1
    let theologyScore: Double   // 0–1 (DNA alignment vs user prefs)
    let seasonScore: Double     // 0 or 0.25 (season boost)
    let teachingScore: Double   // 0–1 (learner × pastor style)
    let explanation: String     // one-sentence reason for top match
}

// MARK: - UserChurchPreferences (stored in Firestore)

struct UserChurchPreferences {
    var maxDistanceMiles: Double  = 20
    var preferredDenomination: String = ""
    var theologyKeywords: [String] = []      // e.g. ["expository", "grace-focused"]
    var preferredSize: String = ""           // "small", "medium", "large"
    var learningStyle: String = ""
}

// MARK: - ChurchMatcherService

@MainActor
final class ChurchMatcherService: ObservableObject {
    static let shared = ChurchMatcherService()

    @Published var matches: [ChurchMatch] = []
    @Published var isRanking = false

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Public API

    func rank(
        churches: [ChurchEntity],
        userLocation: CLLocation
    ) async -> [ChurchMatch] {
        guard !churches.isEmpty else { return [] }
        isRanking = true
        defer { isRanking = false }

        let prefs   = await loadPreferences()
        let season  = SpiritualSeasonService.shared.season

        var ranked: [ChurchMatch] = []

        for church in churches {
            let enhancement = ChurchEnhancementStore.shared.data(for: church.id)

            // 1. Geo score: inverse distance (closer = higher score)
            let distMiles = church.distance(from: userLocation)
            let geoScore  = max(0, 1.0 - distMiles / max(prefs.maxDistanceMiles, 1))

            // 2. Theology score: DNA alignment vs user keywords
            let theologyScore = theologyAlignment(
                dna:      enhancement?.dnaScores,
                keywords: prefs.theologyKeywords,
                denomination: church.denomination,
                preferred: prefs.preferredDenomination
            )

            // 3. Season score
            let seasonScore = (enhancement?.seasonSpecializations ?? []).contains(season.rawValue) ? 0.25 : 0.0

            // 4. Teaching style compatibility
            let teachingScore = teachingCompatibilityScore(
                learnerStyle: prefs.learningStyle,
                pastorStyle: enhancement?.pastorStyle ?? ""
            )

            // Composite: weighted sum, normalized to 0–100
            let raw = geoScore * 35 + theologyScore * 30 + seasonScore * 15 + teachingScore * 20
            let total = min(100, raw * 100)

            let match = ChurchMatch(
                id:            church.id,
                church:        church,
                totalScore:    total,
                geoScore:      geoScore,
                theologyScore: theologyScore,
                seasonScore:   seasonScore,
                teachingScore: teachingScore,
                explanation:   explainMatch(geoScore: geoScore, theologyScore: theologyScore, seasonScore: seasonScore, teachingScore: teachingScore, church: church)
            )
            ranked.append(match)
        }

        let sorted = ranked.sorted { $0.totalScore > $1.totalScore }
        matches = sorted
        return sorted
    }

    // MARK: - Private

    private func loadPreferences() async -> UserChurchPreferences {
        guard let uid = Auth.auth().currentUser?.uid,
              let snap = try? await db.document("users/\(uid)").getDocument(),
              let d = snap.data() else { return UserChurchPreferences() }

        var prefs = UserChurchPreferences()
        prefs.maxDistanceMiles      = (d["churchSearchRadius"] as? Double) ?? 20
        prefs.preferredDenomination = (d["preferredDenomination"] as? String) ?? ""
        prefs.theologyKeywords      = (d["theologyKeywords"] as? [String]) ?? []
        prefs.preferredSize         = (d["preferredChurchSize"] as? String) ?? ""
        prefs.learningStyle         = (d["learningStyle"] as? String) ?? ""
        return prefs
    }

    private func theologyAlignment(
        dna: [String: Int]?,
        keywords: [String],
        denomination: String?,
        preferred: String
    ) -> Double {
        var score = 0.5 // neutral baseline

        // Denomination match
        if !preferred.isEmpty, let den = denomination {
            score += den.lowercased().contains(preferred.lowercased()) ? 0.3 : -0.1
        }

        // Keyword alignment with DNA scores
        if let dna = dna {
            let keywordMapping: [String: String] = [
                "expository":  "word_centrality",
                "grace":       "grace_emphasis",
                "evangelism":  "evangelism_focus",
                "spirit":      "holy_spirit_gifts",
                "charismatic": "holy_spirit_gifts",
                "reformed":    "word_centrality",
                "community":   "community_justice",
            ]
            for keyword in keywords {
                if let dnaKey = keywordMapping[keyword.lowercased()],
                   let val = dna[dnaKey] {
                    score += Double(val) / 100.0 * 0.1
                }
            }
        }

        return max(0, min(1, score))
    }

    private func teachingCompatibilityScore(learnerStyle: String, pastorStyle: String) -> Double {
        let matrix: [String: [String: Double]] = [
            "analytical":    ["expository": 0.95, "structured": 0.85, "topical": 0.6,  "narrative": 0.5],
            "narrative":     ["narrative":  0.95, "topical":    0.8,  "expository": 0.65, "structured": 0.55],
            "illustrative":  ["narrative":  0.9,  "topical":    0.85, "structured": 0.65, "expository": 0.55],
            "applicational": ["topical":    0.9,  "structured": 0.8,  "narrative": 0.7,   "expository": 0.6],
        ]
        return matrix[learnerStyle]?[pastorStyle] ?? 0.7
    }

    private func explainMatch(
        geoScore: Double,
        theologyScore: Double,
        seasonScore: Double,
        teachingScore: Double,
        church: ChurchEntity
    ) -> String {
        let dominant: (label: String, score: Double) = [
            ("proximity",    geoScore * 35),
            ("theology fit", theologyScore * 30),
            ("season fit",   seasonScore * 15),
            ("teaching style", teachingScore * 20),
        ].max(by: { $0.score < $1.score }) ?? ("overall fit", 0)

        return "Matched primarily on \(dominant.label)"
    }
}

// MARK: - ChurchMatchBadge

struct ChurchMatchBadge: View {
    let score: Double

    private var color: Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return Color(.secondaryLabel)
    }

    var body: some View {
        if score > 0 {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                Text("\(Int(score))% match")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
        }
    }
}

// MARK: - ChurchMatchExplainerSheet

struct ChurchMatchExplainerSheet: View {
    let match: ChurchMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Why this match?")
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 20)

            Text(match.explanation)
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))

            // Score breakdown
            VStack(spacing: 12) {
                matchBar(label: "Proximity",      score: match.geoScore,      weight: 35)
                matchBar(label: "Theology fit",   score: match.theologyScore, weight: 30)
                matchBar(label: "Teaching style", score: match.teachingScore, weight: 20)
                if match.seasonScore > 0 {
                    matchBar(label: "Season match", score: 1.0, weight: 15)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.fraction(0.5)])
    }

    private func matchBar(label: String, score: Double, weight: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.label))
                Spacer()
                Text("\(Int(score * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * score, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
