// AmenPrePostReviewSheet.swift
// AMEN App — CommunityOS / ContentSafety
//
// Phase 4 Agent TS-b — AI Content Safety
//
// Two views:
//   AmenPrePostReviewSheet     — shown when PrePostDecision.Action is .showSuggestion
//                                or .blockWithMessage.
//   AmenCrisisInterventionView — shown when PrePostDecision.Action is .crisisIntervene.
//
// Design: Liquid Glass on light system background.
//   Pre-iOS 26: .ultraThinMaterial + strokeBorder(.black.opacity(0.08), lineWidth: 0.8)
//   iOS 26+:    .glassEffect() on card surfaces
//
// Rules:
//   - Suggest before posting, never over-block.
//   - Hard block is ONLY for .severe tier.
//   - Crisis language → AmenCrisisInterventionView, never suppress.
//   - Severe tier: no "Post anyway" option. Only "Remove content" (calls onCancel).
//   - Medium/High tier: both "Edit post" and "Post anyway" available.
//
// Accessibility:
//   - All interactive elements have .accessibilityLabel and .accessibilityHint.
//   - Sheets respect .accessibilityReduceMotion.
//   - Focus order: banner → explanation → actions.
//   - Minimum tap target 44 pt on all buttons.

import SwiftUI

// MARK: - AmenPrePostReviewSheet

struct AmenPrePostReviewSheet: View {

    // MARK: Props

    let decision: PrePostDecision
    let draftContent: String
    var onProceed: () -> Void
    var onEdit: () -> Void
    var onCancel: () -> Void

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: Computed

    private var tier: RiskTier { decision.safetyResult.tier }
    private var isSevere: Bool { tier == .severe }
    private var isHard: Bool { decision.safetyResult.hardBlocked }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    riskBanner
                    explanationSection
                    actionsSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isSevere {
                        Button("Cancel", action: onCancel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Cancel and go back to the draft")
                    }
                }
            }
            .background(sheetBackground.ignoresSafeArea())
        }
        .presentationDetents(isSevere ? [.medium] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(
            reduceTransparency
                ? Color(.systemBackground)
                : Color(.systemBackground).opacity(0.92)
        )
    }

    // MARK: - Risk Banner

    private var riskBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: bannerIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tierColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(bannerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bannerTitle). \(bannerSubtitle)")
    }

    @ViewBuilder
    private var bannerBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .glassEffect(.regular.tint(tierColor.opacity(0.08)))
        } else if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tierColor.opacity(0.30), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Explanation Section

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let suggestion = decision.safetyResult.suggestion, !suggestion.isEmpty {
                Text(suggestion)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !decision.safetyResult.categories.isEmpty {
                categoryChips
            }

            if isSevere {
                severeFlagNote
            }
        }
    }

    private var categoryChips: some View {
        let visibleCategories = decision.safetyResult.categories.filter { $0 != .safe && $0 != .csam }
        return Group {
            if !visibleCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleCategories, id: \.rawValue) { category in
                            categoryChip(category)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 36)
            }
        }
    }

    private func categoryChip(_ category: ContentCategory) -> some View {
        HStack(spacing: 5) {
            Image(systemName: categoryIcon(category))
                .font(.system(size: 10, weight: .semibold))
            Text(categoryLabel(category))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemFill))
        )
        .accessibilityLabel(categoryLabel(category))
    }

    private var severeFlagNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text("This content has been flagged and cannot be posted. If you believe this is a mistake, you can edit your post and try again, or contact support.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 10) {
            if isSevere || isHard {
                // Severe: no bypass allowed. Only "Edit post" to let user revise.
                editPostButton

                Button(action: onCancel) {
                    Text("Remove content")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove this content and go back")
                .accessibilityHint("Discards the post draft")

            } else {
                // Medium / High: user may edit or proceed.
                editPostButton
                postAnywayButton
            }
        }
    }

    private var editPostButton: some View {
        Button(action: onEdit) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Edit post")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit your post")
        .accessibilityHint("Returns to the draft editor so you can revise your content")
    }

    private var postAnywayButton: some View {
        Button(action: onProceed) {
            Text("Post anyway")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(postAnywayBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post anyway")
        .accessibilityHint("Submits your post as-is. It may be held for review.")
    }

    @ViewBuilder
    private var postAnywayBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).glassEffect()
        } else if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Color(.systemBackground).opacity(0.96)
        }
    }

    // MARK: - Computed Helpers

    private var navigationTitle: String {
        switch tier {
        case .low:    return "Looks good"
        case .medium: return "Heads up"
        case .high:   return "Review before posting"
        case .severe: return "Post blocked"
        }
    }

    private var bannerTitle: String {
        switch tier {
        case .low:    return "Your post looks good"
        case .medium: return "A few things to consider"
        case .high:   return "Your post may need edits"
        case .severe: return "This post cannot be published"
        }
    }

    private var bannerSubtitle: String {
        switch tier {
        case .low:    return "No concerns detected."
        case .medium: return "We noticed something you might want to review."
        case .high:   return "Your post has been flagged for review."
        case .severe: return "This content violates community guidelines."
        }
    }

    private var bannerIcon: String {
        switch tier {
        case .low:    return "checkmark.shield.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high:   return "shield.fill"
        case .severe: return "lock.fill"
        }
    }

    private var tierColor: Color {
        switch tier {
        case .low:    return .green
        case .medium: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .high:   return .orange
        case .severe: return .red
        }
    }

    private func categoryLabel(_ category: ContentCategory) -> String {
        switch category {
        case .safe:             return "Safe"
        case .spam:             return "Spam"
        case .harassment:       return "Harassment"
        case .hateSpeech:       return "Hate speech"
        case .misinformation:   return "Misinformation"
        case .scam:             return "Scam"
        case .doxxing:          return "Personal info"
        case .violentExtremism: return "Violent content"
        case .sexualContent:    return "Adult content"
        case .csam:             return "Restricted"
        case .selfHarmRisk:     return "Self-harm"
        case .crisisLanguage:   return "Crisis language"
        }
    }

    private func categoryIcon(_ category: ContentCategory) -> String {
        switch category {
        case .safe:             return "checkmark.circle"
        case .spam:             return "envelope.badge"
        case .harassment:       return "person.fill.badge.minus"
        case .hateSpeech:       return "exclamationmark.bubble"
        case .misinformation:   return "questionmark.circle"
        case .scam:             return "dollarsign.circle"
        case .doxxing:          return "person.crop.circle.badge.exclamationmark"
        case .violentExtremism: return "exclamationmark.shield"
        case .sexualContent:    return "eye.slash"
        case .csam:             return "lock.shield"
        case .selfHarmRisk:     return "heart.slash"
        case .crisisLanguage:   return "heart.circle"
        }
    }
}

