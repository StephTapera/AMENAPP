// AmenOrgOnboardingFlow.swift
// AMENAPP
//
// 5-step Liquid Glass onboarding wizard for creating or joining an organization.
// Presented as a .sheet from any org entry-point in the app.
//
// Usage:
//   .sheet(isPresented: $showOnboarding) {
//       AmenOrgOnboardingFlow { result in
//           // handle OrgSpaceCreationResult
//       }
//   }
//

import SwiftUI

// MARK: - Supporting Models

enum OrgSpaceType: String, CaseIterable, Identifiable {
    case church
    case school
    case ministry
    case smallGroup
    case enterprise

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .church:     return "building.columns.fill"
        case .school:     return "graduationcap.fill"
        case .ministry:   return "hands.sparkles.fill"
        case .smallGroup: return "book.fill"
        case .enterprise: return "building.2.fill"
        }
    }

    var emoji: String {
        switch self {
        case .church:     return "⛪"
        case .school:     return "🎓"
        case .ministry:   return "🙏"
        case .smallGroup: return "📖"
        case .enterprise: return "🏢"
        }
    }

    var displayName: String {
        switch self {
        case .church:     return "Church / Parish"
        case .school:     return "School / University"
        case .ministry:   return "Ministry / Nonprofit"
        case .smallGroup: return "Bible Study / Small Group"
        case .enterprise: return "Enterprise / Organization"
        }
    }

    var description: String {
        switch self {
        case .church:     return "For congregations and worship communities"
        case .school:     return "For faith-based education communities"
        case .ministry:   return "For outreach, missions, and service orgs"
        case .smallGroup: return "For intimate study and fellowship"
        case .enterprise: return "For faith-at-work communities"
        }
    }
}

enum OrgPlan: String, CaseIterable {
    case free
    case ministry
    case enterprise

    var displayName: String {
        switch self {
        case .free:       return "Free"
        case .ministry:   return "Ministry"
        case .enterprise: return "Enterprise"
        }
    }

    var priceLabel: String {
        switch self {
        case .free:       return "$0/mo"
        case .ministry:   return "$12/mo"
        case .enterprise: return "Contact us"
        }
    }

    var tagline: String {
        switch self {
        case .free:
            return "Up to 10 members · 3 channels · Basic Berean AI"
        case .ministry:
            return "Unlimited members · Unlimited channels · Full Berean AI · Prayer analytics"
        case .enterprise:
            return "Custom · SSO · Admin console · Priority support"
        }
    }

    var badge: String {
        switch self {
        case .free:       return "Start here"
        case .ministry:   return "Most popular"
        case .enterprise: return "For large orgs"
        }
    }
}

struct OrgSpaceCreationResult {
    var orgType: OrgSpaceType
    var name: String
    var tagline: String
    var accentHex: String
    var inviteEmails: [String]
    var selectedChannels: [String]
    var plan: OrgPlan
}

// MARK: - Channel Model

private struct SuggestedChannel: Identifiable {
    let id: String
    let icon: String           // "#" or "lock"
    let name: String
    let description: String
    let isRequired: Bool
    let isPrivate: Bool
    let defaultEnabled: Bool
}

private let suggestedChannels: [SuggestedChannel] = [
    SuggestedChannel(id: "announcements",   icon: "#", name: "announcements",   description: "Important updates for everyone",              isRequired: true,  isPrivate: false, defaultEnabled: true),
    SuggestedChannel(id: "prayer-requests", icon: "#", name: "prayer-requests", description: "Share and receive prayer needs",               isRequired: false, isPrivate: false, defaultEnabled: true),
    SuggestedChannel(id: "sermon-notes",    icon: "#", name: "sermon-notes",    description: "Notes, reflections, and sermon highlights",    isRequired: false, isPrivate: false, defaultEnabled: true),
    SuggestedChannel(id: "general",         icon: "#", name: "general",         description: "Open conversation for the whole community",    isRequired: false, isPrivate: false, defaultEnabled: true),
    SuggestedChannel(id: "youth-ministry",  icon: "#", name: "youth-ministry",  description: "Dedicated space for youth programs",           isRequired: false, isPrivate: false, defaultEnabled: false),
    SuggestedChannel(id: "worship-team",    icon: "#", name: "worship-team",    description: "Coordination for worship leaders",             isRequired: false, isPrivate: false, defaultEnabled: false),
    SuggestedChannel(id: "leadership",      icon: "lock.fill", name: "leadership", description: "Private channel for leadership team",       isRequired: false, isPrivate: true,  defaultEnabled: false),
]

