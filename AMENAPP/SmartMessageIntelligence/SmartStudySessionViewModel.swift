import Foundation

@MainActor
final class SmartStudySessionViewModel: ObservableObject {
    @Published var session: SmartStudySession?
    @Published var insight: SmartDiscussionInsight?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = AmenSmartMessageIntelligenceService.shared

    func start(spaceId: String, threadId: String, seedMessageIds: [String], title: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            session = try await service.startStudyMode(spaceId: spaceId, threadId: threadId, seedMessageIds: seedMessageIds, title: title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
