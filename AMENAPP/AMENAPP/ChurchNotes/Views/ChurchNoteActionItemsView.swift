import SwiftUI

/// Action Items surface — review pending AI suggestions, then track completion of
/// approved items. AI suggestions are NEVER silently inserted: they live in
/// `draftItems` until the user explicitly approves them per-item.
struct ChurchNoteActionItemsView: View {

    let noteId: String
    /// True when the current user has owner or editor role on the note.
    let canEdit: Bool

    @StateObject private var service = ChurchNoteActionItemsService()

    @State private var editedDrafts: [Int: String] = [:]
    @State private var approvingIndices: Set<Int> = []

    var body: some View {
        List {
            if !service.draftItems.isEmpty && !service.draftIsApproved && !service.draftIsRejected {
                draftReviewSection
            }
            approvedSection
            if let err = service.errorMessage {
                Section { errorLabel(err) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Action Items")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            service.startListening(noteId: noteId)
            service.startListeningToLatestDraft(noteId: noteId)
        }
        .onDisappear { service.stopListening() }
    }

    // MARK: - Draft review section

    @ViewBuilder
    private var draftReviewSection: some View {
        if let jobId = service.draftJobId {
            Section {
                draftBanner

                ForEach(Array(service.draftItems.enumerated()), id: \.offset) { index, original in
                    draftRow(index: index, original: original, jobId: jobId)
                }

                if canEdit {
                    draftBatchActions(jobId: jobId)
                }
            } header: {
                Text("Suggested action items")
            } footer: {
                Text("AI-suggested. Review each item carefully before adding it to this note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var draftBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("AI-generated draft — approve before adding.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: AI-generated draft. Approve before adding.")
    }

    @ViewBuilder
    private func draftRow(index: Int, original: String, jobId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let bindingText = Binding<String>(
                get: { editedDrafts[index] ?? original },
                set: { editedDrafts[index] = $0 }
            )

            if canEdit {
                TextEditor(text: bindingText)
                    .frame(minHeight: 48)
                    .accessibilityLabel("Edit suggested action item \(index + 1)")
            } else {
                Text(original)
                    .font(.body)
            }

            HStack(spacing: 12) {
                if approvingIndices.contains(index) {
                    ProgressView()
                } else if canEdit {
                    Button {
                        Task { await approveSingle(index: index, jobId: jobId, original: original) }
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Approve action item \(index + 1)")

                    if editedDrafts[index] != nil {
                        Button("Reset") { editedDrafts[index] = nil }
                            .font(.callout)
                            .accessibilityLabel("Reset edits on action item \(index + 1)")
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func draftBatchActions(jobId: String) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await approveAll(jobId: jobId) }
            } label: {
                Label("Approve all", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(service.isWorking)
            .accessibilityLabel("Approve all suggested action items")

            Button(role: .destructive) {
                Task { await service.rejectDraft(noteId: noteId, jobId: jobId) }
            } label: {
                Label("Reject all", systemImage: "xmark.circle")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .disabled(service.isWorking)
            .accessibilityLabel("Reject all suggested action items")
        }
    }

    // MARK: - Approved section (checkboxes)

    @ViewBuilder
    private var approvedSection: some View {
        Section {
            if service.approvedItems.isEmpty {
                ContentUnavailableView(
                    "No action items yet",
                    systemImage: "checklist",
                    description: Text(canEdit
                        ? "Approve a suggested item above, or items will appear when generated."
                        : "Action items will appear here when an editor approves them.")
                )
                .padding(.vertical, 12)
            } else {
                ForEach(service.approvedItems) { item in
                    approvedRow(item)
                }
            }
        } header: {
            Text("Approved")
        }
    }

    @ViewBuilder
    private func approvedRow(_ item: ChurchNoteActionItem) -> some View {
        HStack(spacing: 12) {
            Button {
                guard canEdit else { return }
                Task { await service.setCompletion(noteId: noteId, itemId: item.id, completed: !item.completed) }
            } label: {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.completed ? Color.green : (canEdit ? Color.accentColor : Color.secondary))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityLabel(item.completed
                ? "Mark \(item.text) as incomplete"
                : "Mark \(item.text) as complete")
            .accessibilityHint(canEdit
                ? "Toggles completion state"
                : "You don't have permission to change completion")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .strikethrough(item.completed, color: .secondary)
                    .foregroundStyle(item.completed ? Color.secondary : Color.primary)
                if item.wasEdited {
                    Text("Edited from suggestion")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .accessibilityLabel("Error: \(text)")
    }

    // MARK: - Actions

    private func approveSingle(index: Int, jobId: String, original: String) async {
        let edited = (editedDrafts[index] ?? original).trimmingCharacters(in: .whitespacesAndNewlines)
        guard edited.count >= 3 else { return }
        approvingIndices.insert(index)
        defer { approvingIndices.remove(index) }

        await service.approveItems(
            noteId: noteId,
            jobId: jobId,
            approvals: [ChurchNoteActionItemApproval(text: edited, originalIndex: index)]
        )
        if service.errorMessage == nil { editedDrafts[index] = nil }
    }

    private func approveAll(jobId: String) async {
        let approvals = service.draftItems.enumerated().map { idx, original in
            let edited = (editedDrafts[idx] ?? original).trimmingCharacters(in: .whitespacesAndNewlines)
            return ChurchNoteActionItemApproval(
                text: edited.isEmpty ? original : edited,
                originalIndex: idx
            )
        }
        await service.approveItems(noteId: noteId, jobId: jobId, approvals: approvals)
        if service.errorMessage == nil { editedDrafts.removeAll() }
    }
}
