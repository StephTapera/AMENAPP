// CommentReportSheet.swift
// AMENAPP — Smart Comments Wave 2
//
// Report flow for a single comment. Sheet with glass background + opaque white form card.
// Anonymous — reporter identity is never surfaced to the creator or other users.
//
// Usage:
//   .sheet(isPresented: $showReport) {
//       SmartCommentReportSheet(commentId: comment.id) { report in
//           // handle report submission
//       }
//   }

import SwiftUI
import Foundation
import FirebaseAuth

struct SmartCommentReportSheet: View {

    let commentId: String
    let onSubmit: (CommentReport) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // User-selected category (required)
    @State private var selectedCategory: ReportableCategory? = nil
    // Optional detail text
    @State private var detailText: String = ""
    // Submission in flight
    @State private var isSubmitting: Bool = false

    // Categories available for user reporting — subset of ModerationCategory
    enum ReportableCategory: String, CaseIterable, Identifiable {
        case harassment      = "harassment"
        case hate            = "hate"
        case threats         = "threats"
        case scamSpam        = "scam"
        case selfHarm        = "self_harm"
        case spiritualAbuse  = "spiritual_abuse"
        case doxxing         = "doxxing"
        case misinformation  = "misinformation"
        case other           = "other" // maps to .spam as the closest available category

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .harassment:     return "Harassment or bullying"
            case .hate:           return "Hate speech or discrimination"
            case .threats:        return "Threats or violent language"
            case .scamSpam:       return "Scam or spam"
            case .selfHarm:       return "Concern for someone's safety"
            case .spiritualAbuse: return "Spiritual abuse or manipulation"
            case .doxxing:        return "Personal information shared without consent"
            case .misinformation: return "Misleading or false information"
            case .other:          return "Something else"
            }
        }

        var moderationCategory: ModerationCategory {
            switch self {
            case .harassment:     return .harassment
            case .hate:           return .hate
            case .threats:        return .threats
            case .scamSpam:       return .scam
            case .selfHarm:       return .selfHarm
            case .spiritualAbuse: return .spiritualAbuse
            case .doxxing:        return .doxxing
            case .misinformation: return .misinformation
            case .other:          return .spam
            }
        }
    }

    private let maxDetailChars = 500

    var body: some View {
        ZStack {
            // Glass sheet background
            sheetBackground

            ScrollView {
                VStack(spacing: 0) {
                    headerBar
                    formCard
                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.primary)
            .accessibilityLabel("Cancel report")

            Spacer()

            Text("Report Comment")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: submitReport) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Submit")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selectedCategory != nil ? .blue : .secondary)
                }
            }
            .disabled(selectedCategory == nil || isSubmitting)
            .accessibilityLabel("Submit report")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Category picker section
            VStack(alignment: .leading, spacing: 4) {
                Text("What's the problem?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                ForEach(ReportableCategory.allCases) { category in
                    categoryRow(category)
                }
            }
            .padding(.top, 16)

            Divider()
                .padding(.vertical, 12)

            // Detail text section
            VStack(alignment: .leading, spacing: 6) {
                Text("Additional details (optional)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                ZStack(alignment: .topLeading) {
                    if detailText.isEmpty {
                        Text("Tell us more…")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                    }
                    TextEditor(text: Binding(
                        get: { detailText },
                        set: { detailText = String($0.prefix(maxDetailChars)) }
                    ))
                    .font(.system(size: 15))
                    .frame(minHeight: 80, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                }
                .padding(.horizontal, 16)

                HStack {
                    Spacer()
                    Text("\(detailText.count)/\(maxDetailChars)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 16)
                }
            }

            Divider()
                .padding(.top, 12)

            // Anonymous disclaimer
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Your report is anonymous")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(_ category: ReportableCategory) -> some View {
        Button(action: { selectedCategory = category }) {
            HStack {
                Text(category.displayName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if selectedCategory == category {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 17))
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 17))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
    }

    // MARK: - Sheet Background

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    // MARK: - Submission

    private func submitReport() {
        guard let category = selectedCategory else { return }
        isSubmitting = true

        let reporterId = Auth.auth().currentUser?.uid ?? "anonymous"
        let detail = detailText.trimmingCharacters(in: .whitespacesAndNewlines)

        let report = CommentReport(
            id: UUID().uuidString,
            reporterId: reporterId,
            targetId: commentId,
            targetType: "comment",
            category: category.moderationCategory,
            detail: detail.isEmpty ? nil : detail,
            submittedAt: Date().timeIntervalSince1970
        )

        onSubmit(report)
        isSubmitting = false
        dismiss()
    }
}
