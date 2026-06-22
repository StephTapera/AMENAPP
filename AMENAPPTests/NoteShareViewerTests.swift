import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Note Share Viewer")
@MainActor
struct NoteShareViewerTests {
    @Test("Viewer payload parser preserves backend access model")
    func viewerPayloadParserPreservesAccessModel() throws {
        let payload = try NoteShareService.shared.parseViewerPayload([
            "shareId": "share-123",
            "noteId": "note-456",
            "status": "active",
            "title": "Romans Notes",
            "summary": "Grace leads the thread.",
            "churchName": "AMEN Church",
            "scriptureRefs": ["Romans 8:1"],
            "viewerCanOpenSourceNote": false,
            "viewerCanSeeFullSnapshot": false,
            "route": [
                "appPath": "amen://note-share/share-123",
                "webFallbackPath": "https://amenapp.com/note-share/share-123"
            ],
            "renderBlocks": [[
                "id": "block-1",
                "text": "There is therefore now no condemnation.",
                "semanticType": "scripture",
                "kind": "quote",
                "scriptureReference": "Romans 8:1"
            ]]
        ])

        #expect(payload.id == "share-123")
        #expect(payload.noteId == "note-456")
        #expect(payload.status == "active")
        #expect(payload.viewerCanOpenSourceNote == false)
        #expect(payload.viewerCanSeeFullSnapshot == false)
        #expect(payload.snapshot.blocks.first?.scriptureReference == "Romans 8:1")
        #expect(payload.summary == "Grace leads the thread.")
    }

    @Test("Revoked share leaves viewer unavailable instead of exposing stale payload")
    func revokedShareLeavesViewerUnavailable() async {
        let service = MockNoteShareService(viewerResult: .failure(NoteShareServiceError.invalidResponse))
        let viewModel = NoteShareViewerViewModel(
            route: NoteShareRoute(shareId: "revoked-share", linkToken: "old-token"),
            service: service
        )

        viewModel.load()
        await waitFor { viewModel.errorMessage != nil }

        #expect(viewModel.payload == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == NoteShareServiceError.invalidResponse.localizedDescription)
    }

    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class MockNoteShareService: NoteShareServing {
    private let viewerResult: Result<NoteShareViewerPayload, Error>

    init(viewerResult: Result<NoteShareViewerPayload, Error>) {
        self.viewerResult = viewerResult
    }

    func createShare(
        noteId: String,
        selectedBlockIds: [String],
        accessPolicy: NoteShareAccessPolicy
    ) async throws -> NoteShareCreateResult {
        NoteShareCreateResult(
            shareId: "share-123",
            linkToken: nil,
            appPath: "amen://note-share/share-123",
            webFallbackPath: "https://amenapp.com/note-share/share-123",
            suggestedActions: []
        )
    }

    func viewerPayload(shareId: String, linkToken: String?) async throws -> NoteShareViewerPayload {
        try viewerResult.get()
    }

    func toggleAmen(shareId: String, linkToken: String?) async throws -> Bool {
        false
    }

    func addReflection(shareId: String, body: String, linkToken: String?) async throws {}

    func revoke(shareId: String) async throws {}
}
#endif
