// BereanShieldService.swift
// AMENAPP
//
// Berean Shield — real-time claim verification layer.
// Calls Cloud Function "bereanShieldAnalyze" with claim text.
// Returns ShieldAnalysis struct covering all 5 dimensions + verdict.
// Privacy-first: claim text is never stored locally or logged.

import SwiftUI
import Combine
import FirebaseFunctions

// MARK: - ShieldVerdict

enum ShieldVerdict: String, Codable {
    case verified       = "verified"
    case likelyTrue     = "likely_true"
    case misleading     = "misleading"
    case likelyFalse    = "likely_false"
    case falseClaim     = "false"
    case unverifiable   = "unverifiable"

    var displayLabel: String {
        switch self {
        case .verified:     return "Verified"
        case .likelyTrue:   return "Likely True"
        case .misleading:   return "Misleading"
        case .likelyFalse:  return "Likely False"
        case .falseClaim:   return "False"
        case .unverifiable: return "Unverifiable"
        }
    }

    var color: Color {
        switch self {
        case .verified, .likelyTrue:  return Color(red: 0.18, green: 0.72, blue: 0.45)
        case .misleading:             return Color(red: 0.96, green: 0.58, blue: 0.18)
        case .likelyFalse, .falseClaim: return Color(red: 0.88, green: 0.28, blue: 0.25)
        case .unverifiable:           return Color(white: 0.55)
        }
    }

    var icon: String {
        switch self {
        case .verified, .likelyTrue:  return "checkmark.shield.fill"
        case .misleading:             return "exclamationmark.shield.fill"
        case .likelyFalse, .falseClaim: return "xmark.shield.fill"
        case .unverifiable:           return "questionmark.circle.fill"
        }
    }
}

// MARK: - ShieldDimension

struct ShieldDimension: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let icon: String

    static let sourcing   = ShieldDimension(title: "Sourcing",   content: "", icon: "doc.text.magnifyingglass")
    static let consensus  = ShieldDimension(title: "Consensus",  content: "", icon: "person.3.fill")
    static let distortion = ShieldDimension(title: "Distortion", content: "", icon: "arrow.triangle.branch")
    static let motive     = ShieldDimension(title: "Motive",     content: "", icon: "questionmark.circle.fill")
}

// MARK: - ShieldAnalysis

struct ShieldAnalysis {
    let claim: String
    let sourcing: ShieldDimension
    let consensus: ShieldDimension
    let distortion: ShieldDimension
    let motive: ShieldDimension
    let verdict: ShieldVerdict
    let verdictExplanation: String
    let confidence: Double      // 0.0 – 1.0
    let analyzedAt: Date

    var dimensions: [ShieldDimension] {
        [sourcing, consensus, distortion, motive]
    }
}

// MARK: - ShieldAnalysisError

enum ShieldAnalysisError: LocalizedError {
    case emptyInput
    case networkUnavailable
    case functionError(String)
    case parseError
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .emptyInput:             return "Please enter a claim to analyze."
        case .networkUnavailable:     return "No network connection. Please try again."
        case .functionError(let msg): return msg
        case .parseError:             return "Couldn't interpret the analysis result."
        case .unauthorized:           return "You must be signed in to use Berean Shield."
        }
    }
}

// MARK: - BereanShieldService

@MainActor
final class BereanShieldService: ObservableObject {

    static let shared = BereanShieldService()

    @Published var isAnalyzing: Bool = false
    @Published var lastAnalysis: ShieldAnalysis? = nil
    @Published var lastError: ShieldAnalysisError? = nil

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Public API

    /// Analyzes a claim across 5 dimensions and returns a ShieldAnalysis.
    /// Throws ShieldAnalysisError on failure.
    func analyze(claim: String) async throws -> ShieldAnalysis {
        let trimmed = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShieldAnalysisError.emptyInput
        }

        isAnalyzing = true
        lastError = nil
        defer { isAnalyzing = false }

        let payload: [String: Any] = ["claim": trimmed]

        do {
            let result = try await functions
                .httpsCallable("bereanShieldAnalyze")
                .safeCall(payload)

            guard let data = result.data as? [String: Any] else {
                throw ShieldAnalysisError.parseError
            }

            let analysis = try parseAnalysis(from: data, claim: trimmed)
            lastAnalysis = analysis
            return analysis

        } catch let error as ShieldAnalysisError {
            lastError = error
            throw error
        } catch {
            let wrapped = ShieldAnalysisError.functionError(error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }

    // MARK: - Private Parsing

    private func parseAnalysis(from data: [String: Any], claim: String) throws -> ShieldAnalysis {
        guard
            let sourcingText   = data["sourcing"]    as? String,
            let consensusText  = data["consensus"]   as? String,
            let distortionText = data["distortion"]  as? String,
            let motiveText     = data["motive"]      as? String,
            let verdictRaw     = data["verdict"]     as? String,
            let verdictExp     = data["verdictExplanation"] as? String
        else {
            throw ShieldAnalysisError.parseError
        }

        let verdict = ShieldVerdict(rawValue: verdictRaw) ?? .unverifiable
        let confidence = (data["confidence"] as? Double) ?? 0.5

        return ShieldAnalysis(
            claim: claim,
            sourcing: ShieldDimension(
                title: "Sourcing",
                content: sourcingText,
                icon: "doc.text.magnifyingglass"
            ),
            consensus: ShieldDimension(
                title: "Consensus",
                content: consensusText,
                icon: "person.3.fill"
            ),
            distortion: ShieldDimension(
                title: "Distortion",
                content: distortionText,
                icon: "arrow.triangle.branch"
            ),
            motive: ShieldDimension(
                title: "Motive",
                content: motiveText,
                icon: "questionmark.circle.fill"
            ),
            verdict: verdict,
            verdictExplanation: verdictExp,
            confidence: max(0, min(1, confidence)),
            analyzedAt: Date()
        )
    }
}
