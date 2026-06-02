// AmenSpaceHostOnboardingView.swift
// AMEN Spaces — Monetization: Host KYC + payout onboarding flow
//
// 3-step flow: Host Type → Identity/Entity → Payout Setup
// Glass rule: step container cards use thinMaterial chrome;
//             input fields and body text stay matte.
// Security note: no bank account numbers collected in-app.
//                Stripe hosted onboarding handles sensitive data.
// Written: 2026-06-02

import SwiftUI
import FirebaseFunctions

// MARK: - Step Definition

private enum OnboardingStep: Int, CaseIterable {
    case hostType = 0
    case identity = 1
    case payout   = 2

    var title: String {
        switch self {
        case .hostType: return "Your Host Type"
        case .identity: return "About You"
        case .payout:   return "Payout Setup"
        }
    }
}

// MARK: - Main View

struct AmenSpaceHostOnboardingView: View {
    let onComplete: (AmenSpaceHostType) -> Void
    let onDismiss: () -> Void

    @State private var currentStep: OnboardingStep = .hostType
    @State private var selectedHostType: AmenSpaceHostType? = nil
    @State private var entityName: String = ""
    @State private var entityEmail: String = ""
    @State private var ein: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submissionError: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var requiresEIN: Bool {
        switch selectedHostType {
        case .church, .organization, .nonprofit: return true
        default: return false
        }
    }

    private var canAdvanceFromIdentity: Bool {
        let base = !entityName.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !entityEmail.trimmingCharacters(in: .whitespaces).isEmpty
        if requiresEIN {
            return base && !ein.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return base
    }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar
                stepIndicator
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                stepTitle
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .padding(9)
                    .background(
                        Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    )
            }
            .accessibilityLabel("Dismiss host onboarding")
            .padding(.trailing, 20)
            .padding(.top, 16)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider().opacity(0.20) }
        )
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                stepDot(step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    private func stepDot(_ step: OnboardingStep) -> some View {
        let isActive = step == currentStep
        let isComplete = step.rawValue < currentStep.rawValue
        return ZStack {
            Circle()
                .fill(
                    isComplete
                        ? Color(hex: "D9A441")
                        : isActive
                            ? Color(hex: "D9A441").opacity(0.85)
                            : Color.white.opacity(0.18)
                )
                .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 5, weight: .black))
                    .foregroundStyle(Color(hex: "070607"))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: currentStep)
    }

    // MARK: - Step Title

    private var stepTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441").opacity(0.85))
                .textCase(.uppercase)
                .kerning(0.8)
            Text(currentStep.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .hostType:
            HostTypeStep(
                selectedType: $selectedHostType,
                reduceMotion: reduceMotion
            )
            .transition(transition)
        case .identity:
            IdentityStep(
                hostType: selectedHostType ?? .creator,
                entityName: $entityName,
                entityEmail: $entityEmail,
                ein: $ein,
                requiresEIN: requiresEIN
            )
            .transition(transition)
        case .payout:
            PayoutStep(isSubmitting: isSubmitting)
                .transition(transition)
        }
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 10) {
            if let error = submissionError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                if currentStep != .hostType {
                    backButton
                }
                continueButton
            }
        }
    }

    private var backButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.20)) {
                if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                    currentStep = prev
                }
            }
        } label: {
            Text("Back")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.70))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go back to previous step")
    }

    private var continueButton: some View {
        Button(action: advanceOrComplete) {
            Group {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color(hex: "070607"))
                } else {
                    Text(currentStep == .payout ? "Complete setup" : "Continue")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(canAdvanceCurrent ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.30))
        )
        .buttonStyle(.plain)
        .disabled(!canAdvanceCurrent || isSubmitting)
        .accessibilityLabel(currentStep == .payout ? "Complete host setup" : "Continue to next step")
    }

    private var canAdvanceCurrent: Bool {
        switch currentStep {
        case .hostType:  return selectedHostType != nil
        case .identity:  return canAdvanceFromIdentity
        case .payout:    return true
        }
    }

    private func advanceOrComplete() {
        if currentStep == .payout {
            submitKYC()
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                    currentStep = next
                }
            }
        }
    }

    private func submitKYC() {
        guard let hostType = selectedHostType else { return }
        isSubmitting = true
        submissionError = nil
        Task {
            do {
                let callable = Functions.functions().httpsCallable(AmenSpacesPhase1Callable.hostKYCOnboarding.rawValue)
                var payload: [String: Any] = [
                    "hostType": hostType.rawValue,
                    "entityName": entityName.trimmingCharacters(in: .whitespaces),
                    "entityEmail": entityEmail.trimmingCharacters(in: .whitespaces),
                ]
                if requiresEIN {
                    payload["ein"] = ein.trimmingCharacters(in: .whitespaces)
                }
                _ = try await callable.call(payload)
                await MainActor.run {
                    isSubmitting = false
                    onComplete(hostType)
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "Setup could not be completed. Please try again."
                }
            }
        }
    }
}

