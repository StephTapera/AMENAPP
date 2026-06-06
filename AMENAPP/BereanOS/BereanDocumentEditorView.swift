import SwiftUI
import FirebaseFunctions

// MARK: - BereanDocumentEditorView

struct BereanDocumentEditorView: View {
    let document: BereanLivingDocument
    let projectId: String

    @StateObject private var service = BereanLivingDocumentService.shared
    @State private var documentBody: String
    @State private var isDirty = false
    @State private var isSaving = false
    @State private var showVersionHistory = false
    @State private var showAIRefine = false
    @State private var saveError: Error?
    @State private var showSaveError = false

    private let autoSaveTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(document: BereanLivingDocument, projectId: String) {
        self.document = document
        self.projectId = projectId
        _documentBody = State(initialValue: document.body)
    }

    var body: some View {
        TextEditor(text: $documentBody)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: documentBody) { _ in isDirty = true }
            .onReceive(autoSaveTimer) { _ in
                guard isDirty else { return }
                Task { await performAutoSave() }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showVersionHistory) {
                VersionHistorySheet(
                    document: document,
                    projectId: projectId,
                    currentBody: $documentBody
                )
            }
            .sheet(isPresented: $showAIRefine) {
                AIRefineSheet(
                    document: document,
                    currentBody: $documentBody
                )
            }
            .alert("Save Error", isPresented: $showSaveError, presenting: saveError) { _ in
                Button("OK", role: .cancel) {}
            } message: { err in
                Text(err.localizedDescription)
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 6) {
                Text(document.documentType.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())

                if document.isPublished {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Published")
                }

                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                showVersionHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Version History")

            PublishToggleButton(
                document: document,
                projectId: projectId
            )

            Button {
                showAIRefine = true
            } label: {
                Label("AI Refine", systemImage: "wand.and.sparkles")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("AI Refine")
        }
    }

    // MARK: - Auto-save

    private func performAutoSave() async {
        guard isDirty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.updateDocument(
                id: document.id,
                body: documentBody,
                projectId: projectId,
                changeNotes: "Auto-saved"
            )
            isDirty = false
        } catch {
            saveError = error
            showSaveError = true
        }
    }
}

// MARK: - PublishToggleButton

private struct PublishToggleButton: View {
    let document: BereanLivingDocument
    let projectId: String
    @StateObject private var service = BereanLivingDocumentService.shared
    @State private var isToggling = false

    var isPublished: Bool {
        service.documents.first(where: { $0.id == document.id })?.isPublished
            ?? document.isPublished
    }

    var body: some View {
        Button {
            Task {
                guard !isToggling else { return }
                isToggling = true
                defer { isToggling = false }
                try? await service.togglePublish(docId: document.id, projectId: projectId)
            }
        } label: {
            Label(
                isPublished ? "Unpublish" : "Publish",
                systemImage: isPublished ? "eye.slash" : "eye"
            )
            .labelStyle(.iconOnly)
        }
        .disabled(isToggling)
        .accessibilityLabel(isPublished ? "Unpublish document" : "Publish document")
    }
}

// MARK: - VersionHistorySheet

private struct VersionHistorySheet: View {
    let document: BereanLivingDocument
    let projectId: String
    @Binding var currentBody: String

    @StateObject private var service = BereanLivingDocumentService.shared
    @State private var history: [BereanDocumentVersion] = []
    @State private var isLoading = true
    @State private var selectedVersion: BereanDocumentVersion?
    @State private var showRestoreConfirm = false
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading history...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if history.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Previous versions will appear here after you save.")
                    )
                } else {
                    List(history) { version in
                        Button {
                            selectedVersion = version
                        } label: {
                            VersionHistoryRow(version: version, dateFormatter: dateFormatter)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedVersion) { version in
                VersionPreviewSheet(
                    version: version,
                    onRestore: {
                        selectedVersion = nil
                        showRestoreConfirm = true
                    }
                )
            }
            .confirmationDialog(
                "Restore this version?",
                isPresented: $showRestoreConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) {
                    if let v = selectedVersion {
                        currentBody = v.body
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace your current editor content. It will be saved on next auto-save or when you make changes.")
            }
        }
        .task {
            do {
                history = try await service.fetchVersionHistory(
                    docId: document.id,
                    projectId: projectId
                )
            } catch {
                // Leave history empty on error
            }
            isLoading = false
        }
    }
}

private struct VersionHistoryRow: View {
    let version: BereanDocumentVersion
    let dateFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Version \(version.versionNumber)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(dateFormatter.string(from: version.changedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !version.changeNotes.isEmpty {
                Text(version.changeNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Version \(version.versionNumber), saved \(dateFormatter.string(from: version.changedAt)). \(version.changeNotes)")
    }
}

private struct VersionPreviewSheet: View {
    let version: BereanDocumentVersion
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(version.body)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Version \(version.versionNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore this version") {
                        onRestore()
                    }
                }
            }
        }
    }
}

// MARK: - AIRefineSheet

private struct AIRefineSheet: View {
    let document: BereanLivingDocument
    @Binding var currentBody: String

    @State private var instruction = ""
    @State private var isRefining = false
    @State private var refinedBody: String?
    @State private var changeSummary: String?
    @State private var refineError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Instruction (optional)") {
                    TextField(
                        "e.g. improve clarity, add structure...",
                        text: $instruction,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                if let summary = changeSummary {
                    Section("What changed") {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let refined = refinedBody {
                    Section("Refined Version") {
                        Text(refined)
                            .font(.body)
                            .lineLimit(12)
                    }

                    Section {
                        Button("Apply Refinement") {
                            currentBody = refined
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.accentColor)
                    }
                }

                if let errMsg = refineError {
                    Section {
                        Label(errMsg, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await runRefine() }
                    } label: {
                        HStack {
                            Spacer()
                            if isRefining {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isRefining ? "Refining..." : "Refine with AI")
                            Spacer()
                        }
                    }
                    .disabled(isRefining)
                }
            }
            .navigationTitle("AI Refine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func runRefine() async {
        isRefining = true
        refinedBody = nil
        changeSummary = nil
        refineError = nil

        do {
            let functions = Functions.functions(region: "us-central1")
            let result = try await functions.httpsCallable("bereanRefineDocument").call([
                "body": currentBody,
                "documentType": document.documentType.rawValue,
                "instruction": instruction
            ])
            guard let data = result.data as? [String: Any] else {
                refineError = "Unexpected response format."
                isRefining = false
                return
            }
            refinedBody = data["refinedBody"] as? String ?? currentBody
            changeSummary = data["changeSummary"] as? String
        } catch {
            refineError = error.localizedDescription
        }

        isRefining = false
    }
}
