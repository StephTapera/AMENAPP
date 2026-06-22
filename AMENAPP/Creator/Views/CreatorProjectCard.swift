import SwiftUI

struct CreatorProjectCard: View {
    let project: CreatorProject

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)

                Text(project.projectType.rawValue.capitalized)
                    .font(AMENFont.medium(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(project.status.rawValue.capitalized)
                .font(AMENFont.medium(11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .amenGlassSurface(shape: .rounded(20), background: .balanced, placement: .inline)
    }
}