// MARK: - Step 1: Host Type

private struct HostTypeStep: View {
    @Binding var selectedType: AmenSpaceHostType?
    let reduceMotion: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(AmenSpaceHostType.allCases, id: \.self) { type in
                    HostTypeOptionCard(
                        type: type,
                        isSelected: selectedType == type,
                        reduceMotion: reduceMotion,
                        onSelect: { selectedType = type }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

private struct HostTypeOptionCard: View {
    let type: AmenSpaceHostType
    let isSelected: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            isSelected
                                ? Color(hex: "D9A441").opacity(0.20)
                                : Color.white.opacity(0.07)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isSelected
                                        ? Color(hex: "D9A441").opacity(0.60)
                                        : Color.white.opacity(0.10),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: type.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(hex: "D9A441") : Color.white.opacity(0.55))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(type.hostDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected
                                    ? Color(hex: "D9A441").opacity(0.40)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(type.displayName). \(type.hostDescription). \(isSelected ? "Selected" : "Tap to select")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Step 2: Identity / Entity Details

private struct IdentityStep: View {
    let hostType: AmenSpaceHostType
    @Binding var entityName: String
    @Binding var entityEmail: String
    @Binding var ein: String
    let requiresEIN: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                identityCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            labeledField(
                label: hostType == .creator ? "Your name" : "Organization name",
                placeholder: hostType == .creator ? "Full name" : "Legal organization name",
                binding: $entityName,
                keyboard: .default
            )

            labeledField(
                label: "Contact email",
                placeholder: "you@example.com",
                binding: $entityEmail,
                keyboard: .emailAddress
            )

            if requiresEIN {
                labeledField(
                    label: "EIN (Employer Identification Number)",
                    placeholder: "XX-XXXXXXX",
                    binding: $ein,
                    keyboard: .numbersAndPunctuation
                )
                Text("Required for churches, organizations, and nonprofits to receive payouts.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func labeledField(
        label: String,
        placeholder: String,
        binding: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            TextField(placeholder, text: binding)
                .font(.system(size: 14))
                .foregroundStyle(Color.white)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .accessibilityLabel(label)
        }
    }
}

// MARK: - Step 3: Payout Setup

private struct PayoutStep: View {
    let isSubmitting: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                payoutCard
                stripeNote
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var payoutCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "245B8F").opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(hex: "245B8F").opacity(0.50), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "245B8F"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bank account")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Connected securely via Stripe")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
            }

            Text("Your bank details are entered securely on Stripe's platform. AMEN never sees or stores your account numbers.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            Button {
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Connect Bank Account")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "245B8F").opacity(0.80))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(hex: "245B8F"), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect bank account via Stripe's secure platform")
            .accessibilityHint("Opens Stripe's hosted onboarding in your browser")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var stripeNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
                .padding(.top, 1)
            Text("You can continue setup now and connect your bank account later from Settings > Payout.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.40))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Host Type Display Helpers

private extension AmenSpaceHostType {
    var displayName: String {
        switch self {
        case .creator:      return "Creator"
        case .church:       return "Church"
        case .organization: return "Organization"
        case .nonprofit:    return "Nonprofit"
        }
    }

    var hostDescription: String {
        switch self {
        case .creator:      return "Individual teacher, pastor, or content creator."
        case .church:       return "Registered local church or denomination."
        case .organization: return "Ministry, para-church, or faith-based organization."
        case .nonprofit:    return "501(c)(3) or equivalent registered nonprofit."
        }
    }

    var iconName: String {
        switch self {
        case .creator:      return "person.fill"
        case .church:       return "building.columns"
        case .organization: return "person.3.fill"
        case .nonprofit:    return "heart.fill"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenSpaceHostOnboardingView(
        onComplete: { _ in },
        onDismiss: {}
    )
}
#endif
