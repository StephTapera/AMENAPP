// FindChurch2ClaimView.swift
// AMENAPP — Find Church 2.0, Wave 5
//
// Church-side claim flow. Allows a representative to claim an unclaimed
// church profile, choose a verification method, and submit a ClaimRequest
// to Firestore.
//
// Design rules:
//   - Glass: .ultraThinMaterial only — no nested glass
//   - Luminous border: Color.white.opacity(0.45) at 0.5pt
//   - reduceMotion guard on ALL animations
//   - Dynamic Type only — no fixed font sizes
//   - All tap targets ≥ 44×44pt
//   - No force-unwrap
//   - Async/await throughout
//
// Feature gate: findChurch2_claimPortal
//   (AMENFeatureFlags.shared.findChurch2ClaimPortalEnabled)

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - FindChurch2ClaimButton

/// Small "Is this your church?" button shown on unclaimed church profiles.
/// Taps to open FindChurch2ClaimFlowView as a sheet.
/// Only renders when church.claimState == .unclaimed and the flag is enabled.
struct FindChurch2ClaimButton: View {

    let church: ChurchObject

    @State private var isShowingClaimFlow = false

    private var isEligible: Bool {
        church.claimState == .unclaimed &&
        AMENFeatureFlags.shared.findChurch2ClaimPortalEnabled
    }

