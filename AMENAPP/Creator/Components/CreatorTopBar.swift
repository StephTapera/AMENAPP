import SwiftUI

struct CreatorTopBar: View {
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, subtitle: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.bold(24))
                    .foregroundStyle(Color.black)

                if let subtitle {
                    Text(subtitle)
                        .font(AMENFont.medium(13))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.amenGlass(role: .utility, size: .compact, shape: .capsule))
            }
        }
        .padding(16)
        .amenGlassSurface(shape: .rounded(24), background: .balanced, placement: .inline)
    }
}
