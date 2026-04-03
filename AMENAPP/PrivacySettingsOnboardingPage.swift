//
//  PrivacySettingsOnboardingPage.swift
//  AMENAPP
//
//  Privacy configuration during onboarding
//

import SwiftUI

struct PrivacySettingsOnboardingPage: View {
    @Binding var isAccountPrivate: Bool
    @Binding var whoCanMessage: MessagingPrivacy
    @Binding var commentModeration: CommentModerationLevel
    let currentPage: Int
    let totalPages: Int
    let canContinue: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onNext: () -> Void

    enum CommentModerationLevel: String, CaseIterable {
        case standard = "Standard"
        case strict   = "Strict"

        var icon: String {
            switch self {
            case .standard: return "text.bubble"
            case .strict:   return "shield.fill"
            }
        }

        var description: String {
            switch self {
            case .standard: return "Filters spam and obvious hate speech"
            case .strict:   return "Hides all comments until you approve them"
            }
        }
    }

    enum MessagingPrivacy: String, CaseIterable {
        case everyone = "Everyone"
        case followersOnly = "People I Follow"
        case nobody = "Nobody"

        var icon: String {
            switch self {
            case .everyone: return "person.3.fill"
            case .followersOnly: return "person.2.fill"
            case .nobody: return "hand.raised.fill"
            }
        }

        var description: String {
            switch self {
            case .everyone: return "Anyone can send you direct messages"
            case .followersOnly: return "Only people you follow can message you"
            case .nobody: return "Block all direct messages"
            }
        }
    }

    var body: some View {
        ZStack {
            ONB.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        AmenOnboardingHeroIcon(
                            systemName: "lock.shield.fill",
                            size: 88,
                            accent: ONB.accent
                        )

                        VStack(spacing: 8) {
                            Text("Your Privacy Matters")
                                .font(AMENFont.bold(28))
                                .foregroundStyle(ONB.inkPrimary)

                            Text("Control who can see your content and contact you")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(ONB.inkSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.top, 60)

                    VStack(spacing: 24) {
                        // Private Account Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: isAccountPrivate ? "lock.fill" : "lock.open.fill")
                                    .foregroundStyle(isAccountPrivate ? ONB.accent : ONB.inkTertiary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Private Account")
                                        .font(AMENFont.semiBold(17))
                                        .foregroundStyle(ONB.inkPrimary)

                                    Text(isAccountPrivate ? "Only approved followers see your posts" : "Anyone can see your public posts")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(ONB.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                Toggle("", isOn: $isAccountPrivate)
                                    .labelsHidden()
                                    .tint(ONB.accent)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.thinMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.72)))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ONB.glassBorder, lineWidth: 1))
                            )
                            .shadow(color: ONB.glassShadow, radius: 8, y: 2)

                            // Private account explainer
                            if isAccountPrivate {
                                ONBGlassCard(
                                    padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16),
                                    cornerRadius: 14
                                ) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundStyle(ONB.accent)
                                            .font(.systemScaled(16))

                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("With a private account:")
                                                .font(AMENFont.semiBold(13))
                                                .foregroundStyle(ONB.inkPrimary)

