import SwiftUI

struct CreatorBottomRail: View {
    let primaryActionTitle: String
    let secondaryActionTitle: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(secondaryActionTitle, action: secondaryAction)
                .buttonStyle(.amenGlass(role: .neutral, size: .regular, shape: .capsule))

            Button(primaryActionTitle, action: primaryAction)
                .buttonStyle(.amenGlass(role: .primary, size: .regular, shape: .capsule))
        }
        .padding(12)
        .amenGlassSurface(shape: .rounded(26), background: .balanced, placement: .floating)
    }
}
