import SwiftUI

struct CreatorSecondaryCTA: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.amenGlass(role: .neutral, size: .regular, shape: .capsule))
    }
}
