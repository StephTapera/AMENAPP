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
    @State private var savedSearchAlertNotifications = true
    @State private var soundEnabled = true
    @State private var badgeEnabled = true
    
    // Loading States
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showPermissionAlert = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                listContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Enable Notifications", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                HapticManager.impact(style: .medium)
                openAppSettings()
            }
            Button("Cancel", role: .cancel) {
                HapticManager.impact(style: .light)
            }
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
        .onDisappear {
            saveTask?.cancel()
        }
        .onChange(of: allowNotifications) { _, _ in debouncedSave() }
        .onChange(of: followNotifications) { _, _ in debouncedSave() }
        .onChange(of: amenNotifications) { _, _ in debouncedSave() }
        .onChange(of: commentNotifications) { _, _ in debouncedSave() }
        .onChange(of: messageNotifications) { _, _ in debouncedSave() }
        .onChange(of: prayerReminderNotifications) { _, _ in debouncedSave() }
        .onChange(of: savedSearchAlertNotifications) { _, _ in debouncedSave() }
        .onChange(of: soundEnabled) { _, _ in debouncedSave() }
        .onChange(of: badgeEnabled) { _, _ in debouncedSave() }
    }
    
    private var listContent: some View {
        List {
            systemSettingsSection
            notificationPreferencesSection
            
            if allowNotifications {
                notificationTypesSection
                displaySection
            }
            
            if pushManager.notificationPermissionGranted {
                testingSection
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.25), value: allowNotifications)
    }
    
    private var systemSettingsSection: some View {
        Section {
            HStack(spacing: 12) {
                let isGranted = pushManager.notificationPermissionGranted
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isGranted ? .green : .red)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Push Notifications")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    
                    Text(isGranted ? "Enabled" : "Disabled")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !isGranted {
                    Button("Enable") {
                        HapticManager.impact(style: .light)
                        showPermissionAlert = true
                    }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("SYSTEM SETTINGS")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("Enable push notifications to receive alerts when the app is closed")
                .font(.custom("OpenSans-Regular", size: 13))
        }
    }
    
    private var notificationPreferencesSection: some View {
        Section {
            Toggle(isOn: $allowNotifications.animation()) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Notifications")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    Text("Receive all app notifications")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
            .disabled(!pushManager.notificationPermissionGranted)
            .onChange(of: allowNotifications) { _, _ in
                HapticManager.impact(style: .light)
            }
        } header: {
            Text("NOTIFICATION PREFERENCES")
                .font(.custom("OpenSans-Bold", size: 12))
        }
    }
    
    private var notificationTypesSection: some View {
        Section {
            notificationToggle(
                isOn: $followNotifications,
                icon: "person.fill.badge.plus",
                iconColor: .green,
                title: "New Followers",
                subtitle: "When someone follows you"
            )
            
            notificationToggle(
                isOn: $amenNotifications,
                icon: "hands.sparkles.fill",
                iconColor: .blue,
                title: "Amens",
                subtitle: "When someone says Amen to your posts"
            )
            
            notificationToggle(
                isOn: $commentNotifications,
                icon: "bubble.left.fill",
                iconColor: .purple,
                title: "Comments",
                subtitle: "When someone comments on your posts"
            )
            
            notificationToggle(
                isOn: $messageNotifications,
                icon: "message.fill",
                iconColor: .blue,
                title: "Messages",
                subtitle: "When you receive a new message"
            )
            
            notificationToggle(
                isOn: $prayerReminderNotifications,
                icon: "bell.fill",
                iconColor: .orange,
                title: "Prayer Reminders",
                subtitle: "Daily prayer reminders"
            )
            
            notificationToggle(
                isOn: $savedSearchAlertNotifications,
                icon: "bookmark.fill",
                iconColor: .indigo,
                title: "Saved Search Alerts",
                subtitle: "New results match your saved searches"
            )
        } header: {
            Text("NOTIFICATION TYPES")
                .font(.custom("OpenSans-Bold", size: 12))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var displaySection: some View {
        Section {
            Toggle(isOn: $soundEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    
                    Text("Sound")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .tint(.blue)
            .disabled(!pushManager.notificationPermissionGranted)
            .onChange(of: soundEnabled) { _, _ in
                HapticManager.impact(style: .light)
            }
            
            Toggle(isOn: $badgeEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                        .frame(width: 28)
                    
                    Text("Badge Count")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .tint(.blue)
            .disabled(!pushManager.notificationPermissionGranted)
            .onChange(of: badgeEnabled) { _, _ in
                HapticManager.impact(style: .light)
            }
        } header: {
            Text("DISPLAY")
                .font(.custom("OpenSans-Bold", size: 12))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var testingSection: some View {
        Section {
            Button {
                HapticManager.impact(style: .medium)
                testNotification()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    
                    Text("Send Test Notification")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        } header: {
            Text("TESTING")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("Test notification will appear in 5 seconds")
                .font(.custom("OpenSans-Regular", size: 13))
        }
    }
    
    private func notificationToggle(
        isOn: Binding<Bool>,
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.blue)
        .disabled(!pushManager.notificationPermissionGranted)
        .onChange(of: isOn.wrappedValue) { _, _ in
            HapticManager.impact(style: .light)
        }
    }
    
    // MARK: - Functions
    
    private func checkPermissions() async {
        _ = await pushManager.checkNotificationPermissions()
    }
    
    private func loadNotificationSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run { isLoading = false }
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
                    savedSearchAlertNotifications = data["savedSearchAlertNotifications"] as? Bool ?? true
                    soundEnabled = data["soundEnabled"] as? Bool ?? true
                    badgeEnabled = data["badgeEnabled"] as? Bool ?? true
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load settings"
                isLoading = false
            }
        }
    }
    
    private func debouncedSave() {
        HapticManager.impact(style: .light)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second debounce
            guard !Task.isCancelled else { return }
            await saveNotificationSettings()
        }
    }
    
    private func saveNotificationSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "allowNotifications": allowNotifications,
                "followNotifications": followNotifications,
                "amenNotifications": amenNotifications,
                "commentNotifications": commentNotifications,
                "messageNotifications": messageNotifications,
                "prayerReminderNotifications": prayerReminderNotifications,
                "savedSearchAlertNotifications": savedSearchAlertNotifications,
                "soundEnabled": soundEnabled,
                "badgeEnabled": badgeEnabled,
                "notificationSettingsUpdatedAt": FieldValue.serverTimestamp()
            ])
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save settings"
            }
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
            HapticManager.notification(type: .success)
        }
    }
}

#Preview("Notification Settings") {
    NavigationStack {
        NotificationSettingsView()
    }
}
