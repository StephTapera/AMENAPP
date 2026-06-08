import SwiftUI

struct CreatorNewProjectSheet: View {
    @Binding var title: String
    @Binding var projectType: CreatorProjectType
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            CreatorTopBar(title: "New Project", subtitle: "Start creation")

            CreatorGlassCard {
                TextField("Project title", text: $title)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.primary)
            }

            CreatorGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Project type")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(Color.black.opacity(0.6))

                    CreatorProjectTypePickerView(selection: $projectType)
                }
            }

            CreatorPrimaryCTA(title: "Create", action: onCreate)
        }
        .padding(20)
        .background(Color(.systemBackground))
    }
}
