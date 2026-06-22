// ContentSafetyBadge.swift — AMEN App
// Inline badge shown on posts/comments that passed AI safety review

import SwiftUI

// MARK: - ContentSafetyBadge

/// A small inline badge indicating a piece of content's safety review outcome.
/// Use on PostCard, comment rows, etc.
struct ContentSafetyBadge: View {
    let decision: ContentSafetyLog.SafetyDecision
    var compact: Bool = true // true = icon only, false = icon + label

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(compact ? 10 : 11))
            if !compact {
                Text(label)
                    .font(.systemScaled(10, weight: .medium))
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 3 : 4)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
    }

    private var icon: String {
        switch decision {
        case .approved:    return "checkmark.shield.fill"
        case .warned:      return "exclamationmark.triangle.fill"
        case .blocked:     return "xmark.shield.fill"
        case .appealed:    return "arrow.uturn.left.circle.fill"
        case .underReview: return "clock.fill"
        }
    }

    private var label: String {
        switch decision {
        case .approved:    return "Approved"
        case .warned:      return "Warning"
        case .blocked:     return "Blocked"
        case .appealed:    return "Appealed"
        case .underReview: return "Under Review"
        }
    }

    private var color: Color {
        switch decision {
        case .approved:    return Color(hex: "10B981")
        case .warned:      return Color(hex: "F59E0B")
        case .blocked:     return Color(hex: "EF4444")
        case .appealed:    return Color(hex: "6B48FF")
        case .underReview: return Color(hex: "06B6D4")
        }
    }
}

// MARK: - SafetyScorePill

/// A pill showing a numeric safety score (0.0–1.0) with color coding.
struct SafetyScorePill: View {
    let score: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.fill")
                .font(.systemScaled(10))
            Text("\(Int(score * 100))%")
                .font(.systemScaled(10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        if score >= 0.85 { return Color(hex: "10B981") }
        if score >= 0.6  { return Color(hex: "F59E0B") }
        return Color(hex: "EF4444")
    }
}

// MARK: - ManipulationFlagRow

/// Shows a list of detected logical fallacy flags from ReasoningViewModel.
struct ManipulationFlagRow: View {
    let flags: [String]

    var body: some View {
        if !flags.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "F59E0B"))
                Text(flags.map { friendlyName($0) }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(Color(hex: "F59E0B"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "F59E0B").opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func friendlyName(_ raw: String) -> String {
        switch raw {
        case "ad_hominem":       return "Ad Hominem"
        case "strawman":         return "Straw Man"
        case "appeal_to_emotion": return "Appeal to Emotion"
        case "false_dichotomy":  return "False Dichotomy"
        case "slippery_slope":   return "Slippery Slope"
        default:                 return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
