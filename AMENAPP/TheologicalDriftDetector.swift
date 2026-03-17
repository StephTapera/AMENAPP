//
//  TheologicalDriftDetector.swift
//  AMENAPP
//
//  Detects theological drift in user-generated content by checking
//  alignment with core orthodox Christian doctrines.
//  Used to flag content for pastoral review, not for censorship.
//

import Foundation

class TheologicalDriftDetector {
    static let shared = TheologicalDriftDetector()
    private init() {}

    struct DriftAnalysis {
        let score: Float          // 0.0 = orthodox, 1.0 = significant drift
        let flags: [DriftFlag]
        let suggestion: String?   // Pastoral suggestion if needed
    }

    struct DriftFlag {
        let category: DriftCategory
        let matchedPhrase: String
        let severity: Severity

        enum Severity: String { case info, warning, concern }
    }

    enum DriftCategory: String {
        case prosperity       = "Prosperity Gospel"
        case universalism     = "Universalism"
        case legalism         = "Legalism"
        case gnosticism       = "Gnosticism"
        case politicization   = "Political Christianity"
        case exclusivism      = "Harmful Exclusivism"
        case manipulation     = "Spiritual Manipulation"
    }

    // Pattern dictionaries (keyword-based, not AI — fast and deterministic)
    private let patterns: [DriftCategory: [(phrase: String, severity: DriftFlag.Severity)]] = [
        .prosperity: [
            ("name it and claim it", .warning),
            ("sow a seed", .info),
            ("god wants you rich", .warning),
            ("financial breakthrough guaranteed", .concern),
            ("poverty is a curse", .warning),
            ("your faith determines your wealth", .concern),
        ],
        .universalism: [
            ("all religions lead to god", .warning),
            ("everyone goes to heaven", .concern),
            ("there is no hell", .concern),
            ("all paths are valid", .warning),
        ],
        .legalism: [
            ("you must follow these rules to be saved", .concern),
            ("salvation requires works", .warning),
            ("if you sin you lose salvation", .warning),
            ("true christians don't", .info),
        ],
        .politicization: [
            ("jesus would vote for", .concern),
            ("god's political party", .concern),
            ("real christians support", .warning),
            ("biblical candidate", .warning),
        ],
        .manipulation: [
            ("if you don't share this", .concern),
            ("god told me to tell you to give", .concern),
            ("type amen or bad things", .concern),
            ("god will punish you if you scroll past", .concern),
            ("share in 10 seconds", .warning),
        ],
    ]

    /// Analyze text for theological drift indicators
    func analyze(_ text: String) -> DriftAnalysis {
        let lower = text.lowercased()
        var flags: [DriftFlag] = []
        var totalScore: Float = 0

        for (category, categoryPatterns) in patterns {
            for (phrase, severity) in categoryPatterns {
                if lower.contains(phrase) {
                    flags.append(DriftFlag(
                        category: category,
                        matchedPhrase: phrase,
                        severity: severity
                    ))

                    switch severity {
                    case .info:    totalScore += 0.05
                    case .warning: totalScore += 0.15
                    case .concern: totalScore += 0.30
                    }
                }
            }
        }

        let clampedScore = min(1.0, totalScore)

        var suggestion: String? = nil
        if clampedScore >= 0.3 {
            let topCategory = flags.max(by: { severityWeight($0.severity) < severityWeight($1.severity) })?.category
            suggestion = pastoralSuggestion(for: topCategory)
        }

        return DriftAnalysis(score: clampedScore, flags: flags, suggestion: suggestion)
    }

    private func severityWeight(_ severity: DriftFlag.Severity) -> Int {
        switch severity {
        case .info: return 1
        case .warning: return 2
        case .concern: return 3
        }
    }

    private func pastoralSuggestion(for category: DriftCategory?) -> String {
        switch category {
        case .prosperity:
            return "Consider reviewing what Scripture says about wealth and contentment (1 Timothy 6:6-10, Matthew 6:19-21)."
        case .universalism:
            return "John 14:6 and Acts 4:12 speak to the exclusivity of Christ as the way to salvation."
        case .legalism:
            return "Ephesians 2:8-9 reminds us that salvation is by grace through faith, not by works."
        case .politicization:
            return "Jesus' kingdom is not of this world (John 18:36). Consider separating political opinion from doctrine."
        case .manipulation:
            return "2 Corinthians 9:7 says God loves a cheerful giver — never compelled or manipulated."
        case .gnosticism:
            return "1 John 4:2 affirms the physical incarnation of Christ."
        case .exclusivism:
            return "Galatians 3:28 reminds us there is neither Jew nor Gentile in Christ."
        case nil:
            return "Consider reviewing this content with a trusted pastor or church leader."
        }
    }
}
