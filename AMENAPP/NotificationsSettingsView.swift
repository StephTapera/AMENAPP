//
//  NotificationsSettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    // Notification Settings State
    @State private var notificationsEnabled = false
    @State private var amensNotifications = true
    @State private var commentsNotifications = true
    @State private var followNotifications = true
    @State private var mentionNotifications = true
    @State private var messageNotifications = true
    @State private var groupNotifications = true
    @State private var eventNotifications = true
    @State private var prayerRequestNotifications = true
    @State private var weeklyDigest = true
    @State private var communityUpdates = true
    
    // Push Notification Sounds
    @State private var soundEnabled = true
    @State private var vibrationEnabled = true
    @State private var showPreview = true
    
    // Loading States
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showPermissionAlert = false
    
    private let db = Firestore.firestore()
    
    private var notificationStatusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Push Notifications")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                Text(notificationsEnabled ? "Enabled" : "Disabled in Settings")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(notificationsEnabled ? .green : .red)
            }
            
            Spacer()
            
            if !notificationsEnabled {
                Button {
                    openAppSettings()
                } label: {
                    Text("Enable")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.blue)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
    
    var body: some View {
        List {
            systemSection
            activitySection
            socialSection
            prayerCommunitySection
            notificationStyleSection
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
        .task {
            await checkNotificationPermission()
            await loadNotificationSettings()
        }
        .modifier(NotificationChangeModifier(
            amensNotifications: amensNotifications,
            commentsNotifications: commentsNotifications,
            followNotifications: followNotifications,
            mentionNotifications: mentionNotifications,
            messageNotifications: messageNotifications,
            groupNotifications: groupNotifications,
            eventNotifications: eventNotifications,
            prayerRequestNotifications: prayerRequestNotifications,
            weeklyDigest: weeklyDigest,
            communityUpdates: communityUpdates,
            soundEnabled: soundEnabled,
            vibrationEnabled: vibrationEnabled,
            showPreview: showPreview,
            saveAction: saveNotificationSettings
        ))
    }
    
    // MARK: - Section Views
    
    private var systemSection: some View {
        Section {
            notificationStatusRow
        } header: {
            Text("SYSTEM")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("You can manage notification permissions in your device settings")
                .font(.custom("OpenSans-Regular", size: 12))
        }
    }
    
    private var activitySection: some View {
        Section {
            Toggle(isOn: $amensNotifications) {
                HStack {
                    Image(systemName: "hands.sparkles.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("Amens")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $commentsNotifications) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                        .foregroundStyle(.green)
                        .frame(width: 24)
                    Text("Comments")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $followNotifications) {
                HStack {
                    Image(systemName: "person.fill.badge.plus")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    Text("New Followers")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $mentionNotifications) {
                HStack {
                    Image(systemName: "at")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text("Mentions")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
        } header: {
            Text("ACTIVITY")
                .font(.custom("OpenSans-Bold", size: 12))
        }
    }
    
    private var socialSection: some View {
        Section {
            Toggle(isOn: $messageNotifications) {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("Direct Messages")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $groupNotifications) {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.indigo)
                        .frame(width: 24)
                    Text("Group Activity")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $eventNotifications) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.red)
                        .frame(width: 24)
                    Text("Events")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
        } header: {
            Text("SOCIAL")
                .font(.custom("OpenSans-Bold", size: 12))
        }
    }
    
    private var prayerCommunitySection: some View {
        Section {
            Toggle(isOn: $prayerRequestNotifications) {
                HStack {
                    Image(systemName: "hands.and.sparkles.fill")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    Text("Prayer Requests")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $weeklyDigest) {
                HStack {
                    Image(systemName: "newspaper.fill")
                        .foregroundStyle(.brown)
                        .frame(width: 24)
                    Text("Weekly Digest")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $communityUpdates) {
                HStack {
                    Image(systemName: "megaphone.fill")
                        .foregroundStyle(.pink)
                        .frame(width: 24)
                    Text("Community Updates")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
        } header: {
            Text("PRAYER & COMMUNITY")
                .font(.custom("OpenSans-Bold", size: 12))
        }
    }
    
    private var notificationStyleSection: some View {
        Section {
            Toggle(isOn: $soundEnabled) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: 24)
                    Text("Sound")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $vibrationEnabled) {
                HStack {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .frame(width: 24)
                    Text("Vibration")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
            
            Toggle(isOn: $showPreview) {
                HStack {
                    Image(systemName: "eye.fill")
                        .frame(width: 24)
                    Text("Show Previews")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .tint(.blue)
            .disabled(!notificationsEnabled)
        } header: {
            Text("NOTIFICATION STYLE")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("Choose how you want to be notified")
                .font(.custom("OpenSans-Regular", size: 12))
        }
    }
    
    private func checkNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        await MainActor.run {
            notificationsEnabled = settings.authorizationStatus == .authorized
        }
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func loadNotificationSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let data = document.data(),
               let notifSettings = data["notificationSettings"] as? [String: Bool] {
                await MainActor.run {
                    amensNotifications = notifSettings["amens"] ?? true
                    commentsNotifications = notifSettings["comments"] ?? true
                    followNotifications = notifSettings["follows"] ?? true
                    mentionNotifications = notifSettings["mentions"] ?? true
                    messageNotifications = notifSettings["messages"] ?? true
                    groupNotifications = notifSettings["groups"] ?? true
                    eventNotifications = notifSettings["events"] ?? true
                    prayerRequestNotifications = notifSettings["prayerRequests"] ?? true
                    weeklyDigest = notifSettings["weeklyDigest"] ?? true
                    communityUpdates = notifSettings["communityUpdates"] ?? true
                    soundEnabled = notifSettings["sound"] ?? true
                    vibrationEnabled = notifSettings["vibration"] ?? true
                    showPreview = notifSettings["showPreview"] ?? true
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("❌ Error loading notification settings: \(error.localizedDescription)")
        }
    }
    
    private func saveNotificationSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        await MainActor.run {
            isSaving = true
        }
        
        let settings: [String: Bool] = [
            "amens": amensNotifications,
            "comments": commentsNotifications,
            "follows": followNotifications,
            "mentions": mentionNotifications,
            "messages": messageNotifications,
            "groups": groupNotifications,
            "events": eventNotifications,
            "prayerRequests": prayerRequestNotifications,
            "weeklyDigest": weeklyDigest,
            "communityUpdates": communityUpdates,
            "sound": soundEnabled,
            "vibration": vibrationEnabled,
            "showPreview": showPreview
        ]
        
        do {
            try await db.collection("users").document(userId).updateData([
                "notificationSettings": settings,
                "notificationSettingsUpdatedAt": FieldValue.serverTimestamp()
            ])
            
            await MainActor.run {
                isSaving = false
            }
            
            print("✅ Notification settings saved successfully")
        } catch {
            await MainActor.run {
                isSaving = false
            }
            print("❌ Error saving notification settings: \(error.localizedDescription)")
        }
    }
}

// MARK: - ViewModifier for handling notification changes
private struct NotificationChangeModifier: ViewModifier {
    let amensNotifications: Bool
    let commentsNotifications: Bool
    let followNotifications: Bool
    let mentionNotifications: Bool
    let messageNotifications: Bool
    let groupNotifications: Bool
    let eventNotifications: Bool
    let prayerRequestNotifications: Bool
    let weeklyDigest: Bool
    let communityUpdates: Bool
    let soundEnabled: Bool
    let vibrationEnabled: Bool
    let showPreview: Bool
    let saveAction: () async -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: amensNotifications) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: commentsNotifications) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: followNotifications) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: mentionNotifications) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: messageNotifications) { _, _ in
                Task { await saveAction() }
            }
            .modifier(AdditionalNotificationChanges(
                groupNotifications: groupNotifications,
                eventNotifications: eventNotifications,
                prayerRequestNotifications: prayerRequestNotifications,
                weeklyDigest: weeklyDigest,
                communityUpdates: communityUpdates,
                soundEnabled: soundEnabled,
                vibrationEnabled: vibrationEnabled,
                showPreview: showPreview,
                saveAction: saveAction
            ))
    }
}

// Additional modifier to split up the onChange chain
private struct AdditionalNotificationChanges: ViewModifier {
    let groupNotifications: Bool
    let eventNotifications: Bool
    let prayerRequestNotifications: Bool
    let weeklyDigest: Bool
    let communityUpdates: Bool
    let soundEnabled: Bool
    let vibrationEnabled: Bool
    let showPreview: Bool
    let saveAction: () async -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: groupNotifications) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: eventNotifications) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: prayerRequestNotifications) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: weeklyDigest) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: communityUpdates) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: soundEnabled) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: vibrationEnabled) { _, _ in
                Task { await saveAction() }
            }
            .onChange(of: showPreview) { _, _ in
                Task { await saveAction() }
            }
    }
}

#Preview {
    NavigationStack {
        NotificationsSettingsView()
            .environmentObject(AuthenticationViewModel())
    }
}
