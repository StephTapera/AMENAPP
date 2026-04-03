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
    @State private var repliesNotifications = true
    @State private var followNotifications = true
    @State private var mentionNotifications = true
    @State private var messageNotifications = true
    @State private var groupNotifications = true
    @State private var eventNotifications = true
    @State private var prayerRequestNotifications = true
    @State private var prayerSupportedNotifications = true
    @State private var churchNoteRepliesNotifications = true
    @State private var weeklyDigest = true
    @State private var communityUpdates = true

    // Sabbath / Sunday focus
    @ObservedObject private var shabbatService = ShabbatModeService.shared

    // Daily scripture reminder
    @AppStorage("dailyScriptureReminderEnabled") private var scriptureReminderEnabled = false
    @AppStorage("dailyScriptureReminderTimeInterval") private var scriptureReminderTimeInterval: Double = 8 * 3600  // 8:00 AM
    @State private var scriptureReminderTime: Date = Calendar.current.date(
        bySettingHour: 8, minute: 0, second: 0, of: Date()
    ) ?? Date()
    @State private var showScriptureTimePicker = false

    // Navigation
    @State private var showQuietHoursSettings = false

    // Push Notification Sounds
    @State private var soundEnabled = true
    @State private var vibrationEnabled = true
    @State private var showPreview = true

    // Reply Assist (Dynamic Island smart replies)
    @AppStorage("replyAssist_suggestionsEnabled") private var replyAssistEnabled = true
    @AppStorage("replyAssist_showPreviews") private var replyAssistShowPreviews = false

    // Loading States
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showPermissionAlert = false

    private let db = Firestore.firestore()

    private var notificationStatusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Push Notifications")
                    .font(AMENFont.semiBold(15))
                Text(notificationsEnabled ? "Enabled" : "Disabled in Settings")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(notificationsEnabled ? .green : .red)
            }

            Spacer()

            if !notificationsEnabled {
                Button {
                    openAppSettings()
                } label: {
                    Text("Enable")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.blue)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                systemSection
                activitySection
                socialSection
                prayerCommunitySection
                notificationStyleSection
                sabbathFocusSection
                scriptureReminderSection
                replyAssistSection
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .overlay {
            if isLoading {
                AMENLoadingIndicator()
            }
        }
        .task {
            await checkNotificationPermission()
            await loadNotificationSettings()
        }
        .sheet(isPresented: $showQuietHoursSettings) {
            SmartNotificationSettingsView()
        }
        .modifier(NotificationChangeModifier(
            amensNotifications: amensNotifications,
            commentsNotifications: commentsNotifications,
            repliesNotifications: repliesNotifications,
            followNotifications: followNotifications,
            mentionNotifications: mentionNotifications,
            messageNotifications: messageNotifications,
            groupNotifications: groupNotifications,
            eventNotifications: eventNotifications,
            prayerRequestNotifications: prayerRequestNotifications,
            prayerSupportedNotifications: prayerSupportedNotifications,
            churchNoteRepliesNotifications: churchNoteRepliesNotifications,
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
        VStack(alignment: .leading, spacing: 0) {
            Text("SYSTEM")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                notificationStatusRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("You can manage notification permissions in your device settings")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACTIVITY")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $amensNotifications) {
                    HStack {
                        Image(systemName: "hands.sparkles.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Amens")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $commentsNotifications) {
                    HStack {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        Text("Comments on my posts")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $repliesNotifications) {
                    HStack {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Replies to my comments")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $followNotifications) {
                    HStack {
                        Image(systemName: "person.fill.badge.plus")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        Text("New Followers")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $mentionNotifications) {
                    HStack {
                        Image(systemName: "at")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text("Mentions")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
    }

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SOCIAL")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $messageNotifications) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Direct Messages")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $groupNotifications) {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(.indigo)
                            .frame(width: 24)
                        Text("Group Activity")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $eventNotifications) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(.red)
                            .frame(width: 24)
                        Text("Events")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
    }

    private var prayerCommunitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PRAYER & CHURCH")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $prayerRequestNotifications) {
                    HStack {
                        Image(systemName: "hands.and.sparkles.fill")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        Text("Prayer Requests")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $prayerSupportedNotifications) {
                    HStack {
                        Image(systemName: "hands.sparkles.fill")
                            .foregroundStyle(.indigo)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Someone is praying for me")
                                .font(AMENFont.semiBold(15))
                            Text("When someone prays for your request")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $churchNoteRepliesNotifications) {
                    HStack {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text("Church Note Replies")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $weeklyDigest) {
                    HStack {
                        Image(systemName: "newspaper.fill")
                            .foregroundStyle(.brown)
                            .frame(width: 24)
                        Text("Weekly Digest")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $communityUpdates) {
                    HStack {
                        Image(systemName: "megaphone.fill")
                            .foregroundStyle(.pink)
                            .frame(width: 24)
                        Text("Community Updates")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
    }

    private var notificationStyleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTIFICATION STYLE")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $soundEnabled) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: 24)
                        Text("Sound")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $vibrationEnabled) {
                    HStack {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .frame(width: 24)
                        Text("Vibration")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $showPreview) {
                    HStack {
                        Image(systemName: "eye.fill")
                            .frame(width: 24)
                        Text("Show Previews")
                            .font(AMENFont.semiBold(15))
                    }
                }
                .tint(.blue)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Button {
                    showQuietHoursSettings = true
                } label: {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(.indigo)
                            .frame(width: 24)
                        Text("Quiet Hours")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("Choose how you want to be notified")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }

    // MARK: - Sabbath / Sunday Focus Section

    private var sabbathFocusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SABBATH & FOCUS")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { shabbatService.isEnabled },
                    set: { shabbatService.setEnabled($0) }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(.indigo)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sunday Church Focus")
                                .font(AMENFont.semiBold(15))
                            Text("Pause social features on Sundays")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.indigo)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("When enabled, the feed, posting, and social features are gently paused on Sundays so you can focus on worship and community.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }

    // MARK: - Daily Scripture Reminder Section

    private var scriptureReminderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DAILY REMINDER")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $scriptureReminderEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(.teal)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily Scripture Reminder")
                                .font(AMENFont.semiBold(15))
                            Text("A verse delivered to you each morning")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.teal)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .onChange(of: scriptureReminderEnabled) { _, enabled in
                    if enabled {
                        scheduleScriptureReminder(at: scriptureReminderTime)
                    } else {
                        cancelScriptureReminder()
                    }
                }

                if scriptureReminderEnabled {
                    Divider().padding(.leading, 16)

                    Button { showScriptureTimePicker = true } label: {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.teal)
                                .frame(width: 24)
                            Text("Reminder Time")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(scriptureReminderTime, style: .time)
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.32, dampingFraction: 0.80), value: scriptureReminderEnabled)

            Text("Your daily verse is powered by Berean AI — scripture-grounded and personally relevant.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .sheet(isPresented: $showScriptureTimePicker) {
            ScriptureTimePickerSheet(selectedTime: $scriptureReminderTime) {
                scriptureReminderTimeInterval = scriptureReminderTime.timeIntervalSince(
                    Calendar.current.startOfDay(for: scriptureReminderTime)
                )
                if scriptureReminderEnabled {
                    scheduleScriptureReminder(at: scriptureReminderTime)
                }
            }
        }
        .onAppear {
            let midnight = Calendar.current.startOfDay(for: Date())
            scriptureReminderTime = midnight.addingTimeInterval(scriptureReminderTimeInterval)
        }
    }

    // MARK: - Scripture Reminder Scheduling

    private func scheduleScriptureReminder(at time: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["com.amen.dailyScripture"])

        let content = UNMutableNotificationContent()
        content.title = "Your Daily Verse"
        content.body = "Open AMEN to receive today's scripture from Berean."
        content.sound = .default
        content.categoryIdentifier = "DAILY_SCRIPTURE"

        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "com.amen.dailyScripture",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error { dlog("⚠️ Scripture reminder schedule failed: \(error.localizedDescription)") }
            else { dlog("✅ Daily scripture reminder scheduled at \(comps.hour ?? 8):\(String(format: "%02d", comps.minute ?? 0))") }
        }
    }

    private func cancelScriptureReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["com.amen.dailyScripture"])
        dlog("🗑 Daily scripture reminder cancelled")
    }

    // MARK: - Reply Assist Section

    private var replyAssistSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REPLY ASSIST")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $replyAssistEnabled) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .frame(width: 24)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Reply Suggestions")
                                .font(AMENFont.semiBold(15))
                            Text("Smart replies in Dynamic Island for comments and DMs")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.purple)
                .disabled(!notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                Toggle(isOn: $replyAssistShowPreviews) {
                    HStack {
                        Image(systemName: "eye.slash.fill")
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Message Previews")
                                .font(AMENFont.semiBold(15))
                            Text("Show sender name and context snippet on Lock Screen")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.blue)
                .disabled(!replyAssistEnabled || !notificationsEnabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("Reply Assist uses Berean AI to generate scripture-aligned suggestions. Previews are hidden by default for privacy.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
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
                    repliesNotifications = notifSettings["replies"] ?? true
                    followNotifications = notifSettings["follows"] ?? true
                    mentionNotifications = notifSettings["mentions"] ?? true
                    messageNotifications = notifSettings["messages"] ?? true
                    groupNotifications = notifSettings["groups"] ?? true
                    eventNotifications = notifSettings["events"] ?? true
                    prayerRequestNotifications = notifSettings["prayerRequests"] ?? true
                    prayerSupportedNotifications = notifSettings["prayerSupported"] ?? true
                    churchNoteRepliesNotifications = notifSettings["churchNoteReplies"] ?? true
                    weeklyDigest = notifSettings["weeklyDigest"] ?? true
                    communityUpdates = notifSettings["communityUpdates"] ?? true
                    soundEnabled = notifSettings["sound"] ?? true
                    vibrationEnabled = notifSettings["vibration"] ?? true
                    showPreview = notifSettings["showPreview"] ?? true
                    isLoading = false
                }
            } else {
                // No settings doc yet — persist defaults so the next load
                // finds them and doesn't reset the user's future changes.
                await MainActor.run { isLoading = false }
                await saveNotificationSettings()
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            dlog("❌ Error loading notification settings: \(error.localizedDescription)")
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
            "replies": repliesNotifications,
            "follows": followNotifications,
            "mentions": mentionNotifications,
            "messages": messageNotifications,
            "groups": groupNotifications,
            "events": eventNotifications,
            "prayerRequests": prayerRequestNotifications,
            "prayerSupported": prayerSupportedNotifications,
            "churchNoteReplies": churchNoteRepliesNotifications,
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

            dlog("✅ Notification settings saved successfully")
        } catch {
            await MainActor.run {
                isSaving = false
            }
            dlog("❌ Error saving notification settings: \(error.localizedDescription)")
        }
    }
}

