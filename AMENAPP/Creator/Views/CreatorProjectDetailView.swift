import SwiftUI

struct CreatorProjectDetailView: View {
    let project: CreatorProject

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CreatorTopBar(title: project.title, subtitle: project.projectType.rawValue)

                CreatorGlassCard {
                    Text("Project status: \(project.status.rawValue)")
                        .font(AMENFont.medium(14))
                        .foregroundStyle(.secondary)
                }

                CreatorPrimaryCTA(title: "Open editor") {}
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(Color(.systemBackground))
    }
}
