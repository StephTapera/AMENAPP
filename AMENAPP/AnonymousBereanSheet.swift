// AnonymousBereanSheet.swift
// AMENAPP
// Ask Berean a single question not linked to your account.

import SwiftUI
import FirebaseFunctions

@MainActor
struct AnonymousBereanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var response = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private var canSubmit: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    privacyBadge
                    questionField
                    if !response.isEmpty { responseCard }
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .navigationTitle("Ask Anonymously")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Ask") { Task { await submit() } }
                            .fontWeight(.semibold)
                            .disabled(!canSubmit)
                    }
                }
            }
        }
        .onAppear { fieldFocused = true }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var privacyBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text("This question is not linked to your account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.green.opacity(0.08), in: Capsule())
    }

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your question")
                .font(.subheadline.weight(.medium))
            TextField("Ask anything…", text: $question, axis: .vertical)
                .lineLimit(4...10)
                .focused($fieldFocused)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.done)
                .onSubmit { if canSubmit { Task { await submit() } } }
        }
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("Berean's Response")
                    .font(.subheadline.weight(.semibold))
            }
            AmenMarkdownText(response)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Submit

    private func submit() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        response = ""
        defer { isLoading = false }
        do {
            let callable = Functions.functions().httpsCallable("anonymousBereanQuery")
            let result = try await callable.call(["question": trimmed])
            guard let data = result.data as? [String: Any],
                  let answer = data["answer"] as? String else {
                throw NSError(domain: "com.amen.anon", code: -1)
            }
            withAnimation(.easeIn(duration: 0.25)) { response = answer }
        } catch {
            errorMessage = "Couldn't reach Berean. Please try again."
            dlog("❌ Anonymous Berean query: \(error)")
        }
    }
}
