import SwiftUI

struct LiquidGlassAlignmentBanner: View {
    let result: BiblicalAlignmentCheckResult
    var onViewContext: (() -> Void)? = nil
    var onCorrectAI: (() -> Void)? = nil
    var onRewrite: (() -> Void)? = nil
    var onContinue: (() -> Void)? = nil
    var onHold: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(result.userVisibleSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(.black.opacity(0.68))
                }
                Spacer()
                Button(expanded ? "Hide" : "View") {
                    withOptionalAnimation {
                        expanded.toggle()
                    }
                }
                .font(.system(size: 12, weight: .semibold))
            }

            if expanded {
                if !result.scriptureSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(result.scriptureSuggestions) { suggestion in
                                Text(suggestion.reference)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    if let onViewContext {
                        bannerAction("View Context", action: onViewContext)
                    }
                    if let onCorrectAI {
                        bannerAction("Correct AI", action: onCorrectAI)
                    }
                    if let onRewrite {
                        bannerAction("Rewrite", action: onRewrite)
                    }
                    if let onContinue {
                        bannerAction("Continue", action: onContinue, filled: true)
                    }
                    if let onHold {
                        bannerAction("Hold", action: onHold)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(result.userVisibleSummary)")
    }

    private var iconName: String {
        switch result.status {
        case .aligned: return "checkmark.shield"
        case .contextNeeded: return "book"
        case .needsDiscernment: return "exclamationmark.bubble"
        case .blocked: return "hand.raised"
        case .humanReview: return "clock.badge.exclamationmark"
        }
    }

    private var title: String {
        switch result.status {
        case .aligned: return "Aligned"
        case .contextNeeded: return "Context Needed"
        case .needsDiscernment: return "Needs Discernment"
        case .blocked: return "Blocked"
        case .humanReview: return "Held for Review"
        }
    }

    @ViewBuilder
    private func bannerAction(_ title: String, action: @escaping () -> Void, filled: Bool = false) -> some View {
        Button(title, action: action)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(filled ? Color.black : Color.black.opacity(0.05), in: Capsule())
            .foregroundStyle(filled ? .white : .black)
    }

    private func withOptionalAnimation(_ updates: @escaping () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82), updates)
        }
    }
}
