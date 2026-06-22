import SwiftUI

struct CreatorToolbar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(12)
        .amenGlassSurface(shape: .rounded(22), background: .balanced, placement: .inline)
    }
}
