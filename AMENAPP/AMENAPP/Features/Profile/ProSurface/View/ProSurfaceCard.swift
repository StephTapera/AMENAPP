import SwiftUI

// MARK: - ProSurfaceCard

public struct ProSurfaceCard: View {
    public let insight: ProInsight
    public let role: ProRole
    public let onTap: () -> Void

    public init(insight: ProInsight, role: ProRole, onTap: @escaping () -> Void) {
        self.insight = insight
        self.role = role
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: roleIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)

                Text(insight.line)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private var roleIcon: String {
        switch role {
        case .mentor: return "person.2.fill"
        case .creator: return "star.fill"
        case .ministryLeader: return "building.2.fill"
        case .church: return "building.columns.fill"
        }
    }
}
