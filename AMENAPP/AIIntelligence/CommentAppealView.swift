// CommentAppealView.swift
// AMENAPP — Smart Comments Wave 2
//
// Appeal flow for a removed comment. Shown to the comment AUTHOR only.
// Appeals are reviewed by a human — this is stated clearly to set correct expectations.
//
// Usage:
//   .sheet(isPresented: $showAppeal) {
//       CommentAppealView(
//           commentId: comment.id,
//           moderationResultId: result.id
//       ) { appeal in
//           // handle appeal submission
//       }
//   }

import SwiftUI
import Foundation
import FirebaseAuth

struct CommentAppealView: View {

    let commentId: String
    let moderationResultId: String
    let onSubmit: (CommentAppeal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var appealText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showValidationError: Bool = false

    private let maxChars = 500

    var body: some View {
        ZStack {
            sheetBackground

            ScrollView {
                VStack(spacing: 0) {
                    headerBar
                    formCard
                    Spacer(minLength: 40)
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
            .accessibilityLabel("Cancel appeal")

            Spacer()

            Text("Appeal Removal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: submitAppeal) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Submit")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSubmit ? .blue : .secondary)
                }
            }
            .disabled(!canSubmit || isSubmitting)
            .accessibilityLabel("Submit appeal")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 8) {
                Text("Why do you think this should be restored?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                Text("Describe why this comment doesn't violate community standards. Be specific — it helps our review team.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            // Text field
            ZStack(alignment: .topLeading) {
                if appealText.isEmpty {
                    Text("Share your perspective…")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }
                TextEditor(text: Binding(
                    get: { appealText },
                    set: { appealText = String($0.prefix(maxChars)) }
                ))
                .font(.system(size: 15))
                .frame(minHeight: 120, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            // Char count + validation error
            HStack(alignment: .top) {
                if showValidationError {
                    Text("Please describe your appeal before submitting.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 16)
                }
                Spacer()
                Text("\(appealText.count)/\(maxChars)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 16)
            }
            .padding(.bottom, 4)

            Divider()
                .padding(.vertical, 8)

            // Human review notice
            HStack(spacing: 6) {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Appeals are reviewed by a human, typically within 48 hours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

    // MARK: - Helpers

    private var canSubmit: Bool {
        !appealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitAppeal() {
        let trimmed = appealText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showValidationError = true
            return
        }

        isSubmitting = true
        showValidationError = false

        let reporterId = Auth.auth().currentUser?.uid ?? "anonymous"

        let appeal = CommentAppeal(
            id: UUID().uuidString,
            reporterId: reporterId,
            targetId: commentId,
            moderationResultId: moderationResultId,
            appealText: trimmed,
            status: .pending,
            submittedAt: Date().timeIntervalSince1970,
            resolvedAt: nil
        )

        onSubmit(appeal)
        isSubmitting = false
        dismiss()
    }
}
