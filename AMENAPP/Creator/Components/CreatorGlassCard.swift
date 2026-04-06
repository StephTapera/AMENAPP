import SwiftUI

struct CreatorGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .amenGlassSurface(shape: .rounded(24), background: .balanced, placement: .inline)
    }
}
