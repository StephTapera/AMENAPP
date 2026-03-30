//
//  ViralityPredictorService.swift
//  AMENAPP
//
//  Real-time resonance predictor for post composition.
//  Shows how likely content is to resonate with the community,
//  framed spiritually rather than as vanity metrics.
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Models

struct ResonanceScore {
    let raw: Int // 0-100

    var label: String {
        switch raw {
        case 75...:  return "This could move someone today"
        case 50..<75: return "This will encourage others"
        case 25..<50: return "Good start"
        default:      return ""
        }
    }

    var icon: String {
        switch raw {
        case 75...:  return "flame.fill"
        case 50..<75: return "heart.fill"
        case 25..<50: return "sparkles"
        default:      return ""
        }
    }

    var color: Color {
        switch raw {
        case 75...:  return .orange
        case 50..<75: return Color(red: 1.0, green: 0.4, blue: 0.5) // brand pink
        case 25..<50: return .purple
        default:      return .clear
        }
    }

    var tip: String? {
        switch raw {
        case 75...:  return "Looks great — your community will appreciate this"
        case 50..<75: return nil
        case 25..<50: return "A bit more context helps others connect"
        default:      return nil
        }
    }
}

struct EngagementPattern {
    let category: String
    let avgAmens: Float
    let avgComments: Float
    let hasScriptureTagBoost: Float // multiplier
    let lengthSweet: ClosedRange<Int> // 80...300 chars
    let topThemes: [String]
}

// MARK: - Service

class ViralityPredictorService {
    static let shared = ViralityPredictorService()

    private var patterns: [EngagementPattern] = []
    private var patternsLoaded = false

    private init() {}

    // MARK: - Load Patterns (once per session)

    /// Load engagement patterns from recent posts. Call on app launch (background).
    func loadPatterns() async {
        guard !patternsLoaded else { return }

        let db = Firestore.firestore()

        // Fetch last 500 posts with engagement data
        guard let snapshot = try? await db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: 500)
            .getDocuments() else { return }

        var categoryStats: [String: (amenTotal: Float, commentTotal: Float, count: Float)] = [:]

        for doc in snapshot.documents {
            let data = doc.data()
            let category = data["category"] as? String ?? "openTable"
            let amens = Float(data["amenCount"] as? Int ?? 0)
            let comments = Float(data["commentCount"] as? Int ?? 0)

            var stats = categoryStats[category] ?? (0, 0, 0)
            stats.amenTotal += amens
            stats.commentTotal += comments
            stats.count += 1
            categoryStats[category] = stats
        }

        patterns = categoryStats.map { category, stats in
            EngagementPattern(
                category: category,
                avgAmens: stats.count > 0 ? stats.amenTotal / stats.count : 0,
                avgComments: stats.count > 0 ? stats.commentTotal / stats.count : 0,
                hasScriptureTagBoost: 1.3,
                lengthSweet: 80...300,
                topThemes: []
            )
        }

        patternsLoaded = true
    }

    // MARK: - Predict Resonance

    /// Compute resonance score for text being composed.
    /// Runs synchronously — pure Swift math, no network call.
    func predictResonance(
        text: String,
        category: String,
        hasScripture: Bool
    ) -> ResonanceScore {
        var score = 0

        // Length score
        let len = text.count
        if (80...300).contains(len) { score += 30 }
        else if (40...79).contains(len) { score += 15 }
        else if len > 300 { score += 10 }

        // Scripture bonus
        if hasScripture { score += 25 }

        // Category base rate
        let pattern = patterns.first { $0.category == category }
        score += Int((pattern?.avgAmens ?? 0) * 2)

        // Keyword themes (positive signal words for AMEN community)
        let faithWords = [
            "grateful", "testimony", "faithful", "blessed", "answered",
            "miracle", "restored", "healed", "forgiven", "grace",
            "prayer", "worship", "praise", "amen", "glory",
            "breakthrough", "overcome", "purpose", "calling", "kingdom",
        ]
        let lower = text.lowercased()
        let matchCount = faithWords.filter { lower.contains($0) }.count
        score += min(20, matchCount * 5)

        // Personal story signal (first person + emotion = testimony pattern)
        let personalIndicators = ["i was", "god showed", "my testimony", "i realized", "he healed", "she prayed"]
        let personalMatch = personalIndicators.filter { lower.contains($0) }.count
        score += min(15, personalMatch * 5)

        // Question engagement (posts with questions get more comments)
        if text.contains("?") { score += 5 }

        return ResonanceScore(raw: min(100, score))
    }

    /// Contextual tip based on current composition state.
    func compositionTip(
        text: String,
        hasScripture: Bool,
        score: ResonanceScore
    ) -> String? {
        if !hasScripture && score.raw < 50 && text.count > 40 {
            return "Adding a scripture verse often increases impact"
        }
        if text.count < 40 && text.count > 10 {
            return "A bit more context helps others connect"
        }
        if score.raw > 75 {
            return "Looks great — your community will appreciate this"
        }
        return nil
    }
}

// MARK: - Resonance Indicator View

struct ResonanceIndicatorView: View {
    let text: String
    let category: String
    let hasScripture: Bool
    @AppStorage("showResonanceHints") private var showHints = true
    @State private var score = ResonanceScore(raw: 0)
    @State private var tip: String?
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        Group {
            if showHints && text.count > 40 && !score.label.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: score.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(score.color)

                        Text(score.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(score.color)
                            .contentTransition(.numericText())
                    }
                    .animation(.easeOut(duration: 0.3), value: score.raw)

                    if let tip {
                        Text(tip)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.animation(.easeIn(duration: 0.2)))
            }
        }
        .onChange(of: text) { _, newText in
            // 1.5s debounce
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let newScore = ViralityPredictorService.shared.predictResonance(
                        text: newText, category: category, hasScripture: hasScripture
                    )
                    withAnimation(.easeOut(duration: 0.3)) {
                        score = newScore
                        tip = ViralityPredictorService.shared.compositionTip(
                            text: newText, hasScripture: hasScripture, score: newScore
                        )
                    }
                }
            }
        }
    }
}
