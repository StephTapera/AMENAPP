// AmenSocialSafetyUI.swift
// AMENAPP — reusable Social Safety OS controls.

import SwiftUI

enum AmenSafetyPillState: String, CaseIterable {
    case safe
    case contextAvailable
    case sourceNeeded
    case rewriteSuggested
    case limitedReach
    case heldForReview
    case aiContent
    case unverifiedClaim
    case quietMode
    case minorProtected

    var title: String {
        switch self {
        case .safe: return "Safe"
        case .contextAvailable: return "Context"
        case .sourceNeeded: return "Source needed"
        case .rewriteSuggested: return "Rewrite"
        case .limitedReach: return "Limited"
        case .heldForReview: return "Review"
        case .aiContent: return "AI"
        case .unverifiedClaim: return "Unverified"
        case .quietMode: return "Quiet"
        case .minorProtected: return "Minor protected"
        }
    }

    var iconName: String {
        switch self {
        case .safe: return "checkmark.shield"
        case .contextAvailable: return "info.circle"
        case .sourceNeeded: return "link.badge.plus"
        case .rewriteSuggested: return "pencil.and.scribble"
        case .limitedReach: return "speedometer"
        case .heldForReview: return "hourglass"
        case .aiContent: return "sparkles"
        case .unverifiedClaim: return "exclamationmark.bubble"
        case .quietMode: return "moon"
        case .minorProtected: return "figure.child"
        }
    }

    var tint: Color {
        switch self {
        case .safe, .contextAvailable, .quietMode, .minorProtected:
            return .green
        case .sourceNeeded, .rewriteSuggested, .limitedReach, .aiContent, .unverifiedClaim:
            return .orange
        case .heldForReview:
            return .red
        }
    }
}

struct AmenSafetyPill: View {
    let state: AmenSafetyPillState

    var body: some View {
        Label(state.title, systemImage: state.iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .amenAdaptiveLiquidGlass(
                AmenAdaptiveGlassContext(
                    role: .floatingControl,
                    isSelected: state != .safe,
                    ambientTint: state.tint
                )
            )
            .accessibilityLabel(Text("Safety status: \(state.title)"))
    }
}
