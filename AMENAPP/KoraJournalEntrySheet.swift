// KoraJournalEntrySheet.swift
// AMENAPP
//
// Sheet for writing a new Kora journal entry with optional AI reflection.

import SwiftUI
import FirebaseFunctions

struct KoraJournalEntrySheet: View {
    let circleId: String
    @ObservedObject var vm: KoraViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var entryContent: String = ""
    @State private var shareScope: KoraShareScope = .private
    @State private var aiReflection: String? = nil
    @State private var isLoadingReflection: Bool = false
    @State private var isReflectionExpanded: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    private var characterCount: Int { entryContent.count }
    private var canSubmit: Bool {
        !entryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Editor
                        editorSection

                        // Share scope
                        shareScopeSection

                        // AI Reflection button + result
                        aiReflectionSection

                        // Error
                        if let error = errorMessage {
                            Text(error)
                                .font(AMENFont.regular(13))
                                .foregroundColor(Color(hex: "EF4444"))
                                .padding(.horizontal, 4)
                        }

                        // Submit
                        submitButton

                        Spacer(minLength: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Editor

    private var editorSection: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if entryContent.isEmpty {
                    Text("What's on your heart?")
                        .font(AMENFont.regular(16))
                        .foregroundColor(.white.opacity(0.28))
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $entryContent)
                    .font(AMENFont.regular(16))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 200)
                    .padding(10)
                    .tint(Color(hex: "6B48FF"))
            }
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Character count
            Text("\(characterCount)")
                .font(AMENFont.regular(11))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    // MARK: - Share Scope

    private var shareScopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share with")
                .font(AMENFont.semiBold(13))
                .foregroundColor(.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 0) {
                scopeSegment(.private, label: "Just Me", icon: "lock.fill")
                scopeSegment(.circle, label: "My Circle", icon: "person.2.fill")
                scopeSegment(.workspace, label: "Workspace", icon: "building.2.fill")
            }
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }

    private func scopeSegment(_ scope: KoraShareScope, label: String, icon: String) -> some View {
        let isSelected = shareScope == scope
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                shareScope = scope
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(10))
                Text(label)
                    .font(isSelected ? AMENFont.semiBold(12) : AMENFont.regular(12))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                isSelected
                    ? Capsule().fill(Color(hex: "6B48FF").opacity(0.25))
                    : Capsule().fill(Color.clear)
            )
            .padding(3)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - AI Reflection

    private var aiReflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Trigger button
            Button {
                Task { await fetchAIReflection() }
            } label: {
                HStack(spacing: 8) {
                    if isLoadingReflection {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "F59E0B")))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(14))
                            .foregroundColor(Color(hex: "F59E0B"))
                    }
                    Text(isLoadingReflection ? "Getting reflection…" : "Ask AI for Reflection")
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(Color(hex: "F59E0B"))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
                .background(Color(hex: "F59E0B").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "F59E0B").opacity(0.25), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(CoCreationPressStyle())
            .disabled(
                entryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingReflection
            )

            // Reflection card
            if let reflection = aiReflection {
                reflectionCard(reflection)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: aiReflection)
    }

    private func reflectionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    isReflectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(13))
                        .foregroundColor(Color(hex: "F59E0B"))
                    Text("AI Reflection")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(Color(hex: "F59E0B"))
                    Spacer()
                    Image(systemName: isReflectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundColor(Color(hex: "F59E0B").opacity(0.6))
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isReflectionExpanded {
                Text(text)
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Color(hex: "F59E0B").opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "F59E0B").opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { isReflectionExpanded = true }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await submitEntry() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                }
                Text(isSubmitting ? "Saving…" : "Save Entry")
                    .font(AMENFont.semiBold(16))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                canSubmit
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color(hex: "6B48FF"), Color(hex: "C084FC")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(Color.white.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(CoCreationPressStyle())
        .disabled(!canSubmit)
    }

    // MARK: - Actions

    private func fetchAIReflection() async {
        let content = entryContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isLoadingReflection = true

        let systemPrompt = """
        You are a gentle, scripture-grounded spiritual companion. A person has written a personal \
        journal entry. Offer a brief, warm reflection (2-3 sentences) that acknowledges what they \
        shared and gently points them toward scripture or prayer. Be pastoral, not preachy. \
        Do not start with "I" or refer to yourself.
        """
        do {
            let functions = Functions.functions()
            let result = try await functions.httpsCallable("bereanChatProxy").call([
                "systemPrompt": systemPrompt,
                "userMessage": content,
                "maxTokens": 160
            ])
            if let data = result.data as? [String: Any],
               let text = data["text"] as? String {
                withAnimation {
                    aiReflection = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            dlog("KoraJournalEntrySheet: fetchAIReflection error: \(error)")
        }
        isLoadingReflection = false
    }

    private func submitEntry() async {
        let content = entryContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await vm.submitJournalEntry(
                circleId: circleId,
                content: content,
                sharedWith: shareScope
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
