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
            List {
            // Account Section
            Section {
                settingsNavigationLink(
                    destination: AccountSettingsView(),
                    icon: "person.circle.fill",
                    iconColor: .blue,
                    title: "Account Settings"
                )
                
                settingsNavigationLink(
                    destination: PrivacySettingsView(),
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Privacy & Security"
                )
                
                settingsNavigationLink(
                    destination: NotificationSettingsView(),
                    icon: "bell.badge.fill",
                    iconColor: .orange,
                    title: "Notifications"
                )
            } header: {
                Text("ACCOUNT")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Social & Connections Section
            Section {
                settingsNavigationLink(
                    destination: BlockedUsersView(),
                    icon: "hand.raised.fill",
                    iconColor: .red,
                    title: "Blocked Users"
                )
            } header: {
                Text("SOCIAL & CONNECTIONS")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // App Section
            Section {
                settingsNavigationLink(
                    destination: HelpSupportView(),
                    icon: "questionmark.circle.fill",
                    iconColor: .purple,
                    title: "Help & Support"
                )
                
                settingsNavigationLink(
                    destination: AboutAmenView(),
                    icon: "info.circle.fill",
                    iconColor: .gray,
                    title: "About AMEN"
                )
            } header: {
                Text("APP")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Sign Out
            Section {
                Button(role: .destructive) {
                    HapticManager.impact(style: .medium)
                    showSignOutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label {
                            Text("Sign Out")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    HapticManager.impact(style: .light)
                    dismiss()
                }
                .font(.custom("OpenSans-SemiBold", size: 16))
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
        } // NavigationStack
    }
    
    @ViewBuilder
    private func settingsNavigationLink<Destination: View>(
        destination: Destination,
        icon: String,
        iconColor: Color,
        title: String
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
            }
        }
        .listRowBackground(Color(.systemBackground))
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