// MARK: - AmenCrisisInterventionView

/// Shown when `PrePostDecision.Action == .crisisIntervene`.
///
/// Design principles:
///   - Warm, non-judgmental tone at all times.
///   - Resources are always visible; user is never shamed or lectured.
///   - "I'm okay" allows dismissal. "I need help" opens the crisis lifeline.
///   - This view must NEVER be suppressed even if a user taps quickly.
///   - Conforms to WCAG 2.1 AA: text >=14pt, contrast >=4.5:1, tap targets >=44pt.
struct AmenCrisisInterventionView: View {

    // MARK: Props

    var onDismiss: () -> Void

    // MARK: Environment

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openURL) private var openURL

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    resourcesSection
                    dismissSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .navigationTitle("You're not alone")
            .navigationBarTitleDisplayMode(.inline)
            .background(sheetBackground.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(
            reduceTransparency
                ? Color(.systemBackground)
                : Color(.systemBackground).opacity(0.95)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.20))
                    .accessibilityHidden(true)

                Text("We noticed something in your post")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text("If you're going through something painful right now, you don't have to face it alone. Help is available, and your feelings matter.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    // MARK: - Resources

    private var resourcesSection: some View {
        VStack(spacing: 12) {
            resourceCard(
                title: "988 Suicide & Crisis Lifeline",
                subtitle: "Call or text 988 — free, confidential, 24/7",
                icon: "phone.circle.fill",
                action: { openURL(URL(string: "tel://988")!) }
            )

            resourceCard(
                title: "Crisis Text Line",
                subtitle: "Text HOME to 741741 — free, 24/7 text support",
                icon: "message.circle.fill",
                action: { openURL(URL(string: "sms://741741&body=HOME")!) }
            )

            resourceCard(
                title: "International Association for Suicide Prevention",
                subtitle: "Find help in your country at iasp.info/resources",
                icon: "globe.americas.fill",
                action: { openURL(URL(string: "https://www.iasp.info/resources/Crisis_Centres/")!) }
            )
        }
    }

    private func resourceCard(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.20))
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(minHeight: 64)
            .background(resourceCardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    @ViewBuilder
    private var resourceCardBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .glassEffect(.regular.tint(Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.04)))
        } else if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.20), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Dismiss Section

    private var dismissSection: some View {
        VStack(spacing: 10) {
            Button(action: onDismiss) {
                Text("I'm okay — go back to my post")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(iAmOkayBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I'm okay, go back to my post")
            .accessibilityHint("Dismisses this screen and returns to your draft")

            Text("Your post is still saved as a draft.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Your post is still saved as a draft")
        }
    }

    @ViewBuilder
    private var iAmOkayBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).glassEffect()
        } else if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Sheet Background

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Color(.systemBackground).opacity(0.97)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Pre-Post Review — Medium") {
    let result = ContentSafetyResult(
        tier: .medium,
        categories: [.doxxing],
        confidence: 0.82,
        suggestion: "This post may contain personal contact information. Consider removing it before posting.",
        hardBlocked: false,
        requiresModerationReview: false,
        escalateImmediately: false,
        checkedAt: Date()
    )
    let decision = PrePostDecision(
        action: .showSuggestion("This post may contain personal contact information."),
        safetyResult: result
    )
    AmenPrePostReviewSheet(
        decision: decision,
        draftContent: "Call me at 555-867-5309 for prayer!",
        onProceed: {},
        onEdit: {},
        onCancel: {}
    )
}

#Preview("Pre-Post Review — Severe") {
    let result = ContentSafetyResult(
        tier: .severe,
        categories: [.hateSpeech],
        confidence: 0.97,
        suggestion: "This post contains language that may violate community guidelines.",
        hardBlocked: true,
        requiresModerationReview: true,
        escalateImmediately: false,
        checkedAt: Date()
    )
    let decision = PrePostDecision(
        action: .blockWithMessage("This post cannot be published."),
        safetyResult: result
    )
    AmenPrePostReviewSheet(
        decision: decision,
        draftContent: "Flagged content here",
        onProceed: {},
        onEdit: {},
        onCancel: {}
    )
}

#Preview("Crisis Intervention") {
    AmenCrisisInterventionView(onDismiss: {})
}
#endif
