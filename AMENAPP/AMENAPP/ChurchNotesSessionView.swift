// ChurchNotesSessionView.swift
// AMENAPP
//
// Low-distraction note-taking view for use during a church service.
// Opened when a journey reaches arrived/notes_active status.
//
// Design principles:
//   - Fast to open, minimal UI chrome
//   - Contextual metadata (church, date, sermon) pre-filled
//   - Quick scripture attach, highlight meaning, prayer/takeaway capture
//   - Works offline (local autosave, syncs on reconnect)
//   - Accessible: Dynamic Type, VoiceOver, large tap targets
//   - No AI calls during service — defer to post-service

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class ChurchNotesSessionViewModel: ObservableObject {

    @Published var session: ChurchNoteSession?
    @Published var noteText: String = ""
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var showHighlightPicker = false
    @Published var showVerseAttach = false
    @Published var pendingHighlightText: String = ""
    @Published var attachedHighlights: [ChurchNoteSession.NoteHighlight] = []

    private let sessionId: String
    private let db = Firestore.firestore()
    private var autosaveTask: Task<Void, Never>?

    init(sessionId: String) {
        self.sessionId = sessionId
        loadSession()
    }

    func loadSession() {
        db.collection("churchNoteSessions").document(sessionId)
            .getDocument { [weak self] doc, _ in
                guard let self else { return }
                let session = try? doc?.data(as: ChurchNoteSession.self)
                Task { @MainActor in
                    if let session {
                        self.session = session
                        self.attachedHighlights = session.highlightsSummary
                    }
                    self.isLoading = false
                }
            }
    }

    // MARK: - Autosave (debounced)

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
            if !Task.isCancelled {
                await save()
            }
        }
    }

    func save() async {
        guard Auth.auth().currentUser?.uid != nil else { return }
        isSaving = true
        let data: [String: Any] = [
            "highlightsSummary": attachedHighlights.map { h in
                ["type": h.type.rawValue, "text": h.text]
            },
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try? await db.collection("churchNoteSessions").document(sessionId).updateData(data)
        // Also persist note text to local storage (offline resilience)
        UserDefaults.standard.set(noteText, forKey: "notes_\(sessionId)")
        isSaving = false
    }

    // MARK: - Highlights

    func addHighlight(type: ChurchNoteHighlightMeaning, text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let highlight = ChurchNoteSession.NoteHighlight(type: type, text: text)
        attachedHighlights.append(highlight)
        pendingHighlightText = ""
        showHighlightPicker = false
        scheduleAutosave()
    }

    func removeHighlight(_ highlight: ChurchNoteSession.NoteHighlight) {
        attachedHighlights.removeAll { $0.type == highlight.type && $0.text == highlight.text }
        scheduleAutosave()
    }

    // MARK: - Complete session

    func completeSession() async {
        await save()
        guard Auth.auth().currentUser?.uid != nil else { return }
        try? await db.collection("churchNoteSessions").document(sessionId).updateData([
            "status": "completed",
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }
}

// MARK: - View

struct ChurchNotesSessionView: View {

    let sessionId: String
    @ObservedObject private var supportDetectionService = SupportDetectionService.shared
    @ObservedObject private var supportActionExecutor = SupportActionExecutor.shared
    @StateObject private var vm: ChurchNotesSessionViewModel
    @EnvironmentObject private var store: ChurchJourneyStore
    @EnvironmentObject private var router: ChurchJourneyRouter
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool
    @State private var supportDraftTask: Task<Void, Never>?
    @State private var supportPayload: SupportInterventionPayload?
    @State private var showSupportSheet = false
    @State private var pendingNavigationAfterSupport = false

    init(sessionId: String) {
        self.sessionId = sessionId
        _vm = StateObject(wrappedValue: ChurchNotesSessionViewModel(sessionId: sessionId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sessionHeader
                Divider()
                noteEditor
                supportSummaryView
                if !vm.attachedHighlights.isEmpty {
                    highlightsList
                }
                Divider()
                quickActionsBar
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $vm.showHighlightPicker) {
                highlightPickerSheet
            }
        }
        .onAppear {
            // Restore any offline text
            if let saved = UserDefaults.standard.string(forKey: "notes_\(sessionId)") {
                vm.noteText = saved
            }
        }
        .sheet(isPresented: $showSupportSheet) {
            if let payload = supportPayload,
               case .sheet(let model) = payload.presentationMode {
                SupportInterventionSheetView(
                    model: model,
                    actions: payload.actions,
                    onAction: handleSupportAction(_:),
                    onDismiss: dismissSupportPrompt,
                    onContinue: finalizeChurchNotesFlow
                )
            }
        }
        .onDisappear {
            supportDraftTask?.cancel()
            supportDraftTask = nil
        }
        .supportDestinationSheet()
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let session = vm.session {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let speaker = session.sermonSpeaker {
                        Text(speaker)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let title = session.sermonTitle {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Church Notes")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Note Editor

    private var noteEditor: some View {
        TextEditor(text: $vm.noteText)
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .focused($editorFocused)
            .frame(minHeight: 200)
            .onChange(of: vm.noteText) { _, _ in
                vm.scheduleAutosave()
                scheduleSupportAnalysis(for: vm.noteText)
            }
            .accessibilityLabel("Church notes editor")
            .overlay(alignment: .topLeading) {
                if vm.noteText.isEmpty {
                    Text("Start typing your notes…")
                        .foregroundStyle(Color(.placeholderText))
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    private var supportSummaryView: some View {
        if let payload = supportPayload {
            switch payload.presentationMode {
            case .inlineCard(let model):
                SupportInlineCardView(
                    model: model,
                    actions: payload.actions,
                    onTap: handleSupportAction(_:),
                    onDismiss: dismissSupportPrompt
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            case .chips(let chips):
                SupportChipsRowView(
                    chips: chips,
                    onTap: handleSupportAction(_:),
                    onDismiss: dismissSupportPrompt
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            case .none, .sheet:
                EmptyView()
            }
        }
    }

    // MARK: - Highlights List

    private var highlightsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.attachedHighlights) { highlight in
                    highlightChip(highlight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func highlightChip(_ highlight: ChurchNoteSession.NoteHighlight) -> some View {
        HStack(spacing: 4) {
            Image(systemName: highlight.type.systemImage)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(highlight.text)
                .font(.caption)
                .lineLimit(1)
            Button {
                vm.removeHighlight(highlight)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .accessibilityLabel("Remove highlight: \(highlight.text)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
        .foregroundStyle(.primary)
        .accessibilityLabel("\(highlight.type.accessibilityLabel): \(highlight.text)")
    }

    // MARK: - Quick Actions Bar

    private var quickActionsBar: some View {
        HStack(spacing: 0) {
            quickActionButton(
                icon: "highlighter",
                label: "Highlight"
            ) {
                vm.pendingHighlightText = vm.noteText.isEmpty ? "" : String(vm.noteText.suffix(80))
                vm.showHighlightPicker = true
            }

            Divider().frame(height: 24)

            quickActionButton(
                icon: "book.closed",
                label: "Verse"
            ) {
                vm.showVerseAttach = true
            }

            Divider().frame(height: 24)

            quickActionButton(
                icon: "hands.sparkles",
                label: "Prayer"
            ) {
                vm.addHighlight(type: .prayer, text: vm.pendingHighlightText.isEmpty ? "Prayer point" : vm.pendingHighlightText)
            }

            Divider().frame(height: 24)

            quickActionButton(
                icon: "checkmark.circle",
                label: "Action"
            ) {
                vm.addHighlight(type: .action, text: vm.pendingHighlightText.isEmpty ? "Action step" : vm.pendingHighlightText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.systemScaled(18))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                Task {
                    pendingNavigationAfterSupport = false
                    await vm.save()
                    if shouldPresentSupportGate {
                        showSupportSheet = true
                    } else {
                        dismiss()
                    }
                }
            } label: {
                Text("Save")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("Save and close notes")
        }

        ToolbarItem(placement: .principal) {
            if vm.isSaving {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Saving…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task {
                    pendingNavigationAfterSupport = true
                    await vm.completeSession()
                    if shouldPresentSupportGate {
                        showSupportSheet = true
                    } else {
                        finalizeChurchNotesFlow()
                    }
                }
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Complete notes and go to reflection")
        }
    }

    private func scheduleSupportAnalysis(for text: String) {
        supportDraftTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            supportPayload = nil
            return
        }

        supportDraftTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }

            let payload = await supportDetectionService.analyzeSupport(
                surface: .churchNote,
                text: trimmed,
                sourceId: sessionId,
                metadata: [
                    "highlightCount": "\(vm.attachedHighlights.count)"
                ]
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                supportPayload = payload
                if let payload {
                    supportDetectionService.record(payload: payload, outcome: .shown)
                }
            }
        }
    }

    private var shouldPresentSupportGate: Bool {
        guard let payload = supportPayload,
              case .sheet = payload.presentationMode else {
            return false
        }
        return true
    }

    private func handleSupportAction(_ action: SupportAction) {
        guard let payload = supportPayload else { return }
        supportActionExecutor.execute(action, from: .churchNote)
        supportDetectionService.record(payload: payload, outcome: .engaged)
        showSupportSheet = false
    }

    private func dismissSupportPrompt() {
        if let payload = supportPayload {
            supportDetectionService.record(payload: payload, outcome: .dismissed)
        }
        showSupportSheet = false
    }

    private func finalizeChurchNotesFlow() {
        showSupportSheet = false
        if pendingNavigationAfterSupport, let journeyId = store.activeJourney?.id {
            router.navigate(to: .reflection(journeyID: journeyId))
        }
        dismiss()
    }

    // MARK: - Highlight Picker Sheet

    private var highlightPickerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Text to highlight", text: $vm.pendingHighlightText, axis: .vertical)
                    .font(.body)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .accessibilityLabel("Text to highlight")

                Text("Choose meaning")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                ForEach(ChurchNoteHighlightMeaning.allCases) { meaning in
                    Button {
                        vm.addHighlight(type: meaning, text: vm.pendingHighlightText)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: meaning.systemImage)
                                .foregroundStyle(.primary)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(meaning.label)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(meaning.accessibilityLabel)
                    Divider().padding(.leading, 56)
                }

                Spacer()
            }
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { vm.showHighlightPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
