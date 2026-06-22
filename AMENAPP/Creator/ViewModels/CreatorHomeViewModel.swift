import Foundation

@MainActor
final class CreatorHomeViewModel: ObservableObject {
    @Published private(set) var projects: [CreatorProject] = []
    @Published private(set) var templates: [CreatorTemplate] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var entitlements: CreatorEntitlementState?

    private let projectService: CreatorProjectServicing
    private let templateService: CreatorTemplateServicing
    private let entitlementService: CreatorEntitlementServicing

    init(
        projectService: CreatorProjectServicing? = nil,
        templateService: CreatorTemplateServicing? = nil,
        entitlementService: CreatorEntitlementServicing? = nil
    ) {
        self.projectService = projectService ?? CreatorProjectService()
        self.templateService = templateService ?? CreatorTemplateService()
        self.entitlementService = entitlementService ?? CreatorEntitlementService()
    }

    func load(ownerID: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            projects = try await projectService.listProjects(ownerID: ownerID)
            templates = try await templateService.fetchTemplates(projectType: nil)
            entitlements = try await entitlementService.fetchEntitlements(ownerID: ownerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProject(title: String, type: CreatorProjectType) async -> CreatorProject? {
        if let entitlements, !entitlements.isPremium, projects.count >= entitlements.maxProjects {
            errorMessage = "Upgrade to create more projects."
            return nil
        }

        do {
            let project = try await projectService.createProject(title: title, type: type)
            projects.insert(project, at: 0)
            return project
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