    var body: some View {
        if isEligible {
            Button {
                isShowingClaimFlow = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.system(.subheadline))
                        .accessibilityHidden(true)
                    Text("Is this your church?")
                        .font(.system(.subheadline).weight(.medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(claimButtonBackground)
                .overlay(claimButtonBorder)
                .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Claim this church profile")
            .accessibilityHint("Opens a form to verify you manage \(church.name)")
            .sheet(isPresented: $isShowingClaimFlow) {
                FindChurch2ClaimFlowView(church: church)
            }
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    private var claimButtonBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }

    private var claimButtonBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - FindChurch2ClaimFlowView

/// Three-step sheet flow for claiming an unclaimed church profile.
/// Step 1: Confirmation of identity (church name + address)
/// Step 2: Verification method selection
/// Step 3: Review + Submit
struct FindChurch2ClaimFlowView: View {

    let church: ChurchObject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Step state
    @State private var currentStep: ClaimStep = .confirmation

    // Step 2 inputs
    @State private var selectedMethod: ChurchObject.VerificationTier = .domain
    @State private var emailInput: String = ""
    @State private var einInput: String = ""

    // Submission state
    @State private var isSubmitting: Bool = false
    @State private var submitResult: SubmitResult? = nil

    enum ClaimStep: Int, CaseIterable {
        case confirmation = 0
        case verification = 1
        case review       = 2
        case done         = 3
    }

    enum SubmitResult {
        case success
        case failure(String)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Sheet background
                Group {
                    if reduceTransparency {
                        Color(.systemBackground)
                    } else {
                        Color(.systemBackground).opacity(0.92)
                    }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if currentStep != .done {
                        progressDots
                            .padding(.top, 20)
                            .padding(.bottom, 4)
                    }

                    stepContent
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                        )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep != .done {
                        Button("Cancel") { dismiss() }
                            .accessibilityLabel("Cancel claim flow")
                    }
                }
            }
        }
    }

    // MARK: - Navigation title

    private var navigationTitle: String {
        switch currentStep {
        case .confirmation: return "Is this your church?"
        case .verification: return "Verify Your Role"
        case .review:       return "Review & Submit"
        case .done:         return "Claim Submitted"
        }
    }

    // MARK: - Progress dots (steps 1–3 only)

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index == currentStep.rawValue ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep.rawValue + 1) of 3")
    }

    // MARK: - Step routing

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .confirmation:
            confirmationStep
        case .verification:
            verificationStep
        case .review:
            reviewStep
        case .done:
            doneStep
        }
    }

    // MARK: - Step 1: Confirmation

    @ViewBuilder private var confirmationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Church details")
                            .font(.system(.subheadline).weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(church.name)
                            .font(.system(.title3).weight(.bold))
                            .foregroundStyle(.primary)

                        Text(church.address)
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)

                        if let city = church.city as String?, !city.isEmpty {
                            Text("\(city)\(church.state.map { ", \($0)" } ?? "")\(church.zipCode.map { " \($0)" } ?? "")")
                                .font(.system(.caption))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Text("Claiming this profile means you're an authorized representative of this church. Our Trust team will review your submission.")
                    .font(.system(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                Spacer(minLength: 0)
            }
            .padding()
        }

        VStack(spacing: 0) {
            Divider()
            Button {
                advance()
            } label: {
                Text("Yes, I manage this church")
                    .font(.system(.body).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .accessibilityLabel("Confirm: I manage \(church.name)")
        }
    }

    // MARK: - Step 2: Verification method

    @ViewBuilder private var verificationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How would you like to verify your role?")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // Domain email option
                verificationOptionCard(
                    tier: .domain,
                    title: "Email domain match",
                    description: "I have an email from this church's domain",
                    systemImage: "envelope.fill"
                )

                if selectedMethod == .domain {
                    glassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Church email address")
                                .font(.system(.caption).weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("you@churchdomain.org", text: $emailInput)
                                .font(.system(.body))
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Church email address")
                        }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                // EIN option
                verificationOptionCard(
                    tier: .ein,
                    title: "EIN verification",
                    description: "I have the church's EIN (tax ID number)",
                    systemImage: "doc.text.fill"
                )

                if selectedMethod == .ein {
                    glassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Church EIN")
                                .font(.system(.caption).weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("XX-XXXXXXX", text: $einInput)
                                .font(.system(.body).monospaced())
                                .textContentType(.none)
                                .keyboardType(.numbersAndPunctuation)
                                .autocorrectionDisabled()
                                .frame(minHeight: 44)
                                .accessibilityLabel("Church EIN, format: two digits, dash, seven digits")
                        }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                // Manual / documents option
                verificationOptionCard(
                    tier: .manual,
                    title: "Submit documentation",
                    description: "I'll submit paperwork for manual review by our Trust team",
                    systemImage: "folder.fill"
                )

                if selectedMethod == .manual {
                    glassCard {
                        Text("After submission, our Trust team will contact you to arrange document review. This process typically takes 3–5 business days.")
                            .font(.system(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 20)
            }
            .padding()
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: selectedMethod)
        }

        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button("Back") { retreat() }
                    .frame(minWidth: 80, minHeight: 50)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Go back to confirmation step")

                Button("Continue") { advance() }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .buttonStyle(.borderedProminent)
                    .disabled(!step2IsValid)
                    .accessibilityLabel("Continue to review step")
            }
            .padding()
        }
    }

    private var step2IsValid: Bool {
        switch selectedMethod {
        case .domain: return !emailInput.trimmingCharacters(in: .whitespaces).isEmpty
        case .ein:    return !einInput.trimmingCharacters(in: .whitespaces).isEmpty
        case .manual: return true
        case .none:   return false
        }
    }

    @ViewBuilder
    private func verificationOptionCard(
        tier: ChurchObject.VerificationTier,
        title: String,
        description: String,
        systemImage: String
    ) -> some View {
        let isSelected = selectedMethod == tier

        Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                selectedMethod = tier
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(.title3))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title3))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 64)
            .background(optionBackground(isSelected: isSelected))
            .overlay(optionBorder(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(description)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func optionBackground(isSelected: Bool) -> some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color(.systemFill) : Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.18 : 0.06))
                )
        }
    }

    private func optionBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.45),
                lineWidth: 0.5
            )
    }

    // MARK: - Step 3: Review + Submit

    @ViewBuilder private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                glassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        summaryRow(label: "Church", value: church.name)
                        summaryRow(label: "Address", value: church.address)
                        Divider()
                        summaryRow(label: "Verification", value: verificationMethodLabel)
                        if !emailInput.isEmpty && selectedMethod == .domain {
                            summaryRow(label: "Email", value: emailInput)
                        }
                        if !einInput.isEmpty && selectedMethod == .ein {
                            summaryRow(label: "EIN", value: maskedEIN(einInput))
                        }
                    }
                }

                // Privacy note
                glassCard {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Your submission is reviewed by our Trust team. Sensitive details are handled per our Privacy Policy and are not shared publicly.")
                            .font(.system(.footnote))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding()
        }

        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button("Back") { retreat() }
                    .frame(minWidth: 80, minHeight: 50)
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting)
                    .accessibilityLabel("Go back to verification step")

                Button {
                    Task { await submitClaim() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Submit Claim")
                                .font(.system(.body).weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
                .accessibilityLabel("Submit church claim")
            }
            .padding()
        }
    }

    private var verificationMethodLabel: String {
        switch selectedMethod {
        case .domain: return "Email domain match"
        case .ein:    return "EIN verification"
        case .manual: return "Document submission"
        case .none:   return "Unknown"
        }
    }

    private func maskedEIN(_ ein: String) -> String {
        let stripped = ein.replacingOccurrences(of: "-", with: "")
        guard stripped.count >= 4 else { return "••-•••••••" }
        let last4 = stripped.suffix(4)
        return "••-•••\(last4)"
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(.footnote).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(.footnote))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Step 4: Done / Confirmation

    private var doneStep: some View {
        VStack(spacing: 24) {
            Spacer()

            switch submitResult {
            case .success, .none:
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    Text("Claim Submitted")
                        .font(.system(.title2).weight(.bold))

                    Text("Your claim is under review. We'll notify you within 3 business days.")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

            case .failure(let message):
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)

                    Text("Submission Failed")
                        .font(.system(.title2).weight(.bold))

                    Text(message)
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Spacer()

            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity, minHeight: 50)
                .buttonStyle(.borderedProminent)
                .padding()
                .accessibilityLabel("Dismiss and close")
        }
    }

    // MARK: - Navigation helpers

    private func advance() {
        guard let next = ClaimStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
            currentStep = next
        }
    }

    private func retreat() {
        guard let prev = ClaimStep(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
            currentStep = prev
        }
    }

    // MARK: - Submit

    private func submitClaim() async {
        isSubmitting = true
        defer { isSubmitting = false }

        guard let uid = Auth.auth().currentUser?.uid else {
            advance()
            submitResult = .failure("You must be signed in to submit a claim.")
            return
        }

        let requestId = UUID().uuidString
        let request = ClaimRequest(
            id: requestId,
            churchId: church.id,
            claimantUid: uid,
            verificationMethod: selectedMethod,
            emailDomain: selectedMethod == .domain
                ? emailInput.trimmingCharacters(in: .whitespaces)
                : nil,
            einProvided: selectedMethod == .ein
                ? einInput.trimmingCharacters(in: .whitespaces)
                : nil,
            documentURLs: [],
            status: .submitted,
            submittedAt: Date(),
            reviewedAt: nil,
            reviewerNote: nil
        )

        do {
            let db = Firestore.firestore()
            let data = try Firestore.Encoder().encode(request)
            try await db.collection("claimRequests").document(requestId).setData(data)
            submitResult = .success
        } catch {
            submitResult = .failure(error.localizedDescription)
        }

        advance() // Move to done step regardless of outcome
    }

    // MARK: - Shared glass card helper

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(glassCardBackground)
            .overlay(glassCardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var glassCardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var glassCardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - Previews

#if DEBUG
private let _claimPreviewChurch = ChurchObject(
    id: "claim-preview-1",
    placeId: nil,
    ein: nil,
    name: "Cornerstone Bible Church",
    normalizedName: "cornerstone bible church",
    address: "800 Church St",
    normalizedAddress: "800 church st",
    city: "Austin",
    state: "TX",
    zipCode: "78701",
    country: "US",
    coordinate: .init(latitude: 30.267, longitude: -97.743),
    phoneNumber: nil,
    email: nil,
    website: nil,
    photoURL: nil,
    logoURL: nil,
    denomination: "Southern Baptist Convention",
    denominationFamily: "Baptist",
    denominationIsFlexible: false,
    denominationLineage: ["Protestant", "Evangelical", "Baptist", "SBC"],
    beliefs: nil,
    serviceTimes: [],
    mediaLinks: .init(),
    accessibility: .init(),
    claimState: .unclaimed,
    verificationTier: .none,
    claimedBy: nil,
    claimedAt: nil,
    childSafetyPolicy: .init(),
    staffCount: nil,
    ministryTags: [],
    gatheringIds: [],
    availabilityCache: nil,
    availabilityCachedAt: nil,
    pendingServiceTimeSuggestions: 0,
    amenMemberCount: 0,
    visitCount: 0,
    friendSavedCount: 0,
    source: .googlePlaces,
    createdAt: Date(),
    updatedAt: Date(),
    isDeleted: false
)

#Preview("Claim button (unclaimed)") {
    VStack {
        FindChurch2ClaimButton(church: _claimPreviewChurch)
    }
    .padding()
}

#Preview("Claim flow sheet") {
    FindChurch2ClaimFlowView(church: _claimPreviewChurch)
}
#endif
