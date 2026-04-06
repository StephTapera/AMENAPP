// PostVisitReflectionView.swift
// Post-visit reflection composer — minimal, growth-oriented
// AMENAPP

import SwiftUI
import FirebaseFirestore

// MARK: - ReflectionField

enum ReflectionField: Hashable {
    case takeaway
    case scripture
    case prayer
}

// MARK: - PostVisitReflectionViewModel

@MainActor
final class PostVisitReflectionViewModel: ObservableObject {

    @Published var takeawayText: String = ""
    @Published var scriptureText: String = ""
    @Published var prayerText: String = ""
    @Published var isPrivate: Bool = true
    @Published var wantsReturnVisit: Bool = false
    @Published var isSaving: Bool = false
    @Published var saveSucceeded: Bool = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()

    /// Save reflection privately to user's personal Firestore subcollection.
    func savePrivately(churchId: String, visitSessionId: String?, userId: String) async {
        guard !takeawayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please add at least a takeaway before saving."
            return
        }
        isSaving = true
        let draft = ChurchReflectionDraft(
            userId: userId,
            churchId: churchId,
            visitSessionId: visitSessionId,
            takeawayText: takeawayText,
            scriptureText: scriptureText.isEmpty ? nil : scriptureText,
            prayerText: prayerText.isEmpty ? nil : prayerText,
            shareTarget: nil,
            isPrivate: true
        )
        do {
            let data = try Firestore.Encoder().encode(draft)
            try await db
                .collection("users").document(userId)
                .collection("churchReflections").document(draft.id)
                .setData(data)
            dlog("[PostVisitReflection] Saved reflection \(draft.id) privately for user \(userId)")
            // Attach to session if present
            if let sessionId = visitSessionId {
                try await db
                    .collection("users").document(userId)
                    .collection("churchVisitSessions").document(sessionId)
                    .updateData(["reflectionId": draft.id, "updatedAt": Timestamp(date: Date())])
            }
            isSaving = false
            saveSucceeded = true
        } catch {
            isSaving = false
            errorMessage = "Could not save your reflection. Please try again."
            dlog("[PostVisitReflection] Error saving privately: \(error)")
        }
    }

    /// Save reflection and create an #OpenTable share draft via PostsManager.
    func shareToOpenTable(churchId: String, visitSessionId: String?, userId: String) async {
        guard !takeawayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please add a takeaway before sharing."
            return
        }
        isSaving = true
        var draft = ChurchReflectionDraft(
            userId: userId,
            churchId: churchId,
            visitSessionId: visitSessionId,
            takeawayText: takeawayText,
            scriptureText: scriptureText.isEmpty ? nil : scriptureText,
            prayerText: prayerText.isEmpty ? nil : prayerText,
            shareTarget: "openTable",
            isPrivate: false
        )
        draft.shareTarget = "openTable"

        do {
            let data = try Firestore.Encoder().encode(draft)
            try await db
                .collection("users").document(userId)
                .collection("churchReflections").document(draft.id)
                .setData(data)
            // Placeholder share post — actual posting routed through PostsManager
            dlog("[PostVisitReflection] Reflection \(draft.id) marked for #OpenTable share — PostsManager routing pending")
            isSaving = false
            saveSucceeded = true
        } catch {
            isSaving = false
            errorMessage = "Could not share your reflection. Please try again."
            dlog("[PostVisitReflection] Error sharing to OpenTable: \(error)")
        }
    }
}

// MARK: - PostVisitReflectionView

struct PostVisitReflectionView: View {

    let churchName: String
    let visitSession: ChurchVisitSession?

    @StateObject private var vm = PostVisitReflectionViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: ReflectionField?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                if vm.saveSucceeded {
                    successState
                } else {
                    mainContent
                }
            }
            .navigationBarHidden(true)
        }
        .alert("Error", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            if let msg = vm.errorMessage { Text(msg) }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(churchName)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.secondary)
                        Text("What did you learn today?")
                            .font(AMENFont.bold(22))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 20)

                    // Takeaway
                    reflectionSection(
                        label: "Takeaway",
                        placeholder: "What stayed with you today?",
                        text: $vm.takeawayText,
                        field: .takeaway,
                        isMultiLine: true
                    )

                    // Scripture (optional)
                    reflectionSection(
                        label: "Verse or Scripture",
                        placeholder: "Optional — e.g. John 3:16",
                        text: $vm.scriptureText,
                        field: .scripture,
                        isMultiLine: false
                    )

                    // Prayer (optional)
                    reflectionSection(
                        label: "Prayer",
                        placeholder: "Optional — write a prayer or intention",
                        text: $vm.prayerText,
                        field: .prayer,
                        isMultiLine: true
                    )

                    // Privacy toggle
                    toggleRow(
                        label: "Keep this private",
                        subtitle: "Only you can see this reflection",
                        icon: "lock.fill",
                        isOn: $vm.isPrivate
                    )

                    // Return visit toggle
                    toggleRow(
                        label: "I'd like to return",
                        subtitle: "We'll remind you to plan another visit",
                        icon: "arrow.counterclockwise",
                        isOn: $vm.wantsReturnVisit
                    )

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }

            // Sticky bottom bar
            bottomBar
        }
    }

    // MARK: - Subviews

    private func reflectionSection(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: ReflectionField,
        isMultiLine: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.tertiary)
                        .padding(.top, isMultiLine ? 12 : 0)
                        .padding(.leading, 1)
                }
                if isMultiLine {
                    TextEditor(text: text)
                        .font(AMENFont.regular(14))
                        .focused($focusedField, equals: field)
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                } else {
                    TextField("", text: text)
                        .font(AMENFont.regular(14))
                        .focused($focusedField, equals: field)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                focusedField == field
                                    ? Color.black.opacity(0.3)
                                    : Color.black.opacity(0.08),
                                lineWidth: 0.8
                            )
                    )
            }
        }
    }

    private func toggleRow(
        label: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.black)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                // Save privately
                Button {
                    Task {
                        await vm.savePrivately(
                            churchId: visitSession?.churchId ?? "",
                            visitSessionId: visitSession?.id,
                            userId: visitSession?.userId ?? ""
                        )
                    }
                } label: {
                    HStack {
                        if vm.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save Privately")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(vm.isSaving)

                // Share to #OpenTable
                Button {
                    Task {
                        await vm.shareToOpenTable(
                            churchId: visitSession?.churchId ?? "",
                            visitSessionId: visitSession?.id,
                            userId: visitSession?.userId ?? ""
                        )
                    }
                } label: {
                    Text("Share to #OpenTable")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
                                )
                        }
                }
                .disabled(vm.isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.white)
    }

    // MARK: - Success State

    private var successState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.green)
            }

            Text("Reflection saved")
                .font(AMENFont.bold(22))
                .foregroundStyle(.primary)

            Text("Your thoughts from \(churchName) have been captured.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .font(AMENFont.semiBold(16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    PostVisitReflectionView(
        churchName: "Antioch Church",
        visitSession: nil
    )
}
#endif
