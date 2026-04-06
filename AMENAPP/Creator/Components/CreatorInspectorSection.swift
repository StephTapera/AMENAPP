import SwiftUI

struct CreatorInspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AMENFont.semiBold(13))
                .foregroundStyle(Color.black.opacity(0.6))

            content
        }
        .padding(14)
        .amenGlassSurface(shape: .rounded(22), background: .balanced, placement: .inline)
    }
}
