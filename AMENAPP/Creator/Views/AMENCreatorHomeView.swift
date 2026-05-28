import SwiftUI
import FirebaseAuth

struct AMENCreatorHomeView: View {
    @StateObject private var viewModel = CreatorHomeViewModel()
    @State private var ownerID: String = ""
    @State private var activeProject: CreatorProject?
    @State private var showNewProjectSheet: Bool = false
    @State private var newProjectTitle: String = ""
    @State private var newProjectType: CreatorProjectType = .flyer

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    CreatorTopBar(
                        title: "AMEN Creator",
                        subtitle: "Your studio",
                        actionTitle: "New",
                        action: { showNewProjectSheet = true }
                    )

                CreatorGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick starts")
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            CreatorToggleChip(title: "Sermon Clip", isSelected: false, action: { openNewProject(type: .sermonSnippet) })
                            CreatorToggleChip(title: "Flyer", isSelected: false, action: { openNewProject(type: .flyer) })
                            CreatorToggleChip(title: "Story Pack", isSelected: false, action: { openNewProject(type: .storyPack) })
                        }
                    }
                }

                CreatorGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent projects")
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.secondary)

                        if viewModel.projects.isEmpty {
                            CreatorEmptyStateView(title: "No projects yet", subtitle: "Start a new creation")
                        } else {
                            ForEach(viewModel.projects) { project in
                                NavigationLink(value: project) {
                                    CreatorProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .navigationDestination(for: CreatorProject.self) { project in
            CreatorEditorView(project: project)
        }
        .navigationDestination(item: $activeProject) { project in
            CreatorEditorView(project: project)
        }
        .sheet(isPresented: $showNewProjectSheet) {
            CreatorNewProjectSheet(title: $newProjectTitle, projectType: $newProjectType) {
                showNewProjectSheet = false
                createProject()
            }
        }
        .task {
            ownerID = Auth.auth().currentUser?.uid ?? ""
            if !ownerID.isEmpty {
                await viewModel.load(ownerID: ownerID)
            }
        }
        .alert("Creator", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .background(Color(.systemBackground))
        }
    }

    private func openNewProject(type: CreatorProjectType) {
        newProjectType = type
        newProjectTitle = ""
        showNewProjectSheet = true
    }

    private func createProject() {
        guard !ownerID.isEmpty else { return }
        Task {
            if let project = await viewModel.createProject(title: newProjectTitle.isEmpty ? "New Project" : newProjectTitle, type: newProjectType) {
                activeProject = project
            }
        }
    }
}
