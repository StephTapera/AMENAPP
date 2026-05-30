// WizardConfirmStep.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// Step 4: Confirm — hero-profile-style review before creation.
//
// Hero header: user avatar (SpaceAvatarView) + title + type badge + access badge.
// Scaffold preview: description, passage refs + cadence (Study), discussion prompts.
// Pricing summary row.
// [Create Space] — amenGold, full width.
//   Creating: progress indicator, button disabled.
//   Error: inline red chip below button, wizard stays open.

import SwiftUI
import FirebaseAuth

struct WizardConfirmStep: View {

    @ObservedObject var viewModel: SpaceCreationViewModel
    let communityId: String
    let onSuccess: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroHeader

                if let scaffold = viewModel.scaffold, !scaffold.description.isEmpty || !(scaffold.discussionPrompts.isEmpty) {
                    scaffoldPreview(scaffold)
                }

                pricingSummary

                createButton

                if let err = viewModel.createError {
                    errorChip(err)
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .onChange(of: viewModel.createdSpaceId) {
            if let id = viewModel.createdSpaceId {
                onSuccess(id)
            }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 14) {
            let currentUser = Auth.auth().currentUser
            let displayName = currentUser?.displayName ?? currentUser?.email ?? "Me"

            SpaceAvatarView(
                avatarURL: currentUser?.photoURL?.absoluteString,
                title: displayName,
                size: 72,
                isShared: false
            )

            VStack(spacing: 6) {
                Text(viewModel.title.isEmpty ? "Untitled Space" : viewModel.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 8) {
                    if let type = viewModel.selectedType {
                        typeBadge(type)
                    }
                    accessBadge
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .amenGlassCard()
    }

    // MARK: - Type badge

    private func typeBadge(_ type: AmenSpace.SpaceType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: spaceTypeSymbol(type))
                .font(.system(size: 11, weight: .medium))
                .accessibilityHidden(true)
            Text(spaceTypeLabel(type))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AmenTheme.Colors.amenPurple)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous).fill(AmenTheme.Colors.amenPurple.opacity(0.12))
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(AmenTheme.Colors.amenPurple.opacity(0.30), lineWidth: 0.5)
        }
        .accessibilityLabel("Type: \(spaceTypeLabel(type))")
    }

    // MARK: - Access badge

    private var accessBadge: some View {
        let label = accessBadgeLabel
        let isPaid = viewModel.accessPolicy != .free
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isPaid ? .black : AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(isPaid ? AmenTheme.Colors.amenGold : AmenTheme.Colors.surfaceChip)
            }
            .accessibilityLabel("Access: \(label)")
    }

    private var accessBadgeLabel: String {
        switch viewModel.accessPolicy {
        case .free:
            return "Free"
        case .oneTime:
            return String(format: "$%.2f", Double(viewModel.amountCents) / 100.0)
        case .recurring:
            let dollars = Double(viewModel.amountCents) / 100.0
            let suffix: String
            switch viewModel.selectedInterval {
            case "weekly":  suffix = "/week"
            case "yearly":  suffix = "/year"
            default:        suffix = "/month"
            }
            return String(format: "$%.2f\(suffix)", dollars)
        }
    }

    // MARK: - Scaffold preview

    private func scaffoldPreview(_ scaffold: SpaceBereanScaffold) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Berean suggests", systemImage: "sparkle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)

            Divider().background(AmenTheme.Colors.separatorSubtle)

            if !scaffold.description.isEmpty {
                Text(scaffold.description)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.selectedType == .bibleStudy {
                if let refs = scaffold.passageRefs, !refs.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 12))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(refs.joined(separator: " · "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
                if let cadence = scaffold.cadenceSuggestion, !cadence.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                            .accessibilityHidden(true)
                        Text(cadence)
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            }

            if !scaffold.discussionPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(scaffold.discussionPrompts.prefix(3).enumerated()), id: \.offset) { _, prompt in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(AmenTheme.Colors.amenPurple)
                                .padding(.top, 6)
                                .accessibilityHidden(true)
                            Text(prompt)
                                .font(.subheadline)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(20)
        .amenGlassCard()
    }

    // MARK: - Pricing summary

    private var pricingSummary: some View {
        HStack {
            Label("Pricing", systemImage: "tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Spacer()
            Text(pricingLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pricing: \(pricingLabel)")
    }

    private var pricingLabel: String {
        switch viewModel.accessPolicy {
        case .free:
            return "Free"
        case .oneTime:
            return String(format: "$%.2f one-time", Double(viewModel.amountCents) / 100.0)
        case .recurring:
            let dollars = Double(viewModel.amountCents) / 100.0
            let suffix: String
            switch viewModel.selectedInterval {
            case "weekly":  suffix = "/week"
            case "yearly":  suffix = "/year"
            default:        suffix = "/month"
            }
            return String(format: "$%.2f\(suffix)", dollars)
        }
    }

    // MARK: - Create button

    private var createButton: some View {
        Button {
            Task { await viewModel.createSpace(communityId: communityId) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(viewModel.canAdvance ? AmenTheme.Colors.amenGold : AmenTheme.Colors.amenGold.opacity(0.45))
                    .frame(height: 52)

                if viewModel.isCreating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                        .controlSize(.regular)
                } else {
                    Text("Create Space")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black.opacity(viewModel.canAdvance ? 1.0 : 0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canAdvance)
        .accessibilityLabel(viewModel.isCreating ? "Creating Space..." : "Create Space")
        .accessibilityHint(viewModel.canAdvance ? "Double-tap to create your new Space." : "Complete required fields first.")
    }

    // MARK: - Error chip

    private func errorChip(_ error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AmenTheme.Colors.statusError)
                .font(.system(size: 16))
                .accessibilityHidden(true)
            Text(error.userFriendlyMessage)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.statusError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(AmenTheme.Colors.statusError.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .strokeBorder(AmenTheme.Colors.statusError.opacity(0.30), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.localizedDescription)")
    }

    // MARK: - Helpers

    private func spaceTypeLabel(_ type: AmenSpace.SpaceType) -> String {
        switch type {
        case .chat:         return "Discussion"
        case .bibleStudy:   return "Study"
        case .group:        return "Group"
        case .announcement: return "Announcement"
        }
    }

    private func spaceTypeSymbol(_ type: AmenSpace.SpaceType) -> String {
        switch type {
        case .chat:         return "bubble.left.and.bubble.right"
        case .bibleStudy:   return "book.closed"
        case .group:        return "person.3"
        case .announcement: return "megaphone"
        }
    }
}

#if DEBUG
#Preview("WizardConfirmStep") {
    let vm = SpaceCreationViewModel()
    vm.selectedType = .bibleStudy
    vm.title = "Romans: The Gospel Unpacked"
    vm.scaffold = SpaceBereanScaffold(
        description: "A deep dive into Paul's letter exploring grace and faith.",
        passageRefs: ["Romans 1–8"],
        cadenceSuggestion: "5-week study",
        discussionPrompts: ["What does justified by faith mean?", "How does Romans 8 speak to your season?"],
        suggestedTitle: nil
    )
    vm.accessPolicy = .recurring
    vm.amountCents = 999
    vm.selectedInterval = "monthly"
    return ScrollView {
        WizardConfirmStep(viewModel: vm, communityId: "preview") { _ in }
    }
    .background(.ultraThinMaterial)
}
#endif
