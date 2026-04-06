import Foundation

@MainActor
final class CreatorProjectViewModel: ObservableObject {
    @Published private(set) var project: CreatorProject?
    @Published private(set) var errorMessage: String?

    private let projectService: CreatorProjectServicing

    init(projectService: CreatorProjectServicing = CreatorProjectService()) {
        self.projectService = projectService
    }

    func load(projectID: String) async {
        do {
            project = try await projectService.fetchProject(projectID: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
