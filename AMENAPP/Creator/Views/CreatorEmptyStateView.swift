import SwiftUI

struct CreatorEmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(Color.black)

            Text(subtitle)
                .font(AMENFont.medium(12))
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .amenGlassSurface(shape: .rounded(22), background: .quiet, placement: .inline)
    }
}