// MARK: - Accent Color Swatch Model

private struct AccentSwatch: Identifiable {
    let id: String
    let hex: String
    let color: Color
    let label: String
}

private let accentSwatches: [AccentSwatch] = [
    AccentSwatch(id: "gold",    hex: "#D3B038", color: AmenTheme.Colors.amenGold,    label: "Gold"),
    AccentSwatch(id: "purple",  hex: "#7043CC", color: AmenTheme.Colors.amenPurple,  label: "Purple"),
    AccentSwatch(id: "blue",    hex: "#0A85FF", color: AmenTheme.Colors.amenBlue,    label: "Blue"),
    AccentSwatch(id: "bronze",  hex: "#CC8033", color: AmenTheme.Colors.amenBronze,  label: "Bronze"),
    AccentSwatch(id: "success", hex: "#2ECC69", color: AmenTheme.Colors.statusSuccess, label: "Green"),
    AccentSwatch(id: "info",    hex: "#239BE6", color: AmenTheme.Colors.statusInfo,  label: "Sky"),
]

// MARK: - Root Flow View

struct AmenOrgOnboardingFlow: View {

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Step state

    @State private var currentStep: Int = 1
    @State private var stepDirection: Int = 1   // +1 forward, -1 backward

    // MARK: Step 1 — Org Type

    @State private var selectedOrgType: OrgSpaceType? = nil

    // MARK: Step 2 — Name & Identity

    @State private var orgName: String = ""
    @State private var orgTagline: String = ""
    @State private var selectedAccentHex: String = "#D3B038"

    // MARK: Step 3 — Invite

    @State private var inviteEmails: [String] = []
    @State private var emailDraft: String = ""
    @State private var emailFieldFocused: Bool = false

    // MARK: Step 4 — Channels

    @State private var selectedChannels: Set<String> = ["announcements", "prayer-requests", "sermon-notes", "general"]

    // MARK: Step 5 — Plan

    @State private var selectedPlan: OrgPlan = .free
    @State private var isCreating: Bool = false

    // MARK: Constants

    let totalSteps = 5

    // MARK: Callback

