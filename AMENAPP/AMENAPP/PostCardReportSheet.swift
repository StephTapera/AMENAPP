import SwiftUI

// MARK: - Report Post Sheet

struct ReportPostSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post
    let postAuthor: String
    let category: PostCard.PostCardCategory

    @State private var selectedReason: ReportReason?
    @State private var additionalDetails = ""
    @State private var showSuccessAlert = false
    @FocusState private var isTextFieldFocused: Bool

    enum ReportReason: String, CaseIterable, Identifiable {
        case spam = "Spam or misleading"
        case harassment = "Harassment or bullying"
        case hateSpeech = "Hate speech or violence"
        case inappropriateContent = "Inappropriate content"
        case falseInformation = "False information"
        case offTopic = "Off-topic or irrelevant"
        case copyright = "Copyright violation"
        case other = "Other"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .spam: return "envelope.badge.fill"
            case .harassment: return "exclamationmark.bubble.fill"
            case .hateSpeech: return "hand.raised.fill"
            case .inappropriateContent: return "eye.slash.fill"
            case .falseInformation: return "checkmark.seal.fill"
            case .offTopic: return "arrow.triangle.branch"
            case .copyright: return "c.circle.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .spam:
                return "Unwanted commercial content or repetitive posts"
            case .harassment:
                return "Targeted harassment, threats, or bullying"
            case .hateSpeech:
                return "Content promoting violence or hatred"
            case .inappropriateContent:
                return "Sexually explicit or disturbing content"
            case .falseInformation:
                return "Deliberately misleading or false claims"
            case .offTopic:
                return "Content that doesn't fit this category"
            case .copyright:
                return "Unauthorized use of copyrighted material"
            case .other:
                return "Something else that violates community guidelines"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report Post")
                            .font(AMENFont.bold(28))

                        Text("Help us keep AMEN safe. Why are you reporting this post?")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Report Reasons
                    VStack(spacing: 12) {
                        ForEach(ReportReason.allCases) { reason in
                            ReportReasonCard(
                                reason: reason,
                                isSelected: selectedReason == reason
                            ) {
                                HapticManager.impact(style: .light)
                                selectedReason = reason
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Additional Details (optional)
                    if selectedReason != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Additional Details (Optional)")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.primary)

                            ZStack(alignment: .topLeading) {
                                if additionalDetails.isEmpty {
                                    Text("Provide any additional context that might help us review this report...")
                                        .font(AMENFont.regular(15))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                }

                                TextEditor(text: $additionalDetails)
                                    .font(AMENFont.regular(15))
                                    .frame(minHeight: 100)
                                    .focused($isTextFieldFocused)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )

                            Text("\(additionalDetails.count)/500 characters")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(additionalDetails.count > 500 ? .red : .secondary)
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: 0.2)))
                    }

                    // Privacy Notice
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.checkered")
                                .font(.systemScaled(14))
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)

                            Text("Your report is confidential")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.primary)
                        }

                        Text("We'll review this report and take appropriate action. The person who posted this won't know you reported it.")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.08))
                    )
                    .padding(.horizontal, 16)

                    Spacer(minLength: 100)
                }
                .padding(.vertical, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Submit Button
                Button {
                    submitReport()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(18))
                            .accessibilityHidden(true)
                        Text("Submit Report")
                            .font(AMENFont.bold(16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedReason != nil ? Color.red : Color.red.opacity(0.3))
                    )
                }
                .disabled(selectedReason == nil)
                .accessibilityLabel("Submit Report")
                .accessibilityHint(selectedReason == nil ? "Select a reason before submitting" : "Submit your report")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
            }
        }
        .alert("Report Submitted", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for helping keep AMEN safe. We'll review this report and take appropriate action.")
        }
    }

    private func submitReport() {
        guard let reason = selectedReason else { return }

        Task {
            do {
                try await ModerationService.shared.reportPost(
                    postId: post.firestoreId,
                    postAuthorId: post.authorId,
                    reason: convertToModerationReason(reason),
                    additionalDetails: additionalDetails.isEmpty ? nil : additionalDetails
                )

                dlog("✅ Report submitted successfully")

                await MainActor.run {
                    showSuccessAlert = true
                }

            } catch {
                dlog("❌ Failed to submit report: \(error)")

                await MainActor.run {
                    // Show error to user
                    dismiss()
                }
            }
        }
    }

    private func convertToModerationReason(_ reason: ReportReason) -> ModerationReportReason {
        switch reason {
        case .spam: return .spam
        case .harassment: return .harassment
        case .hateSpeech: return .hateSpeech
        case .inappropriateContent: return .inappropriateContent
        case .falseInformation: return .falseInformation
        case .offTopic: return .offTopic
        case .copyright: return .copyright
        case .other: return .other
        }
    }
}

// MARK: - Report Reason Card

struct ReportReasonCard: View {
    let reason: ReportPostSheet.ReportReason
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? AmenTheme.Colors.statusError.opacity(0.16) : AmenTheme.Colors.surfaceElevated)
                        .frame(width: 48, height: 48)

                    Image(systemName: reason.icon)
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(isSelected ? AmenTheme.Colors.statusError : AmenTheme.Colors.iconSecondary)
                }
                .accessibilityHidden(true)

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason.rawValue)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)

                    Text(reason.description)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineSpacing(2)
                }

                Spacer()

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.systemScaled(24))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.statusError : AmenTheme.Colors.textPlaceholder)
                    .symbolEffect(.bounce, value: isSelected)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AmenTheme.Colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? AmenTheme.Colors.statusError.opacity(0.3) : AmenTheme.Colors.borderSoft, lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? AmenTheme.Colors.statusError.opacity(0.12) : AmenTheme.Colors.shadowCard.opacity(0.55), radius: isSelected ? 12 : 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reason.rawValue), \(reason.description)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .scaleEffect(isSelected ? 1.0 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
