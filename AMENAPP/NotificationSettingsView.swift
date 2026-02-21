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
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    }
                } else {
                    glassContent
                }
            }
        }
        .animation(.standardUI, value: isLoading)
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
    
    private var glassContent: some View {
        ScrollView {
            VStack(spacing: 16) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
    
    private var systemSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SYSTEM SETTINGS")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    let isGranted = pushManager.notificationPermissionGranted
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isGranted ? .green : .red)
                        .frame(width: 28)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push Notifications")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                        
                        Text(isGranted ? "Enabled" : "Disabled")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.white.opacity(0.6))
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
                .padding(16)
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Text("Enable push notifications to receive alerts when the app is closed")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 16)
        }
    }
    
    private var notificationPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICATION PREFERENCES")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                Toggle(isOn: $allowNotifications.animation(.standardUI)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow Notifications")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                        Text("Receive all app notifications")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .tint(.blue)
                .disabled(!pushManager.notificationPermissionGranted)
                .padding(16)
                .onChange(of: allowNotifications) { _, _ in
                    HapticManager.impact(style: .light)
                }
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var notificationTypesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICATION TYPES")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 1) {
                notificationToggle(
                    isOn: $followNotifications,
                    icon: "person.fill.badge.plus",
                    iconColor: .green,
                    title: "New Followers",
                    subtitle: "When someone follows you",
                    isFirst: true
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
                    subtitle: "New results match your saved searches",
                    isLast: true
                )
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        ))
    }
    
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DISPLAY")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 1) {
                Toggle(isOn: $soundEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        
                        Text("Sound")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .tint(.blue)
                .disabled(!pushManager.notificationPermissionGranted)
                .padding(16)
                .background(Color.white.opacity(0.05))
                .onChange(of: soundEnabled) { _, _ in
                    HapticManager.impact(style: .light)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                Toggle(isOn: $badgeEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "app.badge.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                            .frame(width: 28)
                        
                        Text("Badge Count")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .tint(.blue)
                .disabled(!pushManager.notificationPermissionGranted)
                .padding(16)
                .background(Color.white.opacity(0.05))
                .onChange(of: badgeEnabled) { _, _ in
                    HapticManager.impact(style: .light)
                }
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        ))
    }
    
    private var testingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TESTING")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
            
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
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(16)
            }
            .glassEffect(GlassEffectStyle.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Text("Test notification will appear in 5 seconds")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 16)
        }
    }
    
    private func notificationToggle(
        isOn: Binding<Bool>,
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isFirst: Bool = false,
        isLast: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(iconColor)
                        .frame(width: 28)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .tint(.blue)
            .disabled(!pushManager.notificationPermissionGranted)
            .padding(16)
            .background(Color.white.opacity(0.05))
            .onChange(of: isOn.wrappedValue) { _, _ in
                HapticManager.impact(style: .light)
            }
            
            if !isLast {
                Divider()
                    .background(Color.white.opacity(0.1))
            }
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
