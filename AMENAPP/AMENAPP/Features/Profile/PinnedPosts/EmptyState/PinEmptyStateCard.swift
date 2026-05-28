// PinEmptyStateCard.swift
// AMENAPP — Profile Header v2
//
// Shown ONLY on own profile when the user has 0 pinned posts.
// Dismissible; dismissed state persists in UserDefaults.
// Caller is responsible for not showing this on other users' profiles,
// but `isOwnProfile` acts as an additional guard.
//
// UserDefaults key: "profile.v2.pinEmptyStateDismissed"

import SwiftUI

// MARK: - PinEmptyStateCard

public struct PinEmptyStateCard: View {

    // MARK: - Props

    public let onTapPin: () -> Void
    public let isOwnProfile: Bool

    // MARK: - Private state

    @AppStorage("profile.v2.pinEmptyStateDismissed")
    private var isDismissed = false

    @State private var isVisible = false

    private let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)

    // MARK: - Init

    public init(onTapPin: @escaping () -> Void, isOwnProfile: Bool) {
        self.onTapPin = onTapPin
        self.isOwnProfile = isOwnProfile
    }

    // MARK: - Body

    public var body: some View {
        if isOwnProfile && !isDismissed {
            card
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 6)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        isVisible = true
                    }
                }
        }
    }

    // MARK: - Card

    private var card: some View {
        HStack(spacing: 12) {
            // Pin icon
            ZStack {
                Circle()
                    .fill(amenGold.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: "pin.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(amenGold)
            }

            // Copy
            VStack(alignment: .leading, spacing: 3) {
                Text("Pin your testimony")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Introduce yourself by pinning up to 3 posts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // Dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss pin suggestion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { onTapPin() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pin your testimony. Introduce yourself by pinning up to 3 posts. Tap to start pinning.")
        .accessibilityHint("Double-tap to open pin picker")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Background

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.62))
            )
    }

    // MARK: - Dismiss

    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isDismissed = true
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Own profile — not dismissed") {
    VStack {
        PinEmptyStateCard(
            onTapPin: { print("open pin picker") },
            isOwnProfile: true
        )
    }
    .padding(.vertical)
    .background(Color(.systemGroupedBackground))
}

#Preview("Other profile — hidden") {
    VStack {
        Text("(nothing rendered below)")
            .font(.caption)
            .foregroundStyle(.secondary)

        PinEmptyStateCard(
            onTapPin: {},
            isOwnProfile: false
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif
