import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Translation review surface — never auto-applies AI output.
/// 1. User picks target language and source field
/// 2. Backend generates translation with `approvalState: needsReview`
/// 3. User sees source + translated text side-by-side
/// 4. Approve (optionally edited) or reject — only then is `approvedText` set
/// The original note body is never overwritten by this flow.
struct ChurchNoteTranslationReviewView: View {
    let noteId: String
    /// Source text the user is translating (transcript, OCR, or note body).
    let sourceText: String
    /// Tag for what kind of text `sourceText` represents — passed through to the
    /// callable so the server stores correct provenance.
    let sourceField: String

    @StateObject private var model = TranslationReviewModel()
    @State private var targetLanguageCode: String = "es"
    @State private var editingTranslationId: String?
    @State private var editedText: String = ""
    @Environment(\.dismiss) private var dismiss

    private let supportedLanguages: [(code: String, label: String)] = [
        ("es", "Spanish"),
        ("fr", "French"),
        ("pt", "Portuguese (Brazil)"),
        ("sw", "Swahili"),
        ("zh", "Chinese (Simplified)"),
        ("ko", "Korean"),
        ("en", "English"),
    ]

    var body: some View {
        NavigationStack {
            List {
                sourceSection
                generateSection
                reviewSection
                if let err = model.errorMessage {
                    Section { errorLabel(err) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { model.startListening(noteId: noteId) }
            .onDisappear { model.stopListening() }
        }
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section("Source") {
            Text(sourceText.isEmpty ? "(no source text)" : sourceText)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(8)
                .accessibilityLabel("Source text to translate")
        }
    }

    private var generateSection: some View {
        Section {
            Picker("Translate to", selection: $targetLanguageCode) {
                ForEach(supportedLanguages, id: \.code) { lang in
                    Text(lang.label).tag(lang.code)
                }
            }
            .accessibilityLabel("Choose target language")

            if model.isGenerating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Generating translation…")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await generate() }
                } label: {
                    Label("Generate translation", systemImage: "globe.badge.chevron.backward")
                        .font(.callout.weight(.semibold))
                }
                .disabled(sourceText.isEmpty)
                .accessibilityLabel("Generate AI translation in selected language")
                .accessibilityHint("Translation will be saved as a draft for your review")
            }
        } footer: {
            Text("AI-generated translation. Always review before using it — never replaces the original note.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if !model.translations.isEmpty {
            Section("Drafts") {
                ForEach(model.translations) { translation in
                    translationRow(translation)
                }
            }
        }
    }

    @ViewBuilder
    private func translationRow(_ translation: ChurchNoteTranslationDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(translation.sourceLanguage.uppercased()) → \(translation.targetLanguage.uppercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                statePill(translation.approvalState)
            }

            if editingTranslationId == translation.id {
                TextEditor(text: $editedText)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Edit translated text")
            } else {
                Text(translation.translatedText)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }

            if translation.approvalState == "needsReview" {
                actionRow(for: translation)
            } else if translation.approvalState == "approved", translation.wasEdited == true {
                Label("Edited before approval", systemImage: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actionRow(for translation: ChurchNoteTranslationDraft) -> some View {
        HStack(spacing: 10) {
            if model.workingId == translation.id {
                ProgressView()
                Spacer()
            } else if editingTranslationId == translation.id {
                Button("Save & Approve") {
                    Task { await approve(translation: translation, editedText: editedText) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Save edits and approve translation")

                Button("Cancel") {
                    editingTranslationId = nil
                    editedText = ""
                }
                .accessibilityLabel("Cancel editing translation")
            } else {
                Button {
                    Task { await approve(translation: translation, editedText: nil) }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Approve translation as-is")

                Button {
                    editingTranslationId = translation.id
                    editedText = translation.translatedText
                } label: {
                    Label("Edit first", systemImage: "pencil")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Edit translation before approving")

                Spacer()

                Button(role: .destructive) {
                    Task { await reject(translation: translation) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reject translation")
            }
        }
    }

    private func statePill(_ state: String) -> some View {
        let color: Color = state == "approved" ? .green : (state == "rejected" ? .red : .orange)
        return Text(state.replacingOccurrences(of: "needsReview", with: "Needs review").capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(state)")
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .accessibilityLabel("Error: \(text)")
    }

    // MARK: - Actions

    private func generate() async {
        await model.generate(noteId: noteId, sourceField: sourceField, targetLanguage: targetLanguageCode)
    }

    private func approve(translation: ChurchNoteTranslationDraft, editedText: String?) async {
        await model.approve(noteId: noteId, translationId: translation.id, editedText: editedText)
        if model.errorMessage == nil {
            editingTranslationId = nil
            self.editedText = ""
        }
    }

    private func reject(translation: ChurchNoteTranslationDraft) async {
        await model.reject(noteId: noteId, translationId: translation.id)
    }
}

// MARK: - Model

@MainActor
final class TranslationReviewModel: ObservableObject {

    @Published private(set) var translations: [ChurchNoteTranslationDraft] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var workingId: String?
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    deinit { listener?.remove() }

    func startListening(noteId: String) {
        stopListening()
        listener = db.collection("churchNotes")
            .document(noteId)
            .collection("translations")
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let items: [ChurchNoteTranslationDraft] = snapshot?.documents.compactMap {
                    ChurchNoteTranslationDraft.fromFirestore(id: $0.documentID, data: $0.data())
                } ?? []
                Task { @MainActor [weak self] in self?.translations = items }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func generate(noteId: String, sourceField: String, targetLanguage: String) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            _ = try await functions
                .httpsCallable("translateChurchNoteContent")
                .call([
                    "noteId":         noteId,
                    "sourceField":    sourceField,
                    "targetLanguage": targetLanguage,
                ])
        } catch {
            errorMessage = "Translation failed. Please try again."
        }
    }

    func approve(noteId: String, translationId: String, editedText: String?) async {
        workingId = translationId
        errorMessage = nil
        defer { workingId = nil }

        var payload: [String: Any] = ["noteId": noteId, "translationId": translationId]
        if let editedText, !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["editedText"] = editedText
        }
        do {
            _ = try await functions
                .httpsCallable("approveChurchNoteTranslation")
                .call(payload)
        } catch {
            errorMessage = "Could not approve translation."
        }
    }

    func reject(noteId: String, translationId: String) async {
        workingId = translationId
        errorMessage = nil
        defer { workingId = nil }
        do {
            _ = try await functions
                .httpsCallable("rejectChurchNoteTranslation")
                .call(["noteId": noteId, "translationId": translationId])
        } catch {
            errorMessage = "Could not reject translation."
        }
    }
}

struct ChurchNoteTranslationDraft: Identifiable, Equatable {
    let id: String
    let noteId: String
    let jobId: String?
    let sourceField: String
    let sourceLanguage: String
    let targetLanguage: String
    let translatedText: String
    let approvalState: String
    let wasEdited: Bool?
    let approvedText: String?
    let createdAt: Date?

    static func fromFirestore(id: String, data: [String: Any]) -> ChurchNoteTranslationDraft? {
        guard let noteId          = data["noteId"]         as? String,
              let sourceLanguage  = data["sourceLanguage"] as? String,
              let targetLanguage  = data["targetLanguage"] as? String,
              let translatedText  = data["translatedText"] as? String,
              let approvalState   = data["approvalState"]  as? String else { return nil }
        return ChurchNoteTranslationDraft(
            id: id,
            noteId: noteId,
            jobId: data["jobId"] as? String,
            sourceField: (data["sourceField"] as? String) ?? "transcriptText",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translatedText: translatedText,
            approvalState: approvalState,
            wasEdited: data["wasEdited"] as? Bool,
            approvedText: data["approvedText"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }
}
