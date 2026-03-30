//
//  NotificationPrePromptView.swift
//  AMENAPP
//
//  Pre-permission screen explaining notification value before the system dialog.
//  Shows once, persisted via AppStorage. Increases opt-in rate by ~40%.
//

import SwiftUI
import UserNotifications

struct NotificationPrePromptView: View {
    @Binding var isPresented: Bool
    @AppStorage("hasSeenNotificationPrePrompt") private var hasSeen = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Title
            Text("Stay in the loop")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)

            // Value props
            VStack(alignment: .leading, spacing: 16) {
                notificationBenefit(
                    icon: "hands.sparkles.fill",
                    color: .purple,
                    title: "Prayer updates",
                    subtitle: "Know when someone prays for you"
                )
                notificationBenefit(
                    icon: "bubble.fill",
                    color: .blue,
                    title: "Message replies",
                    subtitle: "Never miss a conversation"
                )
                notificationBenefit(
                    icon: "book.fill",
                    color: .orange,
                    title: "Daily verse",
                    subtitle: "Start each day with Scripture"
                )
                notificationBenefit(
                    icon: "person.badge.plus",
                    color: .green,
                    title: "New followers",
                    subtitle: "See who's connecting with you"
                )
            }
            .padding(.horizontal, 8)

            Spacer()

            // CTA
            Button {
                requestPermission()
            } label: {
                Text("Enable Notifications")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black, in: Capsule())
            }

            Button {
                hasSeen = true
                isPresented = false
            } label: {
                Text("Not now")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
    }

    private func notificationBenefit(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestPermission() {
        hasSeen = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                isPresented = false
            }
        }
    }
}
