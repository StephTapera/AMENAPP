import SwiftUI

struct ChurchNotesBottomActionCapsule: View {
    struct Action: Identifiable {
        let id: String
        let label: String
        let icon: String
        let handler: () -> Void
    }

    let actions: [Action]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button(action: action.handler) {
                    VStack(spacing: 3) {
                        Image(systemName: action.icon).font(.system(size: 16))
                        Text(action.label).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color(.systemBackground).opacity(0.82)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        )
    }
}