// MARK: - ViewModifier for handling notification changes
private struct NotificationChangeModifier: ViewModifier {
    let amensNotifications: Bool
    let commentsNotifications: Bool
    let repliesNotifications: Bool
    let followNotifications: Bool
    let mentionNotifications: Bool
    let messageNotifications: Bool
    let groupNotifications: Bool
    let eventNotifications: Bool
    let prayerRequestNotifications: Bool
    let prayerSupportedNotifications: Bool
    let churchNoteRepliesNotifications: Bool
    let weeklyDigest: Bool
    let communityUpdates: Bool
    let soundEnabled: Bool
    let vibrationEnabled: Bool
    let showPreview: Bool
    let saveAction: () async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: amensNotifications)         { _, _ in Task { await saveAction() } }
            .onChange(of: commentsNotifications)      { _, _ in Task { await saveAction() } }
            .onChange(of: repliesNotifications)       { _, _ in Task { await saveAction() } }
            .onChange(of: followNotifications)        { _, _ in Task { await saveAction() } }
            .onChange(of: mentionNotifications)       { _, _ in Task { await saveAction() } }
            .onChange(of: messageNotifications)       { _, _ in Task { await saveAction() } }
            .modifier(AdditionalNotificationChanges(
                groupNotifications: groupNotifications,
                eventNotifications: eventNotifications,
                prayerRequestNotifications: prayerRequestNotifications,
                prayerSupportedNotifications: prayerSupportedNotifications,
                churchNoteRepliesNotifications: churchNoteRepliesNotifications,
                weeklyDigest: weeklyDigest,
                communityUpdates: communityUpdates,
                soundEnabled: soundEnabled,
                vibrationEnabled: vibrationEnabled,
                showPreview: showPreview,
                saveAction: saveAction
            ))
    }
}

