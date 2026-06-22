import SwiftUI

struct CreatorPrimaryCTA: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.amenGlass(role: .primary, size: .regular, shape: .capsule))
    }
}
