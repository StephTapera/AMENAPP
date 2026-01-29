//
//  NotificationSettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct NotificationSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var pushManager = PushNotificationManager.shared
    
    // Notification Preferences
    @State private var allowNotifications = true
    @State private var followNotifications = true
    @State private var amenNotifications = true
    @State private var commentNotifications = true
    @State private var messageNotifications = true
    @State private var prayerReminderNotifications = true
    @State private var soundEnabled = true
    @State private var badgeEnabled = true
    
    // Loading States
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPermissionAlert = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        List {
            // Push Notification Status
            Section {
                HStack {
                    Image(systemName: pushManager.notificationPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(pushManager.notificationPermissionGranted ? .green : .red)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push Notifications")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        
                        Text(pushManager.notificationPermissionGranted ? "Enabled" : "Disabled")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if !pushManager.notificationPermissionGranted {
                        Button("Enable") {
                            showPermissionAlert = true
                        }
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("SYSTEM SETTINGS")
                    .font(.custom("OpenSans-Bold", size: 12))
            } footer: {
                Text("Enable push notifications to receive alerts when the app is closed")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
            
            // Master Toggle
            Section {
                Toggle(isOn: $allowNotifications) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow Notifications")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Receive all app notifications")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
                .disabled(!pushManager.notificationPermissionGranted)
            } header: {
                Text("NOTIFICATION PREFERENCES")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Notification Types
            if allowNotifications {
                Section {
                    Toggle(isOn: $followNotifications) {
                        HStack {
                            Image(systemName: "person.fill.badge.plus")
                                .foregroundStyle(.green)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("New Followers")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("When someone follows you")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                    .disabled(!pushManager.notificationPermissionGranted)
                    
                    Toggle(isOn: $amenNotifications) {
                        HStack {
                            Image(systemName: "hands.sparkles.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Amens")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("When someone says Amen to your posts")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                    .disabled(!pushManager.notificationPermissionGranted)
                    
                    Toggle(isOn: $commentNotifications) {
                        HStack {
                            Image(systemName: "bubble.left.fill")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Comments")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("When someone comments on your posts")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                    .disabled(!pushManager.notificationPermissionGranted)
                    
                    Toggle(isOn: $messageNotifications) {
                        HStack {
                            Image(systemName: "message.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Messages")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("When you receive a new message")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                    .disabled(!pushManager.notificationPermissionGranted)
                    
                    Toggle(isOn: $prayerReminderNotifications) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Prayer Reminders")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("Daily prayer reminders")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.blue)
                    .disabled(!pushManager.notificationPermissionGranted)
                } header: {
                    Text("NOTIFICATION TYPES")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            
            // Notification Settings
            if allowNotifications {
                Section {
                    Toggle(isOn: $soundEnabled) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            
                            Text("Sound")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        }
                    }
                    .tint(.blue)
                    .disabled(!pushManager.notificationPermissionGranted)
                    
                    Toggle(isOn: $badgeEnabled) {
                        HStack {
                            Image(systemName: "app.badge.fill")
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            
                            Text("Badge Count")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        }
                    }
                    .tint(.blue)
                    .disabled(!pushManager.notificationPermissionGranted)
                } header: {
                    Text("DISPLAY")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            
            // Test Notification
            if pushManager.notificationPermissionGranted {
                Section {
                    Button {
                        testNotification()
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(.orange)
                            Text("Send Test Notification")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        }
                    }
                } header: {
                    Text("TESTING")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("Test notification will appear in 5 seconds")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .overlay {
            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
            }
        }
        .alert("Enable Notifications", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Go to Settings > AMENAPP > Notifications to enable push notifications")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .task {
            await checkPermissions()
            await loadNotificationSettings()
        }
        .onChange(of: allowNotifications) { _, _ in Task { await saveNotificationSettings() } }
        .onChange(of: followNotifications) { _, _ in Task { await saveNotificationSettings() } }
        .onChange(of: amenNotifications) { _, _ in Task { await saveNotificationSettings() } }
        .onChange(of: commentNotifications) { _, _ in Task { await saveNotificationSettings() } }
        .onChange(of: messageNotifications) { _, _ in Task { await saveNotificationSettings() } }
        .onChange(of: prayerReminderNotifications) { _, _ in Task { await saveNotificationSettings() } }
        .onChange(of: soundEnabled) { _, _ in Task { await saveNotificationSettings() } }
        .onChange(of: badgeEnabled) { _, _ in Task { await saveNotificationSettings() } }
    }
    
    // MARK: - Functions
    
    private func checkPermissions() async {
        _ = await pushManager.checkNotificationPermissions()
    }
    
    private func loadNotificationSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let data = document.data() {
                await MainActor.run {
                    allowNotifications = data["allowNotifications"] as? Bool ?? true
                    followNotifications = data["followNotifications"] as? Bool ?? true
                    amenNotifications = data["amenNotifications"] as? Bool ?? true
                    commentNotifications = data["commentNotifications"] as? Bool ?? true
                    messageNotifications = data["messageNotifications"] as? Bool ?? true
                    prayerReminderNotifications = data["prayerReminderNotifications"] as? Bool ?? true
                    soundEnabled = data["soundEnabled"] as? Bool ?? true
                    badgeEnabled = data["badgeEnabled"] as? Bool ?? true
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load notification settings: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func saveNotificationSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        await MainActor.run {
            isSaving = true
        }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "allowNotifications": allowNotifications,
                "followNotifications": followNotifications,
                "amenNotifications": amenNotifications,
                "commentNotifications": commentNotifications,
                "messageNotifications": messageNotifications,
                "prayerReminderNotifications": prayerReminderNotifications,
                "soundEnabled": soundEnabled,
                "badgeEnabled": badgeEnabled,
                "notificationSettingsUpdatedAt": FieldValue.serverTimestamp()
            ])
            
            await MainActor.run {
                isSaving = false
            }
            
            print("✅ Notification settings saved successfully")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save notification settings: \(error.localizedDescription)"
                isSaving = false
            }
            print("❌ Error saving notification settings: \(error.localizedDescription)")
        }
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func testNotification() {
        Task {
            await pushManager.scheduleTestNotification()
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    }
}

#Preview("Notification Settings") {
    NavigationStack {
        NotificationSettingsView()
    }
}
