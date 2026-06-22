//
//  OnboardingNotificationsView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI
import UserNotifications

struct OnboardingNotificationsView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    @State private var isPrayerNotificationsEnabled = true
    @State private var isTestimonyNotificationsEnabled = true
    @State private var isMessageNotificationsEnabled = true
    @State private var isCommunityNotificationsEnabled = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: coordinator.currentStep.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 40)
                
                // Title and subtitle
                VStack(spacing: 8) {
                    Text(coordinator.currentStep.title)
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.black)
                    
                    Text(coordinator.currentStep.subtitle)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                
                // Notification toggles
                VStack(spacing: 16) {
                    NotificationToggleRow(
                        icon: "hands.clap.fill",
                        title: "Prayer Requests",
                        description: "Get notified when someone needs prayer",
                        isEnabled: $isPrayerNotificationsEnabled
                    )
                    
                    NotificationToggleRow(
                        icon: "heart.fill",
                        title: "Testimonies",
                        description: "See new testimonies from the community",
                        isEnabled: $isTestimonyNotificationsEnabled
                    )
                    
                    NotificationToggleRow(
                        icon: "message.fill",
                        title: "Messages",
                        description: "Get alerts for new direct messages",
                        isEnabled: $isMessageNotificationsEnabled
                    )
                    
                    NotificationToggleRow(
                        icon: "bell.fill",
                        title: "Community Updates",
                        description: "Stay updated on community events",
                        isEnabled: $isCommunityNotificationsEnabled
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Permission button
                VStack(spacing: 12) {
                    Button {
                        requestNotificationPermission()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 16))
                            Text("Enable Notifications")
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                    }
                    
                    Text("You can change these settings later in your profile")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer(minLength: 100)
            }
        }
        .onChange(of: isPrayerNotificationsEnabled) { _, _ in updateNotificationPreferences() }
        .onChange(of: isTestimonyNotificationsEnabled) { _, _ in updateNotificationPreferences() }
        .onChange(of: isMessageNotificationsEnabled) { _, _ in updateNotificationPreferences() }
        .onChange(of: isCommunityNotificationsEnabled) { _, _ in updateNotificationPreferences() }
    }
    
    private func requestNotificationPermission() {
        let haptic = UINotificationFeedbackGenerator()
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    coordinator.userData.notificationsEnabled = true
                    haptic.notificationOccurred(.success)
                    print("✅ Notifications authorized")
                } else {
                    haptic.notificationOccurred(.error)
                    print("❌ Notifications denied")
                }
            }
        }
    }
    
    private func updateNotificationPreferences() {
        // Save individual preferences
        print("📱 Notification preferences updated")
    }
}

struct NotificationToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.black)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.black.opacity(0.6))
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }
}

#Preview {
    OnboardingNotificationsView()
        .environmentObject(OnboardingCoordinator())
}
