import SwiftUI

// MARK: - Session Shaping Card
// A dismissible card injected into the Selah media feed at natural stopping points.
// Also includes the FeedHealthOverlay banner (primitive 26) as a companion view.
// Purely additive — no structural changes to any existing view.

struct SelahSessionShapingCard: View {
    let reason: SessionShapingReason
    let onContinue: () -> Void
    let onStop: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dismissed = false

    enum SessionShapingReason {
        case goodStoppingPoint(postsViewed: Int)
        case attentionBudgetReached(minutes: Int)
        case suggestLighterFeed
        case suggestDeepMode
        case highLoadContent
        case longSession(minutes: Int)

        var headline: String {
            switch self {
            case .goodStoppingPoint(let n):  return "You've seen \(n) meaningful moments."
            case .attentionBudgetReached(let m): return "You've been here for \(m) minutes."
            case .suggestLighterFeed:        return "Most of this is pretty heavy."
            case .suggestDeepMode:           return "You've been lingering on a few things."
            case .highLoadContent:           return "High-intensity content ahead."
            case .longSession(let m):        return "\(m) minutes in — you're in deep."
            }
        }

        var subtitle: String {
            switch self {
            case .goodStoppingPoint:     return "This could be a good place to pause."
            case .attentionBudgetReached: return "Want to continue or take a break?"
            case .suggestLighterFeed:    return "Switch to a lighter mix?"
            case .suggestDeepMode:       return "Want to go deeper on one of those?"
            case .highLoadContent:       return "Consider switching to quiet mode."
            case .longSession:           return "A pause might serve you better."
            }
        }

        var icon: String {
            switch self {
            case .goodStoppingPoint:      return "checkmark.circle"
            case .attentionBudgetReached: return "timer"
            case .suggestLighterFeed:     return "wind"
            case .suggestDeepMode:        return "magnifyingglass.circle"
            case .highLoadContent:        return "bolt.shield"
            case .longSession:            return "moon.zzz"
            }
        }

        var accentColor: Color {
            switch self {
            case .goodStoppingPoint:      return .green
            case .attentionBudgetReached: return .orange
            case .suggestLighterFeed:     return .blue
            case .suggestDeepMode:        return .purple
            case .highLoadContent:        return .red
            case .longSession:            return .indigo
            }
        }

        var continueLabel: String {
            switch self {
            case .suggestLighterFeed:  return "Switch feed"
            case .suggestDeepMode:     return "Go deeper"
            case .highLoadContent:     return "Quiet mode"
            default:                   return "Keep going"
            }
        }
    }

    var body: some View {
        if dismissed { EmptyView() } else {
            cardContent
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .scale(scale: 0.94).combined(with: .opacity)
                ))
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(reason.accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: reason.icon)
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundStyle(reason.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(reason.headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(reason.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        dismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .accessibilityLabel("Dismiss")
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation { dismissed = true }
                    onStop()
                } label: {
                    Text("Pause here")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(reason.accentColor))
                }
                .accessibilityLabel("Pause session here")

                Button {
                    withAnimation { dismissed = true }
                    onContinue()
                } label: {
                    Text(reason.continueLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(reason.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(reason.accentColor.opacity(0.10)))
                }
                .accessibilityLabel(reason.continueLabel)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark
                      ? AnyShapeStyle(.ultraThinMaterial)
                      : AnyShapeStyle(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(reason.accentColor.opacity(0.14), lineWidth: 0.5)
                )
                .shadow(color: reason.accentColor.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Feed Health Overlay Banner (Primitive 26)
// A small dismissible status strip shown at the top of the Selah feed.

struct SelahFeedHealthBanner: View {
    enum FeedHealthState {
        case lighterFeed, deepModeActive, learningPath, goodStopping, highSignal, mixed

        var label: String {
            switch self {
            case .lighterFeed:    return "Lighter feed active"
            case .deepModeActive: return "Deep mode active"
            case .learningPath:   return "You're in a learning path"
            case .goodStopping:   return "Good stopping point soon"
            case .highSignal:     return "Mostly high-signal posts"
            case .mixed:          return "Mixed session"
            }
        }

        var icon: String {
            switch self {
            case .lighterFeed:    return "wind"
            case .deepModeActive: return "magnifyingglass"
            case .learningPath:   return "book.closed"
            case .goodStopping:   return "checkmark.circle"
            case .highSignal:     return "star.circle"
            case .mixed:          return "square.grid.2x2"
            }
        }

        var color: Color {
            switch self {
            case .lighterFeed:    return .blue
            case .deepModeActive: return .purple
            case .learningPath:   return .teal
            case .goodStopping:   return .green
            case .highSignal:     return .orange
            case .mixed:          return .secondary
            }
        }
    }

    let state: FeedHealthState
    @State private var dismissed = false

    var body: some View {
        if dismissed { EmptyView() } else {
            HStack(spacing: 8) {
                Image(systemName: state.icon)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(state.color)
                Text(state.label)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(state.color.opacity(0.20), lineWidth: 0.5))
            )
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Session Shaping Engine (client-side)

struct SelahSessionShapingEngine {
    static func evaluate(
        postsViewed: Int,
        sessionDurationSeconds: Double,
        attentionBudgetMinutes: Int = 20,
        highLoadFraction: Double = 0.0
    ) -> SelahSessionShapingCard.SessionShapingReason? {
        let minutes = Int(sessionDurationSeconds / 60)

        if postsViewed > 0 && postsViewed % 12 == 0 {
            return .goodStoppingPoint(postsViewed: postsViewed)
        }
        if minutes >= attentionBudgetMinutes {
            return .attentionBudgetReached(minutes: minutes)
        }
        if minutes > 30 {
            return .longSession(minutes: minutes)
        }
        if highLoadFraction > 0.6 {
            return .highLoadContent
        }
        return nil
    }

    static func feedHealthState(
        sessionDurationSeconds: Double,
        postsViewed: Int,
        highSignalFraction: Double
    ) -> SelahFeedHealthBanner.FeedHealthState {
        if highSignalFraction > 0.7 { return .highSignal }
        if sessionDurationSeconds > 1200 { return .deepModeActive }
        if postsViewed < 5 { return .lighterFeed }
        return .mixed
    }
}