    var onComplete: (OrgSpaceCreationResult) -> Void = { _ in }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            AmenTheme.Colors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: back + progress
                headerBar
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                // Step content
                ZStack {
                    switch currentStep {
                    case 1:
                        Step1OrgTypeView(
                            selectedOrgType: $selectedOrgType,
                            onContinue: advanceStep
                        )
                        .transition(stepTransition)
                    case 2:
                        Step2NameIdentityView(
                            orgName: $orgName,
                            orgTagline: $orgTagline,
                            selectedAccentHex: $selectedAccentHex,
                            onContinue: advanceStep
                        )
                        .transition(stepTransition)
                    case 3:
                        Step3InviteMembersView(
                            inviteEmails: $inviteEmails,
                            emailDraft: $emailDraft,
                            onContinue: advanceStep
                        )
                        .transition(stepTransition)
                    case 4:
                        Step4ChannelsView(
                            selectedChannels: $selectedChannels,
                            onContinue: advanceStep
                        )
                        .transition(stepTransition)
                    case 5:
                        Step5PlanView(
                            selectedPlan: $selectedPlan,
                            isCreating: $isCreating,
                            onCreateSpace: handleCreateSpace
                        )
                        .transition(stepTransition)
                    default:
                        EmptyView()
                    }
                }
                .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75), value: currentStep)
            }
        }
        .interactiveDismissDisabled(isCreating)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                // Back button
                if currentStep > 1 {
                    Button {
                        HapticManager.impact(style: .light)
                        retreatStep()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(AMENFont.semiBold(17))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go back")
                    .accessibilityHint("Returns to the previous step")
                } else {
                    // Dismiss button on step 1
                    Button {
                        HapticManager.impact(style: .light)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Closes this onboarding flow")
                }

                Spacer()

                Text("Step \(currentStep) of \(totalSteps)")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .accessibilityLabel("Step \(currentStep) of \(totalSteps)")
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AmenTheme.Colors.surfaceChip)
                        .frame(height: 3)

                    Capsule()
                        .fill(AmenTheme.Colors.amenGold)
                        .frame(
                            width: geo.size.width * (CGFloat(currentStep) / CGFloat(totalSteps)),
                            height: 3
                        )
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8),
                            value: currentStep
                        )
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Navigation

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return stepDirection > 0
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }

    private func advanceStep() {
        stepDirection = 1
        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
            currentStep = min(currentStep + 1, totalSteps)
        }
    }

    private func retreatStep() {
        stepDirection = -1
        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
            currentStep = max(currentStep - 1, 1)
        }
    }

    // MARK: - Create Space

    private func handleCreateSpace() {
        guard !isCreating else { return }
        HapticManager.impact(style: .medium)
        isCreating = true

        let result = OrgSpaceCreationResult(
            orgType:          selectedOrgType ?? .church,
            name:             orgName,
            tagline:          orgTagline,
            accentHex:        selectedAccentHex,
            inviteEmails:     inviteEmails,
            selectedChannels: Array(selectedChannels),
            plan:             selectedPlan
        )

        // Simulate async creation handoff — caller owns the actual Firestore write.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onComplete(result)
            dismiss()
        }
    }
}

// MARK: - Step 1: Org Type Selection

private struct Step1OrgTypeView: View {

    @Binding var selectedOrgType: OrgSpaceType?
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Title area
            VStack(spacing: 6) {
                Text("What kind of space are you building?")
                    .font(AMENFont.bold(24))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Choose the type that fits your community")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Type cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(OrgSpaceType.allCases) { orgType in
                        OrgTypeCard(
                            orgType: orgType,
                            isSelected: selectedOrgType == orgType,
                            onTap: {
                                HapticManager.impact(style: .light)
                                withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedOrgType = orgType
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Continue button
            OrgPrimaryButton(
                label: "Continue",
                isDisabled: selectedOrgType == nil,
                onTap: onContinue
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }
}

private struct OrgTypeCard: View {

    let orgType: OrgSpaceType
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(orgType.emoji)
                    .font(.system(size: 28))
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(orgType.displayName)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(orgType.description)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .font(.system(size: 22))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 60)
            .background(glassBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? AmenTheme.Colors.amenGold : Color.white.opacity(0.25),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0.06), radius: isSelected ? 10 : 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(orgType.displayName). \(orgType.description)")
        .accessibilityHint(isSelected ? "Selected" : "Tap to select this org type")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.2))
            }
        }
    }
}

// MARK: - Step 2: Name & Identity

private struct Step2NameIdentityView: View {

    @Binding var orgName: String
    @Binding var orgTagline: String
    @Binding var selectedAccentHex: String

    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var nameFieldFocused: Bool

    private var selectedAccentColor: Color {
        accentSwatches.first(where: { $0.hex == selectedAccentHex })?.color ?? AmenTheme.Colors.amenGold
    }

