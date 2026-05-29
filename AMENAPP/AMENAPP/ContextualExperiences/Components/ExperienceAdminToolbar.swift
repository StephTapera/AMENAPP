import SwiftUI

// MARK: - ExperienceAdminToolbar

/// Bottom admin toolbar shown inside ExperienceDetailView for admin/owner roles.
struct ExperienceAdminToolbar: View {

    let experience: ContextualExperience
    let onPublish: () -> Void
    let onUnpublish: () -> Void
    let onArchive: () -> Void
    let onEdit: () -> Void
    let onViewAnalytics: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            publishToggleButton
            toolbarPill(
                icon: "pencil",
                label: "Edit",
                action: onEdit
            )
            toolbarPill(
                icon: "archivebox",
                label: "Archive",
                action: onArchive
            )
            toolbarPill(
                icon: "chart.bar",
                label: "Analytics",
                action: onViewAnalytics
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(toolbarBackground)
        .overlay(
            Rectangle()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Publish/Unpublish toggle

    @ViewBuilder
    private var publishToggleButton: some View {
        if experience.status == .draft {
            toolbarPill(
                icon: "paperplane.fill",
                label: "Publish",
                accent: true,
                action: onPublish
            )
        } else if experience.status == .published {
            toolbarPill(
                icon: "pause.circle",
                label: "Unpublish",
                action: onUnpublish
            )
        }
    }

    // MARK: - Pill button

    private func toolbarPill(
        icon: String,
        label: String,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .imageScale(.small)
                Text(label)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(
                accent
                    ? AmenTheme.Colors.buttonPrimaryText
                    : AmenTheme.Colors.textPrimary
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(pillBackground(accent: accent))
            .overlay(pillStroke(accent: accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Admin action: \(label)")
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private func pillBackground(accent: Bool) -> some View {
        if accent {
            Capsule().fill(AmenTheme.Colors.buttonPrimary)
        } else if reduceTransparency {
            Capsule().fill(AmenTheme.Colors.surfaceChip)
        } else {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.white.opacity(0.3))
            }
        }
    }

    private func pillStroke(accent: Bool) -> some View {
        Capsule()
            .strokeBorder(
                accent
                    ? Color.clear
                    : Color.white.opacity(0.4),
                lineWidth: 0.5
            )
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        if reduceTransparency {
            AmenTheme.Colors.surfaceElevated
        } else {
            Color(uiColor: .systemBackground).opacity(0.9)
                .background(.ultraThinMaterial)
        }
    }
}
