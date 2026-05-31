//
//  AmenTrustSafetyComponents.swift
//  AMENAPP
//
//  All 11 reusable SwiftUI components for the Amen Trust + Safety OS.
//
//  Components:
//    SafetyPreflightBanner      — checking/clean/labeled/blocked states
//    TrueSourceBadge            — provenance label on media
//    AIContentLabel             — AI-generated / AI-assisted label
//    SourceUncertainWarning     — source uncertain friction
//    BotSuspicionFrictionView   — challenge screen for suspected bots
//    ReportAbuseSheet           — full report flow sheet
//    WellnessPauseSheet         — gentle wellness intervention
//    VerifiedIdentityBadge      — trust level badge
//    TrustDetailsSheet          — "Why is this verified?" detail sheet
//    LimitedDistributionNotice  — notice for limited-reach content
//    AppealDecisionView         — appeal a safety decision
//
//  Language: calm, direct, non-preachy.
//  Accessibility: all labels set, reduced motion respected.
//

import SwiftUI

// MARK: - 1. SafetyPreflightBanner

struct SafetyPreflightBanner: View {
    let state: ContentPreflightState
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        if let (message, color, icon) = bannerContent(for: state) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if case .labeled = state, let dismiss = onDismiss {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss notice")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
        }
    }

    private func bannerContent(for state: ContentPreflightState) -> (String, Color, String)? {
        switch state {
        case .checking:
            return ("This post is being checked before it appears.", .blue, "shield.lefthalf.filled")
        case .labeled(let r):
            return (r, .orange, "tag.fill")
        case .limited(let r):
            return (r, .orange, "eye.slash.fill")
        case .blocked(let r):
            return (r, .red, "xmark.shield.fill")
        case .quarantined(let r):
            return (r, .yellow, "clock.badge.questionmark.fill")
        case .underReview:
            return ("Your post is being reviewed.", .yellow, "clock.fill")
        case .error(let e):
            return (e, .red, "exclamationmark.triangle.fill")
        default:
            return nil
        }
    }
}

// MARK: - 2. TrueSourceBadge

struct ProvenanceBadge: View {
    let status: MediaAuthenticityStatus
    var compact: Bool = false
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(badgeColor)
                if !compact {
                    Text(status.displayLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(badgeColor)
                }
            }
            .padding(.horizontal, compact ? 5 : 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Source: \(status.displayLabel)")
        .sheet(isPresented: $showDetail) {
            MediaAuthenticityDetailSheet(status: status)
                .presentationDetents([.height(260)])
        }
    }

    private var iconName: String {
        switch status {
        case .original, .verifiedSource: return "checkmark.seal.fill"
        case .aiGenerated:               return "cpu.fill"
        case .aiAssisted:                return "sparkles"
        case .edited:                    return "pencil.circle.fill"
        case .sourceUncertain, .unknown: return "questionmark.circle.fill"
        case .reposted:                  return "arrow.2.squarepath"
        case .contextMissing:            return "exclamationmark.circle.fill"
        }
    }

    private var badgeColor: Color {
        switch status {
        case .original, .verifiedSource: return .green
        case .aiGenerated:               return .purple
        case .aiAssisted:                return .indigo
        case .edited:                    return .blue
        case .sourceUncertain, .unknown,
             .contextMissing:            return .orange
        case .reposted:                  return .secondary
        }
    }
}

private struct MediaAuthenticityDetailSheet: View {
    let status: MediaAuthenticityStatus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Source information")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .accessibilityLabel("Close")
            }

            Text(status.displayLabel)
                .font(.subheadline.weight(.semibold))

            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }

    private var detailText: String {
        switch status {
        case .original:       return "This media was created by the person who shared it."
        case .edited:         return "This media has been edited from its original version."
        case .aiAssisted:     return "This media was created with help from AI tools."
        case .aiGenerated:    return "This media was generated by an AI system."
        case .reposted:       return "This media was originally shared elsewhere."
        case .verifiedSource: return "The source of this media has been confirmed."
        case .sourceUncertain:return "The origin of this media could not be confirmed. Sharing is limited."
        case .contextMissing: return "Important context about this media is missing."
        case .unknown:        return "The source of this media is not known."
        }
    }
}

// MARK: - 3. AIContentLabel

struct AIContentLabel: View {
    let labelType: AILabelType
    var showExplanation: Bool = true
    @State private var showSheet = false