    private var nameInitials: String {
        let words = orgName.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if words.count >= 2 {
            return String((words[0].first ?? Character(" "))) + String((words[1].first ?? Character(" ")))
        } else if let first = words.first, !first.isEmpty {
            return String(first.prefix(2))
        }
        return "ORG"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Title
                VStack(spacing: 6) {
                    Text("Give your space a name")
                        .font(AMENFont.bold(24))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)

                // Animated icon initials preview
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [selectedAccentColor, selectedAccentColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .shadow(color: selectedAccentColor.opacity(0.4), radius: 16, y: 6)

                    Text(nameInitials.uppercased())
                        .font(AMENFont.bold(28))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75), value: nameInitials)
                .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75), value: selectedAccentHex)
                .accessibilityLabel("Org icon preview showing \(nameInitials.isEmpty ? "placeholder" : nameInitials) in \(accentSwatches.first(where: { $0.hex == selectedAccentHex })?.label ?? "gold")")
                .padding(.bottom, 24)

                // Name field
                VStack(alignment: .leading, spacing: 4) {
                    OrgGlassTextField(
                        text: $orgName,
                        placeholder: "e.g. Bethel Church",
                        charLimit: 60,
                        isFocused: _nameFieldFocused
                    )
                    .accessibilityLabel("Organization name")
                    .accessibilityHint("Enter the name for your space, up to 60 characters")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                // Tagline field
                OrgGlassTextField(
                    text: $orgTagline,
                    placeholder: "Add a short tagline (optional)",
                    charLimit: 120
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .accessibilityLabel("Org tagline")
                .accessibilityHint("Optional short description, up to 120 characters")

                // Accent color picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Accent color")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .padding(.horizontal, 20)

                    HStack(spacing: 14) {
                        ForEach(accentSwatches) { swatch in
                            AccentSwatchButton(
                                swatch: swatch,
                                isSelected: selectedAccentHex == swatch.hex,
                                onTap: {
                                    HapticManager.impact(style: .light)
                                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedAccentHex = swatch.hex
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)

                // Continue button
                OrgPrimaryButton(
                    label: "Continue",
                    isDisabled: orgName.trimmingCharacters(in: .whitespaces).count < 2,
                    onTap: onContinue
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct AccentSwatchButton: View {

    let swatch: AccentSwatch
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(swatch.color)
                    .frame(width: 36, height: 36)
                    .shadow(color: swatch.color.opacity(0.4), radius: 6, y: 2)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2.5)
                        .frame(width: 36, height: 36)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.label + (isSelected ? ", selected" : ""))
        .accessibilityHint(isSelected ? "" : "Tap to use \(swatch.label) as your accent color")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Step 3: Invite Members

private struct Step3InviteMembersView: View {

    @Binding var inviteEmails: [String]
    @Binding var emailDraft: String
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var emailFieldFocused: Bool

    private let inviteLink = "https://amen.app/join/your-space-id"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Title
                VStack(spacing: 6) {
                    Text("Invite your community")
                        .font(AMENFont.bold(24))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("You can always add more later")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)

                // Share card
                inviteLinkCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                // Email invite field
                emailInviteSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                // Email chips
                if !inviteEmails.isEmpty {
                    emailChipsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                // Skip link
                Button {
                    HapticManager.impact(style: .light)
                    onContinue()
                } label: {
                    Text("Skip for now")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip inviting members for now")
                .accessibilityHint("You can add members later from the org settings")
                .padding(.bottom, 12)

                // Continue button
                OrgPrimaryButton(
                    label: "Continue",
                    isDisabled: false,
                    onTap: onContinue
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: Invite link card

    private var inviteLinkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AmenTheme.Colors.amenGold)

                Text("Share invite link")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }

            Text(inviteLink)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 10) {
                Button {
                    HapticManager.impact(style: .light)
                    UIPasteboard.general.string = inviteLink
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                        Text("Copy link")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(AmenTheme.Colors.surfaceChip)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy invite link")
                .accessibilityHint("Copies the invite link to your clipboard")

                Button {
                    HapticManager.impact(style: .light)
                    shareLink()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                        Text("Share")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(AmenTheme.Colors.buttonPrimary)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share invite link")
                .accessibilityHint("Opens the system share sheet with your invite link")
            }
        }
        .padding(18)
        .background(inviteCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    @ViewBuilder
    private var inviteCardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.2))
            }
        }
    }

    // MARK: Email invite section

    private var emailInviteSection: some View {
        HStack(spacing: 10) {
            TextField("Add email addresses", text: $emailDraft)
                .font(AMENFont.regular(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled(true)
                .focused($emailFieldFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                )
                .accessibilityLabel("Email address input")
                .accessibilityHint("Type an email address and tap Add to invite")

            Button {
                HapticManager.impact(style: .light)
                addEmail()
            } label: {
                Text("Add")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(emailDraft.isEmpty ? AmenTheme.Colors.surfaceChip : AmenTheme.Colors.buttonPrimary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(emailDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Add email")
            .accessibilityHint("Adds the entered email to the invite list")
        }
    }

    // MARK: Email chips

    private var emailChipsSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
            spacing: 8
        ) {
            ForEach(inviteEmails, id: \.self) { email in
                emailChip(email: email)
            }
        }
    }

    private func emailChip(email: String) -> some View {
        HStack(spacing: 6) {
            Text(email)
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)

            Button {
                HapticManager.impact(style: .light)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    inviteEmails.removeAll { $0 == email }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(email)")
            .accessibilityHint("Removes this email from the invite list")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(AmenTheme.Colors.surfaceChip)
        )
    }

    // MARK: Helpers

    private func addEmail() {
        let trimmed = emailDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !inviteEmails.contains(trimmed) else {
            emailDraft = ""
            return
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            inviteEmails.append(trimmed)
            emailDraft = ""
        }
    }

    private func shareLink() {
        let activityVC = UIActivityViewController(
            activityItems: [inviteLink],
            applicationActivities: nil
        )
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        topVC.present(activityVC, animated: true)
    }
}

// MARK: - Step 4: Suggested Channels

private struct Step4ChannelsView: View {

    @Binding var selectedChannels: Set<String>
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 6) {
                Text("Start with these channels")
                    .font(AMENFont.bold(24))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Built for faith communities — edit anytime")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(suggestedChannels) { channel in
                        ChannelToggleRow(
                            channel: channel,
                            isEnabled: channel.isRequired || selectedChannels.contains(channel.id),
                            onToggle: {
                                guard !channel.isRequired else { return }
                                HapticManager.impact(style: .light)
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                    if selectedChannels.contains(channel.id) {
                                        selectedChannels.remove(channel.id)
                                    } else {
                                        selectedChannels.insert(channel.id)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(reduceTransparency ? AnyShapeStyle(AmenTheme.Colors.surfaceCard) : AnyShapeStyle(.ultraThinMaterial.opacity(0.7)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            OrgPrimaryButton(
                label: "Continue",
                isDisabled: false,
                onTap: onContinue
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }
}

private struct ChannelToggleRow: View {

    let channel: SuggestedChannel
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: channel.isPrivate ? "lock.fill" : "number")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isEnabled ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textTertiary
                    )
                    .frame(width: 20)
                    .accessibilityHidden(true)

                // Name + description
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .lineLimit(1)

                        if channel.isRequired {
                            Text("required")
                                .font(AMENFont.semiBold(10))
                                .foregroundStyle(AmenTheme.Colors.amenGold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(AmenTheme.Colors.amenGold.opacity(0.15))
                                )
                        }
                    }

                    Text(channel.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Toggle indicator
                ZStack {
                    if channel.isRequired {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.5))
                    } else {
                        Toggle("", isOn: .constant(isEnabled))
                            .labelsHidden()
                            .tint(AmenTheme.Colors.amenGold)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .disabled(channel.isRequired)
        .overlay(
            Divider()
                .foregroundStyle(AmenTheme.Colors.separatorSubtle)
                .frame(maxWidth: .infinity, maxHeight: 0.5)
                .offset(y: 0),
            alignment: .bottom
        )
        .accessibilityLabel("\(channel.isPrivate ? "Private channel" : "Channel") \(channel.name). \(channel.description)\(channel.isRequired ? ". Required" : "")")
        .accessibilityHint(channel.isRequired ? "This channel is always included" : (isEnabled ? "Tap to remove this channel" : "Tap to include this channel"))
        .accessibilityAddTraits(isEnabled ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Step 5: Choose Plan

private struct Step5PlanView: View {

    @Binding var selectedPlan: OrgPlan
    @Binding var isCreating: Bool
    let onCreateSpace: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var createButtonScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Title
            VStack(spacing: 6) {
                Text("Choose your plan")
                    .font(AMENFont.bold(24))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Start free, grow as your community does")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(OrgPlan.allCases, id: \.rawValue) { plan in
                        PlanCard(
                            plan: plan,
                            isSelected: selectedPlan == plan,
                            onTap: {
                                HapticManager.impact(style: .light)
                                withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedPlan = plan
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Create Space button
            Button {
                guard !isCreating else { return }
                HapticManager.impact(style: .medium)
                withAnimation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.6)) {
                    createButtonScale = 0.95
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                        createButtonScale = 1.0
                    }
                    onCreateSpace()
                }
            } label: {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "sparkles")
                            .font(AMENFont.semiBold(15))
                    }
                    Text(isCreating ? "Creating your space…" : "Create Space")
                        .font(AMENFont.bold(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AmenTheme.Colors.statusSuccess)
                        .shadow(color: AmenTheme.Colors.statusSuccess.opacity(0.4), radius: 12, y: 4)
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(createButtonScale)
            .disabled(isCreating)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityLabel(isCreating ? "Creating your space" : "Create Space")
            .accessibilityHint("Finalizes your setup and creates the organization space")

            // Privacy note
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Text("Your space is private until you invite members")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 32)
            .accessibilityLabel("Your space is private until you invite members")
        }
    }
}

private struct PlanCard: View {

    let plan: OrgPlan
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(plan.displayName)
                            .font(AMENFont.bold(17))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)

                        planBadge
                    }

                    Text(plan.tagline)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(plan.priceLabel)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(
                            plan == .free
                                ? AmenTheme.Colors.statusSuccess
                                : AmenTheme.Colors.textPrimary
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                    }
                }
            }
            .padding(18)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? AmenTheme.Colors.amenGold : Color.white.opacity(0.25),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0.06), radius: isSelected ? 10 : 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plan.displayName) plan. \(plan.tagline). \(plan.priceLabel). \(plan.badge)")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select this plan")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var planBadge: some View {
        switch plan {
        case .free:
            Text(plan.badge)
                .font(AMENFont.semiBold(10))
                .foregroundStyle(AmenTheme.Colors.statusSuccess)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(AmenTheme.Colors.statusSuccess.opacity(0.14))
                )
        case .ministry:
            Text(plan.badge)
                .font(AMENFont.bold(10))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(AmenTheme.Colors.amenGold.opacity(0.18))
                )
        case .enterprise:
            Text(plan.badge)
                .font(AMENFont.semiBold(10))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(AmenTheme.Colors.surfaceChip)
                )
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.2))
            }
        }
    }
}

