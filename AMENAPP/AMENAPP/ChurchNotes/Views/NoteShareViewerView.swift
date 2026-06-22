import SwiftUI

struct NoteShareRoute: Identifiable, Equatable {
    let shareId: String
    let linkToken: String?

    var id: String { [shareId, linkToken].compactMap { $0 }.joined(separator: ":") }
}

@MainActor
final class NoteShareViewerViewModel: ObservableObject {
    @Published private(set) var payload: NoteShareViewerPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var isAmened = false
    @Published var reflectionText = ""
    @Published var errorMessage: String?

    private let route: NoteShareRoute
    private let service: any NoteShareServing
    private var loadTask: Task<Void, Never>?

    init(route: NoteShareRoute, service: (any NoteShareServing)? = nil) {
        self.route = route
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--note-share-runtime-proof") {
            self.service = service ?? NoteShareRuntimeProofService()
        } else {
            self.service = service ?? NoteShareService.shared
        }
        #else
        self.service = service ?? NoteShareService.shared
        #endif
    }

    func load() {
        guard loadTask == nil else { return }
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await service.viewerPayload(shareId: route.shareId, linkToken: route.linkToken)
                payload = loaded
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            loadTask = nil
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    func toggleAmen() {
        Task {
            do {
                isAmened = try await service.toggleAmen(shareId: route.shareId, linkToken: route.linkToken)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addReflection() {
        let body = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        reflectionText = ""
        Task {
            do {
                try await service.addReflection(shareId: route.shareId, body: body, linkToken: route.linkToken)
            } catch {
                errorMessage = error.localizedDescription
                reflectionText = body
            }
        }
    }
}

#if DEBUG
@MainActor
private struct NoteShareRuntimeProofService: NoteShareServing {
    func createShare(noteId: String, selectedBlockIds: [String], accessPolicy: NoteShareAccessPolicy) async throws -> NoteShareCreateResult {
        NoteShareCreateResult(
            shareId: "runtime-proof-shared",
            linkToken: "runtime-proof-token",
            appPath: "amen://note-share/runtime-proof-shared",
            webFallbackPath: "https://amenapp.com/n/runtime-proof-token",
            suggestedActions: []
        )
    }

    func viewerPayload(shareId: String, linkToken: String?) async throws -> NoteShareViewerPayload {
        if shareId.contains("revoked") {
            throw NoteShareServiceError.invalidResponse
        }

        let blocks = [
            NoteShareSnapshotBlock(
                id: "romans-8",
                text: "There is therefore now no condemnation for those who are in Christ Jesus. The note captures the sermon emphasis on grace, adoption, and walking by the Spirit.",
                semanticType: "scripture",
                blockType: "paragraph",
                scriptureReference: "Romans 8:1"
            ),
            NoteShareSnapshotBlock(
                id: "prayer-point",
                text: "Prayer point: ask for courage to live from belovedness instead of fear this week.",
                semanticType: "prayer",
                blockType: "callout",
                scriptureReference: nil
            )
        ]
        let snapshot = NoteShareViewerSnapshot(
            title: "What I learned from Romans 8",
            sermonTitle: "Sunday Notes",
            sermonSpeaker: "Pastor Elena Reyes",
            churchName: "Grace Chapel",
            scriptureReferences: ["Romans 8:1", "Romans 8:15-17"],
            excerpt: blocks.map(\.text).joined(separator: "\n\n"),
            blocks: blocks
        )
        return NoteShareViewerPayload(
            id: shareId,
            noteId: "runtime-proof-note",
            status: "active",
            appPath: "amen://note-share/\(shareId)",
            webFallbackPath: "https://amenapp.com/n/runtime-proof-token",
            snapshot: snapshot,
            suggestedActions: [
                NoteShareSuggestedAction(id: "reflect", label: "Reflect quietly", systemIcon: "text.bubble", intent: "reflection")
            ],
            summary: "A shared Church Note rendered from a deep link for runtime proof.",
            viewerCanOpenSourceNote: false,
            viewerCanSeeFullSnapshot: true
        )
    }

    func toggleAmen(shareId: String, linkToken: String?) async throws -> Bool { true }
    func addReflection(shareId: String, body: String, linkToken: String?) async throws {}
    func revoke(shareId: String) async throws {}
}
#endif

struct NoteShareViewerView: View {
    @StateObject private var viewModel: NoteShareViewerViewModel
    @Environment(\.dismiss) private var dismiss

    init(route: NoteShareRoute) {
        _viewModel = StateObject(wrappedValue: NoteShareViewerViewModel(route: route))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.payload == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = viewModel.payload, payload.status == "active" {
                    // Safety gate: only render when the server confirms status == "active".
                    // Statuses removed_by_moderation / revoked / expired all fall through
                    // to unavailableState so moderated content is never shown to viewers.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(payload)
                            smartActionRow(payload.suggestedActions)
                            snapshot(payload.snapshot, canSeeFull: payload.viewerCanSeeFullSnapshot)
                            reflectionComposer
                        }
                        .padding(20)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                } else {
                    unavailableState
                }
            }
            .navigationTitle("Shared Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { viewModel.load() }
        .onDisappear { viewModel.cancel() }
        .alert("Note Share", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func header(_ payload: NoteShareViewerPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(payload.snapshot.churchName ?? "Church Notes", systemImage: "note.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(payload.snapshot.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let sermonTitle = payload.snapshot.sermonTitle {
                Text(sermonTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !payload.summary.isEmpty {
                Text(payload.summary)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func smartActionRow(_ actions: [NoteShareSuggestedAction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested next step")
                .font(.headline)
            ForEach(actions) { action in
                Button {
                    // The server-selected intent is intentionally surfaced here without
                    // auto-navigation so the user stays in control of spiritual actions.
                } label: {
                    Label(action.label, systemImage: action.systemIcon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func snapshot(_ snapshot: NoteShareViewerSnapshot, canSeeFull: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !snapshot.scriptureReferences.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scripture")
                        .font(.headline)
                    ForEach(snapshot.scriptureReferences, id: \.self) { reference in
                        Text(reference)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

            if canSeeFull && !snapshot.blocks.isEmpty {
                ForEach(snapshot.blocks) { block in
                    VStack(alignment: .leading, spacing: 6) {
                        if let reference = block.scriptureReference {
                            Text(reference)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(block.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else {
                Text(snapshot.excerpt)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Full note access is limited by the author’s sharing settings.", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reflectionComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reflect")
                .font(.headline)
            TextField("Add a gracious reflection", text: $viewModel.reflectionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
            HStack {
                Button {
                    viewModel.toggleAmen()
                } label: {
                    Label(viewModel.isAmened ? "Amened" : "Amen", systemImage: viewModel.isAmened ? "heart.fill" : "heart")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Post") {
                    viewModel.addReflection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("This shared note is unavailable")
                .font(.headline)
            Text("The author may have changed the sharing settings or revoked the link.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