                                            BulletPoint(text: "New followers must request to follow you")
                                            BulletPoint(text: "Only approved followers see your posts")
                                            BulletPoint(text: "Your posts won't appear in search results")
                                            BulletPoint(text: "You can still follow and interact with public accounts")
                                        }
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)))
                            }
                        }

                        // Messaging Privacy Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Who Can Message You")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(ONB.inkSecondary)

                            VStack(spacing: 10) {
                                ForEach(MessagingPrivacy.allCases, id: \.self) { option in
                                    MessagingPrivacyOption(
                                        option: option,
                                        isSelected: whoCanMessage == option,
                                        action: {
                                            let haptic = UIImpactFeedbackGenerator(style: .light)
                                            haptic.impactOccurred()
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                whoCanMessage = option
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        // Comment Moderation Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Comment Moderation")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(ONB.inkSecondary)

                            VStack(spacing: 10) {
                                ForEach(CommentModerationLevel.allCases, id: \.self) { level in
                                    Button(action: {
                                        let haptic = UIImpactFeedbackGenerator(style: .light)
                                        haptic.impactOccurred()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            commentModeration = level
                                        }
                                    }) {
                                        let selected = commentModeration == level
                                        HStack(spacing: 16) {
                                            ZStack {
                                                Circle()
                                                    .stroke(selected ? ONB.accent : ONB.inkTertiary.opacity(0.4), lineWidth: 2)
                                                    .frame(width: 24, height: 24)
                                                if selected {
                                                    Circle()
                                                        .fill(ONB.accent)
                                                        .frame(width: 12, height: 12)
                                                }
                                            }

                                            Image(systemName: level.icon)
                                                .foregroundStyle(selected ? ONB.accent : ONB.inkTertiary)
                                                .frame(width: 24)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(level.rawValue)
                                                    .font(AMENFont.semiBold(15))
                                                    .foregroundStyle(ONB.inkPrimary)
                                                Text(level.description)
                                                    .font(AMENFont.regular(12))
                                                    .foregroundStyle(ONB.inkSecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }

                                            Spacer()
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(.thinMaterial)
                                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.72)))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .strokeBorder(
                                                            selected ? ONB.accent.opacity(0.50) : ONB.glassBorder,
                                                            lineWidth: selected ? 1.5 : 1
                                                        )
                                                )
                                        )
                                        .shadow(color: ONB.glassShadow, radius: selected ? 8 : 4, y: selected ? 3 : 1)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        // AI Moderation Disclosure
                        ONBGlassCard(
                            padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16),
                            cornerRadius: 14
                        ) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "cpu.fill")
                                    .foregroundStyle(ONB.accent)
                                    .font(.systemScaled(16))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AI-Assisted Safety")
                                        .font(AMENFont.semiBold(14))
                                        .foregroundStyle(ONB.inkPrimary)

                                    Text("Messages are reviewed by AI to detect harmful content and protect our community. No human reads your messages except in confirmed safety escalations.")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(ONB.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        // You're Always in Control
                        ONBGlassCard(
                            padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16),
                            cornerRadius: 14
                        ) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundStyle(ONB.accentGold)
                                    .font(.systemScaled(16))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("You're Always in Control")
                                        .font(AMENFont.semiBold(14))
                                        .foregroundStyle(ONB.inkPrimary)

                                    Text("Change these settings anytime in your account settings")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(ONB.inkSecondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Navigation Buttons
                    OnboardingNavigationButtons(
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: onBack,
                        onSkip: onSkip,
                        onNext: onNext
                    )
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
        }
        .onChange(of: isAccountPrivate) { _, _ in
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
    }
}

// MARK: - Messaging Privacy Option

struct MessagingPrivacyOption: View {
    let option: PrivacySettingsOnboardingPage.MessagingPrivacy
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? ONB.accent : ONB.inkTertiary.opacity(0.4), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(ONB.accent)
                            .frame(width: 12, height: 12)
                    }
                }

                Image(systemName: option.icon)
                    .foregroundStyle(isSelected ? ONB.accent : ONB.inkTertiary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.rawValue)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(ONB.inkPrimary)

                    Text(option.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(ONB.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.72)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? ONB.accent.opacity(0.50) : ONB.glassBorder,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .shadow(color: ONB.glassShadow, radius: isSelected ? 8 : 4, y: isSelected ? 3 : 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Onboarding Navigation Buttons (local copy)

private struct OnboardingNavigationButtons: View {
    let currentPage: Int
    let totalPages: Int
    let canContinue: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if currentPage > 0 {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(13, weight: .semibold))
                        Text("Back")
                            .font(.systemScaled(15, weight: .medium))
                    }
                    .foregroundStyle(ONB.inkSecondary)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: onSkip) {
                Text("Skip")
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
            }
            .buttonStyle(.plain)

            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text(currentPage == totalPages - 1 ? "Finish" : "Next")
                        .font(.systemScaled(15, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(height: 52)
                .padding(.horizontal, 20)
                .background(
                    Capsule().fill(canContinue ? ONB.inkPrimary : ONB.inkTertiary.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
        }
    }
}

// MARK: - Bullet Point

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(AMENFont.regular(13))
                .foregroundStyle(ONB.inkTertiary)

            Text(text)
                .font(AMENFont.regular(13))
                .foregroundStyle(ONB.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PrivacySettingsOnboardingPage(
        isAccountPrivate: .constant(false),
        whoCanMessage: .constant(.everyone),
        commentModeration: .constant(.standard),
        currentPage: 8,
        totalPages: 13,
        canContinue: true,
        onBack: {},
        onSkip: {},
        onNext: {}
    )
}
