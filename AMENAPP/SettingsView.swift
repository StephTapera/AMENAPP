//
//  SettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import FirebaseAuth
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showSignOutConfirmation = false
    @State private var navigateToAccountSettings = false
    
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
            .navigationDestination(isPresented: $navigateToAccountSettings) {
                AccountSettingsView()
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .navigateToAccountSettings)) { _ in
                // Auto-navigate to Account Settings when triggered from Shabbat Mode gate
                navigateToAccountSettings = true
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
                    title: "Notifications"
                )

                Divider()
                    .background(Color.white.opacity(0.1))

                settingsNavigationLink(
                    destination: SafetyDashboardView(),
                    icon: "shield.checkered",
                    iconColor: .purple,
                    title: "Safety & Community",
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
                    title: "About AMEN"
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                ftueReplayButton
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - FTUE Replay Button
    
    private var ftueReplayButton: some View {
        Button {
            HapticManager.impact(style: .medium)
            FTUEManager.shared.resetFTUE()
            FTUEManager.shared.checkAndShowFTUE()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.purple)
                    .frame(width: 24)
                
                Text("Replay Tutorial")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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
                } catch {
                    Logger.error("Sign out failed", error: error)
                }
                dismiss()
            }
        }
    }
}



#Preview {
    NavigationStack {
        SettingsView()
    }
}
