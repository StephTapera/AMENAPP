// NotificationBellButton.swift
// AMENAPP
//
// A self-contained notification bell icon with live badge count.
// Tap → presents NotificationsView as a full-screen cover.
//
// Usage (drop anywhere in a toolbar or HStack):
//   NotificationBellButton()

import SwiftUI
import FirebaseAuth

// MARK: - NotificationBellButton

struct NotificationBellButton: View {
    @ObservedObject private var badgeManager = BadgeCountManager.shared
    @State private var showNotifications    = false

    var body: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color(.label))

                if badgeManager.unreadNotifications > 0 {
                    badgePill(badgeManager.unreadNotifications)
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showNotifications) {
            NotificationsView()
        }
    }

    private func badgePill(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 4 : 5)
            .padding(.vertical, 2)
            .background(Color.red, in: Capsule())
            .fixedSize()
    }
}

// MARK: - NotificationBellButtonFilled
// Alternative with solid circle background (for light nav bars).

struct NotificationBellButtonFilled: View {
    @ObservedObject private var badgeManager = BadgeCountManager.shared
    @State private var showNotifications    = false

    var body: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 36, height: 36)
                    Image(systemName: badgeManager.unreadNotifications > 0 ? "bell.badge.fill" : "bell.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(badgeManager.unreadNotifications > 0 ? Color.red : Color(.label))
                }
                if badgeManager.unreadNotifications > 0 {
                    Text(badgeManager.unreadNotifications > 99 ? "99+" : "\(badgeManager.unreadNotifications)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .fixedSize()
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showNotifications) {
            NotificationsView()
        }
    }
}
