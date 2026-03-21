//
//  BereanStructuredCardView.swift
//  AMENAPP
//
//  A styled card bubble for structured Berean AI outputs:
//  prayers, decision summaries, meal plans, debate responses, fact-checks, etc.
//  Distinct from regular chat bubbles — uses a glass aesthetic with a
//  colored top accent stripe per card type.
//

import SwiftUI

// MARK: - BereanCardType

enum BereanCardType: String, CaseIterable {
    case prayer     = "prayer"
    case decision   = "decision"
    case meal       = "meal"
    case debate     = "debate"
    case factCheck  = "factCheck"
    case crisis     = "crisis"
    case generic    = "generic"

    var accentColor: Color {
        switch self {
        case .prayer:    return Color(red: 0.48, green: 0.36, blue: 0.75)  // soft purple
        case .decision:  return Color(red: 0.22, green: 0.65, blue: 0.87)  // sky blue
        case .meal:      return Color(red: 0.30, green: 0.72, blue: 0.45)  // fresh green
        case .debate:    return Color(red: 0.92, green: 0.53, blue: 0.23)  // amber
        case .factCheck: return Color(red: 0.85, green: 0.30, blue: 0.25)  // berean coral
        case .crisis:    return Color(red: 0.55, green: 0.20, blue: 0.20)  // deep red
        case .generic:   return Color(red: 0.45, green: 0.45, blue: 0.52)  // neutral slate
        }
    }

    var icon: String {
        switch self {
        case .prayer:    return "hands.sparkles"
        case .decision:  return "scale.3d"
        case .meal:      return "fork.knife"
        case .debate:    return "bubble.left.and.bubble.right"
        case .factCheck: return "checkmark.shield"
        case .crisis:    return "heart.circle"
        case .generic:   return "sparkles"
        }
    }

    var defaultTitle: String {
        switch self {
        case .prayer:    return "Prayer"
        case .decision:  return "Decision Summary"
        case .meal:      return "Meal & Fasting Plan"
        case .debate:    return "Perspective"
        case .factCheck: return "Fact Check"
        case .crisis:    return "You Matter"
        case .generic:   return "Berean Response"
        }
    }
}

// MARK: - BereanStructuredCard

struct BereanStructuredCard: View {

    let title: String
    let content: String
    let cardType: BereanCardType
    var onSave: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isSaved = false
    @State private var isPressed = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Colored accent stripe + header
            accentHeader

            // Content body
            contentBody

            // Action footer (Save / Share)
            if onSave != nil || onShare != nil {
                Divider()
                    .overlay(Color.black.opacity(0.06))
                actionFooter
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(cardType.accentColor.opacity(0.18), lineWidth: 1.0)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.07),
                radius: 12, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
    }

    // MARK: - Sub-views

    private var accentHeader: some View {
        HStack(spacing: 10) {
            // Accent-colored icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(cardType.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: cardType.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(cardType.accentColor)
            }

            Text(title.isEmpty ? cardType.defaultTitle : title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(cardType.accentColor)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            // Top accent stripe
            LinearGradient(
                colors: [
                    cardType.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.08),
                    cardType.accentColor.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var contentBody: some View {
        Text(content)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color(.label).opacity(0.88))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, content.isEmpty ? 0 : 4)
    }

    private var actionFooter: some View {
        HStack(spacing: 0) {
            // Save button
            if let saveTap = onSave {
                Button {
                    saveTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSaved = true
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 13, weight: .medium))
                        Text(isSaved ? "Saved" : "Save")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(isSaved ? cardType.accentColor : Color(.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }

            // Share button
            if let shareTap = onShare {
                if onSave != nil {
                    Divider()
                        .frame(height: 24)
                }
                Button {
                    shareTap()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                        Text("Share")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardBackground: some View {
        Group {
            if colorScheme == .dark {
                Color(white: 0.13)
            } else {
                Color(.systemBackground)
            }
        }
    }
}

// MARK: - Crisis Card Convenience

extension BereanStructuredCard {
    /// Returns a pre-configured crisis support card using the .crisis type.
    static func crisisCard(onShare: (() -> Void)? = nil) -> BereanStructuredCard {
        BereanStructuredCard(
            title: "You Matter",
            content: """
            I hear you. What you're feeling is real, and you don't have to face it alone.

            Please reach out to someone who can help right now:

            📞 988 Suicide & Crisis Lifeline — Call or text 988 (US)
            💬 Crisis Text Line — Text HOME to 741741
            🌐 988lifeline.org

            "The Lord is close to the brokenhearted and saves those who are crushed in spirit." — Psalm 34:18

            You are seen, you are loved, and help is available right now.
            """,
            cardType: .crisis,
            onSave: nil,
            onShare: onShare
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Structured Cards") {
    ScrollView {
        VStack(spacing: 16) {
            BereanStructuredCard(
                title: "Morning Prayer",
                content: "Heavenly Father, as I begin this day, fill me with Your wisdom and guide my steps. Let my words and actions reflect Your love. In Jesus' name, Amen.",
                cardType: .prayer,
                onSave: {},
                onShare: {}
            )
            BereanStructuredCard(
                title: "Career Decision",
                content: "Based on the principles of Proverbs 16:3 and Jeremiah 29:11, here are three perspectives to weigh before making your decision...",
                cardType: .decision,
                onSave: {},
                onShare: {}
            )
            BereanStructuredCard(
                title: "Sermon Fact-Check",
                content: "The claim that 'the Bible says God helps those who help themselves' does not appear in Scripture. This phrase is often attributed to Benjamin Franklin.",
                cardType: .factCheck,
                onSave: {},
                onShare: {}
            )
            BereanStructuredCard.crisisCard(onShare: {})
        }
        .padding()
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
#endif
