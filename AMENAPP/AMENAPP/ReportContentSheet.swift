// ReportContentSheet.swift
// AMENAPP
//
// Phase 3 — System 35 Trust Spine.
// User-facing report flow. Calls `TrustSpineService.reportContent` which writes
// the /reports + /moderation_queue documents via Cloud Function. The client
// never writes those docs directly.
//
// Liquid Glass treatment:
//   - Glass header (.ultraThinMaterial), solid body
//   - Reduce Transparency falls back to a solid header
//   - No glass-on-glass stacking
//   - Calm, single-screen flow

import SwiftUI

struct ReportContentSheet: View {

    // MARK: Inputs

    let targetType: TrustSpineService.ReportTargetType
    let targetId: String
    let onSubmitted: (TrustSpineService.ReportResult) -> Void
    let onDismiss: () -> Void

    // MARK: Environment

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State

    @State private var selectedReason: TrustSpineService.ReportReason? = nil
    @State private var detailsText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    // MARK: Reasons

    private let reasons: [(reason: TrustSpineService.ReportReason, title: String, subtitle: String, icon: String)] = [
        (.minorSafety, "Minor safety", "Content endangering a minor", "shield.lefthalf.filled"),
        (.selfHarm, "Self-harm or suicide", "Content promoting self-harm", "heart.text.square"),
        (.violence, "Violence", "Threats or graphic violence", "exclamationmark.octagon"),
        (.harassment, "Harassment", "Targeted harassment or bullying", "person.crop.circle.badge.exclamationmark"),
        (.hateSpeech, "Hate speech", "Attacks on a protected group", "speaker.slash"),
        (.sexualContent, "Sexual content", "Explicit or unwanted sexual content", "eye.slash"),
        (.scam, "Scam or fraud", "Deceptive financial behavior", "creditcard.trianglebadge.exclamationmark"),
        (.spam, "Spam", "Repetitive or unsolicited content", "tray.full"),
        (.misinformation, "Misinformation", "Factually inaccurate claims", "questionmark.bubble"),
        (.syntheticMedia, "Synthetic media concern", "Manipulated or deepfake media", "wand.and.rays"),
        (.aiUndisclosed, "Undisclosed AI", "AI use not labeled by creator", "sparkles.tv"),
        (.intellectualProperty, "Intellectual property", "Copyright or trademark concern", "doc.badge.gearshape"),
        (.other, "Other", "Something else not listed", "ellipsis.circle"),
    ]

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    reasonList
                    detailsField
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    submitButton
                    disclaimer
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Report content")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Reports go to Amen's safety team for review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Close report sheet")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
    }

    private var headerBackground: some View {
        Group {
            if reduceTransparency {
                Color(.secondarySystemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    // MARK: Sections

    private var intro: some View {
        Text("Choose the option that best describes the problem. You can add details below if it helps the reviewer.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var reasonList: some View {
        VStack(spacing: 8) {
            ForEach(reasons, id: \.reason.rawValue) { row in
                Button {
                    if !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedReason = row.reason
                        }
                    } else {
                        selectedReason = row.reason
                    }
                } label: {
                    reasonRow(row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reasonRow(
        _ row: (reason: TrustSpineService.ReportReason, title: String, subtitle: String, icon: String)
    ) -> some View {
        let isSelected = selectedReason == row.reason
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.systemScaled(18))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title). \(row.subtitle).")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detailsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Details (optional)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $detailsText)
                .frame(minHeight: 80, maxHeight: 140)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .accessibilityLabel("Optional details")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
                Text(isSubmitting ? "Submitting…" : "Submit report")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(canSubmit ? Color.accentColor : Color(.tertiarySystemFill))
            )
            .foregroundStyle(canSubmit ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .accessibilityHint("Submits this report to Amen's safety team")
    }

    private var disclaimer: some View {
        Text("Reports are recorded server-side. Amen's safety team reviews each report. False reporting may affect your account standing.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var canSubmit: Bool {
        selectedReason != nil && !isSubmitting
    }

    // MARK: Submit

    private func submit() {
        guard let reason = selectedReason else { return }
        isSubmitting = true
        errorMessage = nil
        let details = detailsText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let result = try await TrustSpineService.shared.reportContent(
                    targetType: targetType,
                    targetId: targetId,
                    reason: reason,
                    details: details.isEmpty ? nil : details
                )
                await MainActor.run {
                    isSubmitting = false
                    TrustSpineAnalytics.track(.reportSubmitted, params: [
                        "target_type": targetType.rawValue,
                        "reason": reason.rawValue,
                    ])
                    onSubmitted(result)
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Could not submit report. Please try again."
                }
            }
        }
    }
}

// MARK: - Sheet Modifier

extension View {
    /// Presents `ReportContentSheet` for a given target. The caller controls
    /// presentation via the binding. `onSubmitted` fires with the server result;
    /// the caller is responsible for dismissing the sheet if desired.
    func reportContentSheet(
        isPresented: Binding<Bool>,
        targetType: TrustSpineService.ReportTargetType,
        targetId: String,
        onSubmitted: @escaping (TrustSpineService.ReportResult) -> Void = { _ in }
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ReportContentSheet(
                targetType: targetType,
                targetId: targetId,
                onSubmitted: { result in
                    onSubmitted(result)
                    isPresented.wrappedValue = false
                },
                onDismiss: { isPresented.wrappedValue = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
    }
}

#if DEBUG
#Preview("Report — Post") {
    ReportContentSheet(
        targetType: .post,
        targetId: "post_demo_001",
        onSubmitted: { _ in },
        onDismiss: {}
    )
}
#endif