// MARK: - Shared Components

// MARK: Primary Button

private struct OrgPrimaryButton: View {

    let label: String
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(AMENFont.bold(16))
                .foregroundStyle(isDisabled ? AmenTheme.Colors.textTertiary : AmenTheme.Colors.buttonPrimaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isDisabled ? AmenTheme.Colors.surfaceChip : AmenTheme.Colors.buttonPrimary)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityHint(isDisabled ? "Complete the required fields to continue" : "Proceeds to the next step")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Glass Text Field with Char Limit

private struct OrgGlassTextField: View {

    @Binding var text: String
    let placeholder: String
    let charLimit: Int
    @FocusState var isFocused: Bool

    init(text: Binding<String>, placeholder: String, charLimit: Int) {
        self._text = text
        self.placeholder = placeholder
        self.charLimit = charLimit
    }

    // Designated init accepting a FocusState binding
    init(text: Binding<String>, placeholder: String, charLimit: Int, isFocused: FocusState<Bool>) {
        self._text = text
        self.placeholder = placeholder
        self.charLimit = charLimit
        self._isFocused = isFocused
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField(placeholder, text: $text)
                .font(AMENFont.regular(16))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    if newValue.count > charLimit {
                        text = String(newValue.prefix(charLimit))
                    }
                }
                .padding(.trailing, 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                )

            Text("\(text.count)/\(charLimit)")
                .font(AMENFont.regular(11))
                .foregroundStyle(
                    text.count >= charLimit
                        ? AmenTheme.Colors.statusError
                        : AmenTheme.Colors.textTertiary
                )
                .padding(.trailing, 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