// Additional modifier to split up the onChange chain (SwiftUI limit: ~10 onChange per modifier)
private struct AdditionalNotificationChanges: ViewModifier {
    let groupNotifications: Bool
    let eventNotifications: Bool
    let prayerRequestNotifications: Bool
    let prayerSupportedNotifications: Bool
    let churchNoteRepliesNotifications: Bool
    let weeklyDigest: Bool
    let communityUpdates: Bool
    let soundEnabled: Bool
    let vibrationEnabled: Bool
    let showPreview: Bool
    let saveAction: () async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: groupNotifications)              { _, _ in Task { await saveAction() } }
            .onChange(of: eventNotifications)              { _, _ in Task { await saveAction() } }
            .onChange(of: prayerRequestNotifications)      { _, _ in Task { await saveAction() } }
            .onChange(of: prayerSupportedNotifications)    { _, _ in Task { await saveAction() } }
            .onChange(of: churchNoteRepliesNotifications)  { _, _ in Task { await saveAction() } }
            .onChange(of: weeklyDigest)                    { _, _ in Task { await saveAction() } }
            .onChange(of: communityUpdates)                { _, _ in Task { await saveAction() } }
            .onChange(of: soundEnabled)                    { _, _ in Task { await saveAction() } }
            .onChange(of: vibrationEnabled)                { _, _ in Task { await saveAction() } }
            .onChange(of: showPreview)                     { _, _ in Task { await saveAction() } }
    }
}

// MARK: - Scripture Time Picker Sheet

private struct ScriptureTimePickerSheet: View {
    @Binding var selectedTime: Date
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Reminder Time",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
            }
            .navigationTitle("Daily Reminder Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onConfirm()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    NavigationStack {
        NotificationsSettingsView()
            .environmentObject(AuthenticationViewModel())
    }
}
