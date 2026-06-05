// SpaceRoleActionBar.swift
// AMEN SpacesOS — Standalone glass action bar, role-aware.
//
// Design constraints:
//   - Chrome: .thinMaterial (AmenLiquidGlass pattern) — NOT matte card surface
//   - Guest actions: visibly disabled, tappable for tooltip, clear disabledReason shown
//   - Reduce Motion + Reduce Transparency honored throughout
//   - Max 4 actions visible; overflow handled by "More" button (not yet wired)

import SwiftUI

// MARK: - SpaceRoleActionBar

struct SpaceRoleActionBar: View {
    let role: SpaceMemberRole
    let spaceName: String

    // Injected action callbacks — callers supply concrete implementations
    var onPostAnnouncement: (() -> Void)?
    var onManageMembers: (() -> Void)?
    var onViewAnalytics: (() -> Void)?
    var onCreateEvent: (() -> Void)?
    var onCreatePost: (() -> Void)?
    var onRequestPrayer: (() -> Void)?
    var onRSVP: (() -> Void)?
    var onAddNote: (() -> Void)?
    var onViewRequests: (() -> Void)?

    @State private var disabledTooltipAction: SpaceQuickAction?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var actions: [SpaceQuickAction] {
        SpaceRoleActionProvider.actions(
            for: role,
            spaceName: spaceName,
            onPostAnnouncement: onPostAnnouncement,
            onManageMembers: onManageMembers,
            onViewAnalytics: onViewAnalytics,
            onCreateEvent: onCreateEvent,
            onCreatePost: onCreatePost,
            onRequestPrayer: onRequestPrayer,
            onRSVP: onRSVP,
            onAddNote: onAddNote,
            onViewRequests: onViewRequests
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tooltip for disabled guest actions
            if let tip = disabledTooltipAction {
                Text(tip.disabledReason ?? "Join to participate")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color(hex: "D9A441").opacity(0.90))
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                    )
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                                disabledTooltipAction = nil
                            }
                        }
                    }
                    .padding(.bottom, 6)
            }

            // Action pill bar
            HStack(spacing: 0) {
                ForEach(actions.prefix(4)) { action in
                    actionButton(action)
                    if action.id != actions.prefix(4).last?.id {
                        Divider()
                            .frame(height: 28)
                            .foregroundStyle(Color.white.opacity(0.12))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.10, green: 0.08, blue: 0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color(hex: "D9A441").opacity(0.20), lineWidth: 0.5)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color(hex: "D9A441").opacity(0.18), lineWidth: 0.5)
                        }
                }
            }
            .shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 6)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82), value: disabledTooltipAction?.id)
    }

    @ViewBuilder
    private func actionButton(_ action: SpaceQuickAction) -> some View {
        Button {
            if action.isEnabled {
                action.action()
            } else {
                withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.78)) {
                    disabledTooltipAction = action
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(action.isEnabled ? Color(hex: "D9A441") : Color.white.opacity(0.28))

                Text(action.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(action.isEnabled ? Color.white.opacity(0.80) : Color.white.opacity(0.28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityHint(action.isEnabled ? "" : (action.disabledReason ?? "Join to participate"))
        .accessibilityAddTraits(action.isEnabled ? [] : .isStaticText)
    }
}

// MARK: - SpaceRoleActionProvider

/// Single source of truth for per-role action sets.
/// Callers should not replicate this switch logic.
enum SpaceRoleActionProvider {
    static func actions(
        for role: SpaceMemberRole,
        spaceName: String,
        onPostAnnouncement: (() -> Void)?,
        onManageMembers: (() -> Void)?,
        onViewAnalytics: (() -> Void)?,
        onCreateEvent: (() -> Void)?,
        onCreatePost: (() -> Void)?,
        onRequestPrayer: (() -> Void)?,
        onRSVP: (() -> Void)?,
        onAddNote: (() -> Void)?,
        onViewRequests: (() -> Void)?
    ) -> [SpaceQuickAction] {
        switch role {
        case .pastor, .admin:
            return [
                SpaceQuickAction(id: "post-ann", label: "Announce", icon: "megaphone.fill", action: onPostAnnouncement ?? {}),
                SpaceQuickAction(id: "manage", label: "Members", icon: "person.badge.key.fill", action: onManageMembers ?? {}),
                SpaceQuickAction(id: "analytics", label: "Analytics", icon: "chart.bar.fill", action: onViewAnalytics ?? {}),
                SpaceQuickAction(id: "create-evt", label: "Event", icon: "calendar.badge.plus", action: onCreateEvent ?? {})
            ]

        case .leader:
            return [
                SpaceQuickAction(id: "draft-ann", label: "Announce", icon: "megaphone.fill", action: onPostAnnouncement ?? {}),
                SpaceQuickAction(id: "create-evt", label: "Event", icon: "calendar.badge.plus", action: onCreateEvent ?? {}),
                SpaceQuickAction(id: "view-req", label: "Requests", icon: "tray.full.fill", action: onViewRequests ?? {}),
                SpaceQuickAction(id: "create-post", label: "Post", icon: "square.and.pencil", action: onCreatePost ?? {})
            ]

        case .member:
            return [
                SpaceQuickAction(id: "create-post", label: "Post", icon: "square.and.pencil", action: onCreatePost ?? {}),
                SpaceQuickAction(id: "prayer", label: "Pray", icon: "hands.sparkles.fill", action: onRequestPrayer ?? {}),
                SpaceQuickAction(id: "rsvp", label: "RSVP", icon: "calendar.badge.checkmark", action: onRSVP ?? {}),
                SpaceQuickAction(id: "note", label: "Add Note", icon: "note.text.badge.plus", action: onAddNote ?? {})
            ]

        case .guest:
            let reason = "Join \(spaceName) to participate"
            return [
                SpaceQuickAction(id: "guest-post", label: "Post", icon: "square.and.pencil", isEnabled: false, disabledReason: reason),
                SpaceQuickAction(id: "guest-pray", label: "Pray", icon: "hands.sparkles.fill", isEnabled: false, disabledReason: reason),
                SpaceQuickAction(id: "guest-rsvp", label: "RSVP", icon: "calendar.badge.checkmark", isEnabled: false, disabledReason: reason),
                SpaceQuickAction(id: "guest-note", label: "Note", icon: "note.text.badge.plus", isEnabled: false, disabledReason: reason)
            ]
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Pastor role") {
    ZStack {
        Color(red: 0.027, green: 0.024, blue: 0.031).ignoresSafeArea()
        VStack {
            Spacer()
            SpaceRoleActionBar(role: .pastor, spaceName: "Elevation Church")
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Member role") {
    ZStack {
        Color(red: 0.027, green: 0.024, blue: 0.031).ignoresSafeArea()
        VStack {
            Spacer()
            SpaceRoleActionBar(role: .member, spaceName: "Elevation Church")
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Guest role") {
    ZStack {
        Color(red: 0.027, green: 0.024, blue: 0.031).ignoresSafeArea()
        VStack {
            Spacer()
            SpaceRoleActionBar(role: .guest, spaceName: "Elevation Church")
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        }
    }
    .preferredColorScheme(.dark)
}
#endif
