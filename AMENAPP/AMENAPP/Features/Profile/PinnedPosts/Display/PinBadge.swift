import SwiftUI

/// Decorative gold pin badge overlay. Applied at .topTrailing alignment in Profile v2 pinned posts row.
/// Renamed ProfilePinBadge to avoid conflict with the feed-level PinBadge in AMENAPP/PinBadge.swift.
struct ProfilePinBadge: View {
    private let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(amenGold.opacity(0.15)))
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(amenGold)
                .rotationEffect(.degrees(45))
        }
        .padding(4)
        .accessibilityHidden(true)
    }
}
