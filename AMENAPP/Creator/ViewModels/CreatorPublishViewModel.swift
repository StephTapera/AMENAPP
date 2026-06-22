import Foundation

@MainActor
final class CreatorPublishViewModel: ObservableObject {
    @Published private(set) var activeJob: CreatorProcessingJob?
    @Published private(set) var errorMessage: String?

    private let publishService: CreatorPublishServicing

    init(publishService: CreatorPublishServicing? = nil) {
        self.publishService = publishService ?? CreatorPublishService()
    }

    func publish(projectID: String, targets: [CreatorPublishTarget]) async {
        do {
            activeJob = try await publishService.publish(projectID: projectID, targets: targets)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
