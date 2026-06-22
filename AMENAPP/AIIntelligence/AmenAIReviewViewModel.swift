import Foundation

@MainActor
final class AmenAIReviewViewModel: ObservableObject {
    @Published private(set) var state: AmenAIReviewState = .idle
    @Published private(set) var errorMessage: String?
    @Published var draft: AmenGeneratedDraft?

    func beginExplainer() { state = .explaining }
    func requestConfirmation() { state = .awaitingUserConfirmation }
    func beginValidation() { state = .validating }
    func beginInputModeration() { state = .moderatingInput }
    func beginGeneration() { state = .generating }
    func beginOutputModeration() { state = .moderatingOutput }

    func setDraftReady(_ draft: AmenGeneratedDraft) {
        self.draft = draft
        state = .draftReady
        errorMessage = nil
    }

    func startEditing() { guard state.canPreviewDraft else { return }; state = .editing }
    func startRegeneration() { guard state.canPreviewDraft else { return }; state = .regenerating }
    func rejectDraft() { state = .rejected }
    func approveDraft() { guard state.canApprove else { return }; state = .approved }

    func fail(_ message: String) {
        errorMessage = message
        state = .failed
    }
}