    var body: some View {
        if labelType != .none {
            Button { if showExplanation { showSheet = true } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu.fill")
                        .font(.caption2)
                    Text(labelText)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(labelColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(labelColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(labelText)
            .sheet(isPresented: $showSheet) {
                AITransparencySheet(labelType: labelType)
                    .presentationDetents([.height(280)])
            }
        }
    }

    private var labelText: String {
        switch labelType {
        case .aiGenerated:    return "AI-generated"
        case .aiAssisted:     return "AI-assisted"
        case .mayBeAI:        return "May be AI"
        case .sourceUncertain:return "Source uncertain"
        case .none:           return ""
        }
    }

    private var labelColor: Color {
        switch labelType {
        case .aiGenerated:    return .purple
        case .aiAssisted:     return .indigo
        case .mayBeAI:        return .blue
        case .sourceUncertain:return .orange
        case .none:           return .clear
        }
    }
}

private struct AITransparencySheet: View {
    let labelType: AILabelType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("AI transparency", systemImage: "cpu.fill")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .accessibilityLabel("Close")
            }
            Text(explanationText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }

    private var explanationText: String {
        switch labelType {
        case .aiGenerated:
            return "This content was generated by an AI system. It may not reflect real events, people, or places."
        case .aiAssisted:
            return "This content was created with AI tools. The author may have edited or guided the output."
        case .mayBeAI:
            return "This content may have been generated or heavily edited by AI. We couldn't confirm its origin."
        case .sourceUncertain:
            return "We couldn't verify the original source of this content. Sharing is limited until source is confirmed."
        case .none:
            return ""
        }
    }
}

// MARK: - 4. SourceUncertainWarning

struct SourceUncertainWarning: View {
    let provenanceStatus: MediaAuthenticityStatus
    var onConfirmShare: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Source is uncertain")
                    .font(.subheadline.weight(.semibold))
            }

            Text("The source of this media couldn't be confirmed. Sharing content with uncertain origins can spread misinformation. Are you sure you want to share this?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if onConfirmShare != nil {
                HStack(spacing: 12) {
                    Button("Cancel") { onCancel?() }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.primary)
                    Button("Share anyway") { onConfirmShare?() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            }
        }
        .padding(16)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 5. BotSuspicionFrictionView

struct BotSuspicionFrictionView: View {
    var onChallengePassed: () -> Void
    var onCancel: () -> Void
    @State private var challengeAnswer: String = ""
    @State private var isVerifying: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text("Quick verification needed")
                .font(.title3.weight(.semibold))

            Text("We noticed unusual activity. Please confirm you're a real person to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Simple math challenge (real impl: invisible reCAPTCHA or App Check)
            VStack(spacing: 8) {
                Text("What is 3 + 4?")
                    .font(.subheadline.weight(.medium))
                TextField("Your answer", text: $challengeAnswer)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 120)
            }

            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                Button {
                    isVerifying = true
                    // Validate: answer is "7"
                    if challengeAnswer.trimmingCharacters(in: .whitespaces) == "7" {
                        onChallengePassed()
                    }
                    isVerifying = false
                } label: {
                    if isVerifying {
                        ProgressView().tint(.white)
                    } else {
                        Text("Verify")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(challengeAnswer.isEmpty || isVerifying)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

// MARK: - 6. ReportAbuseSheet

struct ReportAbuseSheet: View {
    let targetUid: String?
    let contentId: String?
    let contentType: ContentSurface?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: ReportCategory?
    @State private var details: String = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    private let service = AmenReportAbuseService.shared

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    submittedView
                } else {
                    reportFormView
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var reportFormView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What's the issue?")
                    .font(.headline)
                    .padding(.horizontal)

                LazyVStack(spacing: 0) {
                    ForEach(ReportCategory.allCases) { category in
                        reportCategoryRow(category)
                        Divider().padding(.leading, 52)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                if selectedCategory != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional details (optional)")
                            .font(.subheadline.weight(.medium))
                        TextField("Describe the issue…", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    Task { await submitReport() }
                } label: {
                    Group {
                        if isSubmitting {
                            HStack {
                                ProgressView().tint(.white)
                                Text("Submitting…")
                            }
                        } else {
                            Text("Submit report")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedCategory == nil || isSubmitting)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func reportCategoryRow(_ category: ReportCategory) -> some View {
        Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedCategory == category ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedCategory == category ? .red : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayLabel)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if category.isCritical {
                        Text("Emergency priority")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
    }

    private var submittedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Report submitted")
                .font(.title3.weight(.semibold))
            Text("Thank you for helping keep Amen safe. We'll review this report and take appropriate action.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func submitReport() async {
        guard let category = selectedCategory else { return }
        isSubmitting = true
        errorMessage = nil
        let result = await service.submitReport(
            targetUid: targetUid,
            contentId: contentId,
            contentType: contentType,
            category: category,
            details: details.isEmpty ? nil : details
        )
        isSubmitting = false
        if result != nil {
            submitted = true
        } else {
            errorMessage = service.submissionError ?? "Something went wrong. Please try again."
        }
    }
}

// MARK: - 7. WellnessPauseSheet

struct WellnessPauseSheet: View {
    let context: WellnessInterventionContext
    var onContinue: () -> Void
    var onPause: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text(context.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(context.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(pauseActionLabel) {
                    onPause()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)

                Button("Continue anyway") {
                    onContinue()
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .presentationDetents([.height(340)])
        .accessibilityElement(children: .contain)
    }

    private var pauseActionLabel: String {
        switch context.intervention {
        case .selahPause:            return "Take a Selah"
        case .reflectionPrompt:      return "Reflect a moment"
        case .postConfirmation:      return "Hold my post"
        case .conflictWarning:       return "Skip this reply"
        case .replyReflection:       return "Wait before replying"
        case .muteSuggestion:        return "Mute this thread"
        case .disableNotifications:  return "Quiet notifications"
        case .switchToReflectionMode:return "Open prayer mode"
        }
    }
}

// MARK: - 8. VerifiedIdentityBadge

struct VerifiedIdentityBadge: View {
    let trustLevel: IdentityTrustLevel
    var compact: Bool = false
    @State private var showTrustDetails = false

    var body: some View {
        if trustLevel.showBadge {
            Button { showTrustDetails = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: badgeIcon)
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(badgeColor)
                    if !compact {
                        Text(trustLevel.badgeLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(badgeColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(trustLevel.badgeLabel) account")
            .sheet(isPresented: $showTrustDetails) {
                TrustDetailsSheet(trustLevel: trustLevel)
                    .presentationDetents([.height(300)])
            }
        }
    }

    private var badgeIcon: String {
        switch trustLevel {
        case .churchVerified:       return "building.columns.fill"
        case .professionalVerified: return "rosette"
        case .creatorVerified:      return "star.fill"
        case .communityVerified:    return "person.2.fill"
        default:                    return "checkmark.seal.fill"
        }
    }

    private var badgeColor: Color {
        switch trustLevel {
        case .churchVerified:       return .blue
        case .professionalVerified: return .purple
        case .creatorVerified:      return .orange
        case .communityVerified:    return .green
        default:                    return .blue
        }
    }
}

// MARK: - 9. TrustDetailsSheet

struct TrustDetailsSheet: View {
    let trustLevel: IdentityTrustLevel
    var unverifiedClaims: [String] = []
    var isSuspectedImpersonation: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Account verification")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .accessibilityLabel("Close")
            }

            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(trustLevel.badgeLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(trustLevelDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            if !unverifiedClaims.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Unverified claims", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(unverifiedClaims, id: \.self) { claim in
                        Text("\"\(claim)\" — Unverified claim")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isSuspectedImpersonation {
                Label("This account may be impersonating someone else.", systemImage: "person.badge.minus")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
        }
        .padding(24)
    }

    private var trustLevelDescription: String {
        switch trustLevel {
        case .emailVerified:        return "Email address confirmed"
        case .phoneVerified:        return "Phone number confirmed"
        case .humanChallengePassed: return "Passed human verification challenge"
        case .communityVerified:    return "Verified by Amen community"
        case .churchVerified:       return "Church domain and location verified"
        case .creatorVerified:      return "Creator identity confirmed"
        case .professionalVerified: return "Professional credentials on file"
        default:                    return "Account active"
        }
    }
}

// MARK: - 10. LimitedDistributionNotice

struct LimitedDistributionNotice: View {
    let reason: String
    var onLearnMore: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Limited distribution")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let learn = onLearnMore {
                Button("Learn more", action: learn)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Limited distribution: \(reason)")
    }
}

// MARK: - 11. AppealDecisionView

struct AppealDecisionView: View {
    let strikeId: String
    var onSubmitted: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var isSubmitting = false
    @State private var appealId: String?
    @State private var error: String?

    private let service = AmenReportAbuseService.shared

    var body: some View {
        NavigationStack {
            Group {
                if let id = appealId {
                    appealSubmittedView(id: id)
                } else {
                    appealFormView
                }
            }
            .navigationTitle("Appeal this decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var appealFormView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tell us why you think this decision was wrong.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $reason)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                if let err = error {
                    Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }

                Button {
                    Task { await submitAppeal() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Submit appeal")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func appealSubmittedView(id: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Appeal submitted")
                .font(.title3.weight(.semibold))
            Text("We'll review your appeal and let you know the outcome.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func submitAppeal() async {
        isSubmitting = true
        error = nil
        if let id = await service.submitAppeal(
            strikeId: strikeId,
            reason: reason.trimmingCharacters(in: .whitespaces)
        ) {
            appealId = id
            onSubmitted?(id)
        } else {
            error = "Could not submit appeal. Please try again."
        }
        isSubmitting = false
    }
}

// MARK: - Previews

#if DEBUG
struct TrustSafetyComponents_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SafetyPreflightBanner(state: .checking)
                .padding()
                .previewDisplayName("Checking")

            SafetyPreflightBanner(state: .blocked(reason: "This content violates Amen safety rules."))
                .padding()
                .previewDisplayName("Blocked")

            ProvenanceBadge(status: .aiGenerated)
                .padding()
                .previewDisplayName("AI Generated Badge")

            AIContentLabel(labelType: .aiGenerated)
                .padding()
                .previewDisplayName("AI Label")

            VerifiedIdentityBadge(trustLevel: .churchVerified)
                .padding()
                .previewDisplayName("Church Verified Badge")

            LimitedDistributionNotice(reason: "Source uncertain — sharing is limited.")
                .padding()
                .previewDisplayName("Limited Distribution")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
