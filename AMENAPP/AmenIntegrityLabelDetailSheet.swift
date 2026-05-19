// AmenIntegrityLabelDetailSheet.swift
// AMENAPP
// Shows full detail of a content integrity label — what it means, its source, and actions.

import SwiftUI

struct AmenIntegrityLabelDetailSheet: View {
    let label: ContentIntegrityLabel
    let contentId: String
    @Environment(\.dismiss) private var dismiss
    @State private var explanation: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: label.labelType.icon)
                        .font(.title2)
                        .foregroundStyle(labelColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label.labelType.userFacingLabel)
                            .font(.headline)
                        Text("Source: \(label.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let claim = label.explanation {
                Section("Claim") {
                    Text(claim)
                        .font(.body)
                }
            }

            Section("Verified") {
                Text(label.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let explanation {
                Section("Why you're seeing this") {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Report this label") {
                    // Surface AmenSafetyReportService
                    dismiss()
                }
                .foregroundStyle(.orange)
            }
        }
        .navigationTitle("Content Label")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            explanation = await AmenIntegrityLabelService.shared.explanationForContent(contentId)
        }
    }

    private var labelColor: Color {
        switch label.labelType {
        case .aiGenerated, .aiEdited: return .purple
        case .unverifiedClaim, .disputedClaim: return .orange
        case .needsContext, .partiallyTrue: return .blue
        case .sourceUnclear: return .gray
        case .personalOpinion, .theologicalInterp: return .teal
        }
    }
}

// MARK: - Translation Request Sheet

struct TranslationRequestSheet: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @State private var isTranslating = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text("Translate this post?")
                    .font(.title3.bold())
                if let lang = post.detectedLanguage {
                    Text("This post appears to be in \(Locale.current.localizedString(forLanguageCode: lang) ?? lang). Translate it to English?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())

                Button {
                    isTranslating = true
                    // TranslationService is already integrated into PostCard;
                    // dismiss and let the feed/detail handle it via notification
                    NotificationCenter.default.post(
                        name: Notification.Name("AmenRequestTranslation"),
                        object: post.firebaseId ?? post.firestoreId
                    )
                    dismiss()
                } label: {
                    if isTranslating {
                        ProgressView().tint(.white)
                    } else {
                        Text("Translate")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .disabled(isTranslating)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}
