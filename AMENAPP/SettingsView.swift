//
//  SettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showSignOutConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Account Section
                        accountSection
                        
                        // Social & Connections Section
                        socialSection
                        
                        // App Section
                        appSection
                        
                        // Sign Out Button
                        signOutButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
                Button("Cancel", role: .cancel) {
                    HapticManager.impact(style: .light)
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 1) {
                settingsNavigationLink(
                    destination: AccountSettingsView(),
                    icon: "person.circle.fill",
                    iconColor: .blue,
                    title: "Account Settings",
                    isFirst: true
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                settingsNavigationLink(
                    destination: PrivacySettingsView(),
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Privacy & Security"
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                settingsNavigationLink(
                    destination: NotificationSettingsView(),
                    icon: "bell.badge.fill",
                    iconColor: .orange,
                    title: "Notifications",
                    isLast: true
                )
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Social Section
    
    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SOCIAL & CONNECTIONS")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                settingsNavigationLink(
                    destination: BlockedUsersView(),
                    icon: "hand.raised.fill",
                    iconColor: .red,
                    title: "Blocked Users",
                    isFirst: true,
                    isLast: true
                )
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - App Section
    
    private var appSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APP")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 1) {
                settingsNavigationLink(
                    destination: HelpSupportView(),
                    icon: "questionmark.circle.fill",
                    iconColor: .purple,
                    title: "Help & Support",
                    isFirst: true
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                settingsNavigationLink(
                    destination: AboutAmenView(),
                    icon: "info.circle.fill",
                    iconColor: .gray,
                    title: "About AMEN",
                    isLast: true
                )
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Sign Out Button
    
    private var signOutButton: some View {
        Button(role: .destructive) {
            HapticManager.impact(style: .medium)
            showSignOutConfirmation = true
        } label: {
            HStack {
                Spacer()
                Label {
                    Text("Sign Out")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(16)
        }
        .glassEffect(GlassEffectStyle.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Navigation Link Helper
    
    @ViewBuilder
    private func settingsNavigationLink<Destination: View>(
        destination: Destination,
        icon: String,
        iconColor: Color,
        title: String,
        isFirst: Bool = false,
        isLast: Bool = false
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .contentShape(Rectangle())
        }
    }
    
    private func signOut() {
        HapticManager.notification(type: .success)
        
        // ✅ NEW: Clean up FCM token before signing out
        Task {
            await PushNotificationManager.shared.removeFCMTokenFromFirestore()
            PushNotificationManager.shared.clearBadge()
            
            // Sign out after FCM cleanup
            await MainActor.run {
                do {
                    try Auth.auth().signOut()
                    print("✅ Successfully signed out")
                } catch {
                    print("❌ Error signing out: \(error.localizedDescription)")
                }
                dismiss()
            }
        }
    }
}

// MARK: - Haptic Manager

class HapticManager {
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    static func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
