//
//  AmenProfileGlassActionSheet.swift
//  AMENAPP
//
//  Light frosted-glass bottom sheet: quick-action rows + account switcher rail.
//  Surface: .ultraThinMaterial with systemBackground overlay (light glass, not dark).
//  Spring: .amenSpring for sheet entry, .amenSnappy for selection changes.
//

import SwiftUI

// MARK: - ProfileSheetAction

enum ProfileSheetAction {
    case editProfile
    case sabbathMode
    case prayerJournal
    case myTestimonies
    case bereanStudyNotes
    case mySpaces
    case allSettings
    case signOut
}

// MARK: - AmenProfileGlassActionSheet

struct AmenProfileGlassActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAction: (ProfileSheetAction) -> Void

    @ObservedObject private var accountManager = AMENMultiAccountManager.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Sheet glass background
            sheetBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Drag handle region (implicit via presentationDragIndicator, but we
                    // leave 20pt top padding so content doesn't kiss the indicator)
                    Spacer().frame(height: 20)

                    actionSection

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    accountSwitcherSection

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 16)
            }
        }
        .presentationDetents([.height(520)])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        // Override the background applied by amenSheet() so we control the glass surface
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Sheet Background

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Color(.systemBackground).opacity(0.7)
        }
    }

    // MARK: - Action Rows

    private var actionSection: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "person.circle",
                label: "Edit Profile",
                tint: AmenTheme.Colors.amenBlue,
                action: .editProfile
            )
            rowDivider
            actionRow(
                icon: "moon.stars",
                label: "Sabbath Mode",
                tint: AmenTheme.Colors.amenPurple,
                action: .sabbathMode
            )
            rowDivider
            actionRow(
                icon: "hands.and.sparkles",
                label: "Prayer Journal",
                tint: AmenTheme.Colors.amenGold,
                action: .prayerJournal
            )
            rowDivider
            actionRow(
                icon: "star.bubble",
                label: "My Testimonies",
                tint: AmenTheme.Colors.amenGold,
                action: .myTestimonies
            )
            rowDivider
            actionRow(
                icon: "book.and.wrench",
                label: "Berean Study Notes",
                tint: AmenTheme.Colors.amenBlue,
                action: .bereanStudyNotes
            )
            rowDivider
            actionRow(
                icon: "square.stack.3d.up",
                label: "My Spaces",
                tint: AmenTheme.Colors.amenPurple,
                action: .mySpaces
            )
            rowDivider
            actionRow(
                icon: "gearshape",
                label: "All Settings",
                tint: Color.secondary,
                action: .allSettings
            )
            rowDivider
            actionRow(
                icon: "rectangle.portrait.and.arrow.right",
                label: "Sign Out",
                tint: Color.red.opacity(0.8),
                action: .signOut,
                isDestructive: true
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground).opacity(reduceTransparency ? 1.0 : 0.5))
        )
    }

    private var rowDivider: some View {
        Color.primary.opacity(0.06)
            .frame(height: 1)
            .padding(.horizontal, 56) // align with label, not icon
    }

    // MARK: - Single Action Row

    private func actionRow(
        icon: String,
        label: String,
        tint: Color,
        action: ProfileSheetAction,
        isDestructive: Bool = false
    ) -> some View {
        ActionRowButton(
            icon: icon,
            label: label,
            tint: tint,
            isDestructive: isDestructive,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        ) {
            HapticManager.impact(style: .light)
            dismiss()
            onAction(action)
        }
    }

    // MARK: - Account Switcher Rail

    private var accountSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SWITCH ACCOUNT")
                .font(AMENFont.semiBold(12))
                .tracking(0.8)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 4)

            if accountManager.accounts.isEmpty {
                Text("No other accounts")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(accountManager.accounts) { account in
                            AccountAvatarChip(
                                account: account,
                                isActive: account.id == accountManager.currentAccount?.id,
                                reduceMotion: reduceMotion
                            ) {
                                Task { @MainActor in
                                    _ = await accountManager.switchAccount(to: account)
                                    dismiss()
                                }
                            }
                        }

                        // Add account chip (only shown when under the 5-account cap)
                        if accountManager.canAddAccount {
                            AddAccountChip()
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - ActionRowButton

private struct ActionRowButton: View {
    let icon: String
    let label: String
    let tint: Color
    let isDestructive: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon in glass circle
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tint)
                }

                Text(label)
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(isDestructive ? Color.red.opacity(0.85) : Color.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                if isPressed {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        .opacity(isPressed && !reduceMotion ? 0.9 : 1.0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.82),
            value: isPressed
        )
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - AccountAvatarChip

private struct AccountAvatarChip: View {
    let account: AMENAccount
    let isActive: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    @GestureState private var isPressed = false

    private let avatarSize: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    // Avatar circle
                    Group {
                        if let urlString = account.profileImageURL,
                           let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    initialsView
                                }
                            }
                        } else {
                            initialsView
                        }
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())

                    // amenGold active ring
                    if isActive {
                        Circle()
                            .strokeBorder(AmenTheme.Colors.amenGold, lineWidth: 2.5)
                            .frame(width: avatarSize + 5, height: avatarSize + 5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Checkmark badge for active account
                    if isActive {
                        ZStack {
                            Circle()
                                .fill(AmenTheme.Colors.amenGold)
                                .frame(width: 16, height: 16)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(.systemBackground))
                        }
                        .offset(x: 2, y: 2)
                    }
                }

                // Username caps
                Text("@\(account.username.isEmpty ? account.name : account.username)")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(isActive ? AmenTheme.Colors.amenGold : Color.secondary)
                    .lineLimit(1)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed && !reduceMotion ? 0.95 : 1.0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.74),
            value: isPressed
        )
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .accessibilityLabel("\(account.username)\(isActive ? ", current account" : "")")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(AmenTheme.Colors.amenBlue.opacity(0.18))
            Text(String(account.name.prefix(2)).uppercased())
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
    }
}

// MARK: - AddAccountChip

private struct AddAccountChip: View {
    private let size: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: size, height: size)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }

            Text("Add")
                .font(AMENFont.regular(11))
                .foregroundStyle(Color.secondary)
                .frame(width: 56)
        }
        .accessibilityLabel("Add account")
        .accessibilityAddTraits(.isButton)
    }
}
