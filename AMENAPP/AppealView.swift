// AppealView.swift — AMEN App
// Sheet for appealing a safety moderation decision.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct AppealView: View {
    let contentId: String
    let originalDecision: String
    let aiReasoning: String
    let onSubmit: () -> Void

    @State private var appealText = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var submitError: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var appealTextTrimmed: String { appealText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !appealTextTrimmed.isEmpty && !isSubmitting }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if didSubmit {
                successView
            } else {
                formView
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(red: 0.25, green: 0.88, blue: 0.56).opacity(0.12))
                    .frame(width: 90, height: 90)
                Circle()
                    .strokeBorder(Color(red: 0.25, green: 0.88, blue: 0.56).opacity(0.25), lineWidth: 1.5)
                    .frame(width: 90, height: 90)
                Image(systemName: "checkmark.circle.fill")
                    .font(.systemScaled(40))
                    .foregroundColor(Color(red: 0.25, green: 0.88, blue: 0.56))
            }
            .transition(.scale.combined(with: .opacity))

            VStack(spacing: 8) {
                Text("Appeal Submitted")
                    .font(.systemScaled(22, weight: .bold))
                    .foregroundStyle(.primary)

                Text("We'll review this within 24 hours.\nYou'll be notified of the outcome.")
                    .font(.systemScaled(15))
                    .foregroundStyle(.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            Button {
                onSubmit()
                dismiss()
            } label: {
                Text("Done")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Form View

    private var formView: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Heading
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tell us more")
                            .font(.systemScaled(22, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Help us understand the context of your content so we can review your appeal fairly.")
                            .font(.systemScaled(14))
                            .foregroundStyle(.primary.opacity(0.55))
                            .lineSpacing(3)
                    }

                    // Original AI reasoning card
                    originalDecisionCard

                    // Appeal text editor
                    appealEditor

                    // Error message
                    if let error = submitError {
                        Text(error)
                            .font(.systemScaled(13))
                            .foregroundColor(Color(red: 0.96, green: 0.38, blue: 0.38))
                            .padding(.horizontal, 4)
                    }

                    // Submit button
                    submitButton

                    // Decision label
                    HStack {
                        Spacer()
                        Text("Decision: \(originalDecision.capitalized)")
                            .font(.systemScaled(12))
                            .foregroundStyle(.primary.opacity(0.25))
                        Spacer()
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Appeal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary.opacity(0.7))
                            .font(.systemScaled(15, weight: .medium))
                    }
                }
            }
        }
    }

    // MARK: - Original Decision Card

    private var originalDecisionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                Text("Original AI Assessment")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
            }

            Text(aiReasoning.isEmpty ? "Flagged by automated safety systems." : aiReasoning)
                .font(.systemScaled(14))
                .foregroundStyle(.primary.opacity(0.7))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Appeal Editor

    private var appealEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Appeal")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.5))

            ZStack(alignment: .topLeading) {
                if appealText.isEmpty {
                    Text("Explain the context of your content — why it was meant in a positive, faith-building way...")
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary.opacity(0.22))
                        .padding(.top, 12)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $appealText)
                    .font(.systemScaled(15))
                    .foregroundStyle(.primary.opacity(0.9))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(
                                appealTextTrimmed.isEmpty
                                    ? Color.white.opacity(0.08)
                                    : Color(red: 0.25, green: 0.88, blue: 0.56).opacity(0.3),
                                lineWidth: 1
                            )
                    )
            )

            Text("\(appealText.count) characters")
                .font(.systemScaled(11))
                .foregroundStyle(.primary.opacity(0.25))
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            Task { await submitAppeal() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.systemScaled(16))
                }
                Text(isSubmitting ? "Submitting..." : "Submit Appeal")
                    .font(.systemScaled(16, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.25, blue: 1.0), Color(red: 0.35, green: 0.15, blue: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.purple.opacity(0.35), radius: 10, x: 0, y: 5)
                    .opacity(canSubmit ? 1 : 0.4)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    // MARK: - Submit Action

    private func submitAppeal() async {
        guard canSubmit else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            submitError = "You must be signed in to appeal."
            return
        }

        isSubmitting = true
        submitError = nil

        lazy var db = Firestore.firestore()
        let docRef = contentId.isEmpty
            ? db.collection("contentSafetyLogs").document()
            : db.collection("contentSafetyLogs").document(contentId)

        do {
            try await docRef.setData([
                "appealText": appealTextTrimmed,
                "appealedAt": FieldValue.serverTimestamp(),
                "appealedByUid": uid,
                "originalDecision": originalDecision,
                "decision": "appealed",
                "contentId": contentId
            ], merge: true)

            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                didSubmit = true
            }
        } catch {
            submitError = "Couldn't submit your appeal. Please try again."
        }

        isSubmitting = false
    }
}
