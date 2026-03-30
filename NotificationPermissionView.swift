//
//  NotificationPermissionView.swift
//  AMENAPP
//
//  Production-ready notification permission education screen
//  Shows BEFORE the system permission dialog to improve conversion
//

import SwiftUI

struct NotificationPermissionView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isRequestingPermission = false
    @State private var showSettingsAlert = false
    
    var body: some View {
        ZStack {
            // Soft gradient background matching app design
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.94, blue: 0.98),
                    Color(red: 0.98, green: 0.95, blue: 0.97),
                    Color(red: 1.0, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 40)
                    
                    // Icon - Animated notification bell
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.blue.opacity(0.2),
                                        Color.purple.opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                        
                        // Inner circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.15),
                                        Color.purple.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        // Bell icon
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.bounce, options: .repeating.speed(0.5))
                    }
                    .padding(.bottom, 8)
                    
                    // Title and subtitle
                    VStack(spacing: 12) {
                        Text("Stay Connected")
                            .font(.custom("OpenSans-Bold", size: 32))
                            .foregroundStyle(.black)
                        
                        Text("Get notified about what matters to you")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    
                    // Benefits list
                    VStack(alignment: .leading, spacing: 20) {
                        NotificationBenefitRow(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "Engagement",
                            description: "Likes and comments on your posts"
                        )
                        
                        NotificationBenefitRow(
                            icon: "message.fill",
                            iconColor: .blue,
                            title: "Messages",
                            description: "Never miss a message from your community"
                        )
                        
                        NotificationBenefitRow(
                            icon: "hands.sparkles",
                            iconColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                            title: "Prayer Requests",
                            description: "Stay updated on prayer needs and answers"
                        )
                        
                        NotificationBenefitRow(
                            icon: "bell.badge.fill",
                            iconColor: .purple,
                            title: "Updates",
                            description: "Important announcements and features"
                        )
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    
                    Spacer()
                        .frame(height: 20)
                    
                    // Buttons
                    VStack(spacing: 16) {
                        // Enable Notifications button
                        Button {
                            requestPermission()
                        } label: {
                            HStack(spacing: 8) {
                                if isRequestingPermission {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Enable Notifications")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 26)
                                    .fill(.black)
                                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                            )
                        }
                        .disabled(isRequestingPermission)
                        
                        // Skip button
                        Button {
                            dismiss()
                        } label: {
                            Text("I'll do this later")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.black.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .alert("Enable in Settings", isPresented: $showSettingsAlert) {
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
                dismiss()
            }
            Button("Not Now", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("You previously denied notification permissions. You can enable them in Settings > AMEN > Notifications")
        }
        .interactiveDismissDisabled(true) // User must explicitly choose
    }
    
    // MARK: - Request Permission
    
    private func requestPermission() {
        isRequestingPermission = true
        
        Task {
            // Check if already decided (previously denied)
            let currentStatus = await checkCurrentStatus()
            
            if currentStatus == .denied {
                // User previously denied - show settings alert
                await MainActor.run {
                    isRequestingPermission = false
                    showSettingsAlert = true
                }
                return
            }
            
            // Request permission
            let granted = await PushNotificationManager.shared.requestNotificationPermissions()
            
            await MainActor.run {
                isRequestingPermission = false
                
                if granted {
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Mark as completed
                    UserDefaults.standard.set(true, forKey: "hasCompletedNotificationPermission")
                    
                    // Dismiss
                    dismiss()
                } else {
                    // User denied - just dismiss (they chose not to enable)
                    UserDefaults.standard.set(true, forKey: "hasCompletedNotificationPermission")
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Check Current Status
    
    private func checkCurrentStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
}

// MARK: - Notification Benefit Row Component

struct NotificationBenefitRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon container
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.black)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

#Preview {
    NotificationPermissionView()
}
