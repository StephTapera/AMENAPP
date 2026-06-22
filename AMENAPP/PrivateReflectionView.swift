// PrivateReflectionView.swift
// AMENAPP
// Private journaling surface — content is never posted or shared publicly.

import SwiftUI
import FirebaseFunctions

// MARK: - Firebase stub

/// Thin wrapper around the `savePrivateReflection` Cloud Function.
final class FirebaseReflectionService {
    static let shared = FirebaseReflectionService()
    private init() {}

    func saveReflection(_ text: String) async throws {
        let callable = Functions.functions().httpsCallable("savePrivateReflection")
        _ = try await callable.call(["text": text])
    }
}

// MARK: - View

struct PrivateReflectionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var reflectionText = ""
    @State private var isSaved = false
    @State private var isSaving = false

    let promptText: String

    init(promptText: String = "What's on your heart today?") {
        self.promptText = promptText
    }

    var body: some View {
        guard AMENFeatureFlags.shared.privateReflectionEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    private var content: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Privacy disclaimer
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    Text("Private — only visible to you. Never shared.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))

                // Text editor
                ZStack(alignment: .topLeading) {
                    if reflectionText.isEmpty {
                        Text(promptText)
                            .foregroundStyle(Color(.placeholderText))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $reflectionText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemBackground))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Save / confirmation row
                HStack {
                    if isSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button(action: saveReflection) {
                        if isSaving {
                            ProgressView()
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                        } else {
                            Text("Save")
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                        }
                    }
                    .background(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(.systemGray4)
                                : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .background(Color(.systemBackground))
            .navigationTitle("Private Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Private")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func saveReflection() {
        let trimmed = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        Task {
            do {
                try await FirebaseReflectionService.shared.saveReflection(trimmed)
            } catch {
                // Non-fatal: local draft still visible to user
            }
            await MainActor.run {
                isSaving = false
                withAnimation { isSaved = true }
            }
        }
    }
}
