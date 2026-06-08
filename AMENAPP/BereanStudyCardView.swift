//
//  BereanStudyCardView.swift
//  AMENAPP
//
//  Renders a single StudyCard from a BereanStructuredResponse.
//  Each card type has a distinct visual treatment; all follow the
//  same compact card shell from the design system.
//

import SwiftUI

struct BereanStudyCardView: View {
    let card: StudyCard
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: card.type.icon)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(card.type.tintColor)
                    .frame(width: 24, height: 24)
                    .background(card.type.tintColor.opacity(0.12), in: Circle())

                Text(card.title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if card.type.isExpandable {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Scripture ref label (e.g. "John 3:16 (ESV)")
            if let ref = card.scriptureRef {
                Text(ref)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }

            // Content
            if !card.type.isExpandable || isExpanded {
                Text(card.content)
                    .font(card.type == .scripture ? AMENFont.regular(15).italic() : AMENFont.regular(14))
                    .foregroundStyle(card.type == .scripture ? Color.primary : Color.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // External resource link
            if let urlString = card.resourceURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Learn more", systemImage: "arrow.up.right")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(card.type.tintColor.opacity(0.18), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if card.type.isExpandable {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
    }
}

// MARK: - StudyCard.StudyCardType extensions for display

extension StudyCard.StudyCardType {
    var icon: String {
        switch self {
        case .scripture:        return "book.fill"
        case .wordStudy:        return "textformat.abc"
        case .historicalContext: return "clock.fill"
        case .commentary:       return "text.bubble.fill"
        case .application:      return "arrow.right.circle.fill"
        case .reflection:       return "heart.fill"
        case .crossReference:   return "arrow.left.arrow.right"
        case .christConnection: return "cross.fill"
        case .leaderReferral:   return "person.fill.questionmark"
        case .crisisResource:   return "exclamationmark.shield.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .scripture:        return Color(red: 0.18, green: 0.44, blue: 0.80)  // Deep blue
        case .wordStudy:        return Color(red: 0.52, green: 0.26, blue: 0.73)  // Purple
        case .historicalContext: return Color(red: 0.70, green: 0.45, blue: 0.20) // Warm brown
        case .commentary:       return Color(red: 0.18, green: 0.58, blue: 0.46)  // Teal
        case .application:      return Color(red: 0.22, green: 0.62, blue: 0.28)  // Green
        case .reflection:       return Color(red: 0.85, green: 0.30, blue: 0.35)  // Rose
        case .crossReference:   return Color(red: 0.18, green: 0.44, blue: 0.80)  // Blue
        case .christConnection: return Color(red: 0.85, green: 0.60, blue: 0.15)  // Gold
        case .leaderReferral:   return Color(red: 0.40, green: 0.60, blue: 0.80)  // Steel blue
        case .crisisResource:   return Color.orange
        }
    }

    var isExpandable: Bool {
        switch self {
        case .wordStudy, .historicalContext, .commentary: return true
        default: return false
        }
    }
}

// MARK: - Crisis Resource Card

/// Specialized urgent card shown when crisis signals are detected.
/// Always renders expanded; never collapsible.
struct BereanCrisisResourceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.systemScaled(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.orange, in: Circle())

                Text("You Are Not Alone")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
            }

            Text("If you're in crisis, please reach out to someone who can help:")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                crisisRow(label: "988 Suicide & Crisis Lifeline", detail: "Call or text 988 (US)")
                crisisRow(label: "Crisis Text Line", detail: "Text HOME to 741741")
                crisisRow(label: "Talk to your pastor", detail: "They want to hear from you")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func crisisRow(label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Leadership Prompt Banner

/// A soft banner inviting the user to connect with their pastor.
/// Never shown automatically on-screen; only shown when `leadershipPromptShown == true`.
struct BereanLeadershipPromptBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.fill.questionmark")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(Color(red: 0.40, green: 0.60, blue: 0.80))
                .frame(width: 36, height: 36)
                .background(Color(red: 0.40, green: 0.60, blue: 0.80).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("A Word from Berean")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(red: 0.40, green: 0.60, blue: 0.80).opacity(0.20), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}
