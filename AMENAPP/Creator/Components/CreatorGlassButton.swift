import SwiftUI

struct CreatorGlassButton: View {
    let title: String
    let role: AmenGlassRole
    let action: () -> Void

    init(title: String, role: AmenGlassRole = .primary, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.amenGlass(role: role, size: .regular, shape: .capsule))
    }
}
