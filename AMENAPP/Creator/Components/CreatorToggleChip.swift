import SwiftUI

struct CreatorToggleChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AMENFont.medium(12))
        }
        .buttonStyle(.amenGlass(role: isSelected ? .primary : .neutral, size: .compact, shape: .capsule))
    }
}
