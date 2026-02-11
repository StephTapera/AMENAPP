//
//  PrayerReminderSettingsView.swift
//  AMENAPP
//
//  Created by Assistant on 2/2/26.
//
//  Settings view for managing prayer reminder notifications
//

import SwiftUI
import UserNotifications

struct PrayerReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationManager = PushNotificationManager.shared
    
    @State private var remindersEnabled = false
    @State private var selectedReminderStyle: ReminderStyle = .standard
    @State private var customReminders: [CustomReminder] = []
    @State private var showingAddReminder = false
    @State private var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var scheduledRemindersCount = 0
    
    enum ReminderStyle: String, CaseIterable {
        case standard = "Standard (8 daily)"
        case minimal = "Minimal (3 daily)"
        case custom = "Custom"
        case off = "Off"
        
        var description: String {
            switch self {
            case .standard:
                return "Receive 8 prayer reminders throughout the day with Bible verses"
            case .minimal:
                return "Receive 3 prayer reminders: morning, afternoon, and evening"
            case .custom:
                return "Create your own custom prayer reminder schedule"
            case .off:
                return "No automatic prayer reminders"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Card
                        headerCard
                        
                        // Permission Status
                        if notificationPermissionStatus != .authorized {
                            permissionCard
                        }
                        
                        // Reminder Style Selection
                        reminderStyleSection
                        
                        // Scheduled Reminders Preview
                        if remindersEnabled && selectedReminderStyle != .off {
                            scheduledRemindersSection
                        }
                        
                        // Custom Reminders
                        if selectedReminderStyle == .custom {
                            customRemindersSection
                        }
                        
                        // Verse of the Day
                        verseOfTheDaySection
                        
                        // Info Section
                        infoSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Prayer Reminders")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .sheet(isPresented: $showingAddReminder) {
                AddCustomReminderView { reminder in
                    customReminders.append(reminder)
                    scheduleCustomReminder(reminder)
                }
            }
            .alert("Enable Notifications", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("To receive prayer reminders, please enable notifications in Settings.")
            }
            .task {
                await loadSettings()
            }
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Stay Connected")
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(.primary)
            
            Text("Set up prayer reminders to help you stay connected with God throughout your day")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Permission Card
    
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Notifications Disabled")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
            }
            
            Text("To receive prayer reminders, you need to enable notifications for AMENAPP.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            Button {
                Task {
                    let granted = await notificationManager.requestNotificationPermissions()
                    if granted {
                        await checkNotificationPermissions()
                    } else {
                        showingPermissionAlert = true
                    }
                }
            } label: {
                Text("Enable Notifications")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Reminder Style Section
    
    private var reminderStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminder Style")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                ForEach(ReminderStyle.allCases, id: \.self) { style in
                    ReminderStyleCard(
                        style: style,
                        isSelected: selectedReminderStyle == style
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedReminderStyle = style
                            applyReminderStyle(style)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Scheduled Reminders Section
    
    private var scheduledRemindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Reminders")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(scheduledRemindersCount)")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                if selectedReminderStyle == .standard {
                    standardRemindersPreview
                } else if selectedReminderStyle == .minimal {
                    minimalRemindersPreview
                }
            }
        }
    }
    
    private var standardRemindersPreview: some View {
        VStack(spacing: 8) {
            ReminderTimeRow(time: "6:00 AM", title: "Rise and Shine!", icon: "sunrise.fill", color: .orange)
            ReminderTimeRow(time: "8:00 AM", title: "Morning Prayer", icon: "hands.sparkles", color: .blue)
            ReminderTimeRow(time: "10:00 AM", title: "Trust in Him", icon: "heart.fill", color: .pink)
            ReminderTimeRow(time: "12:00 PM", title: "Midday Devotional", icon: "book.fill", color: .purple)
            ReminderTimeRow(time: "3:00 PM", title: "Prayer Break", icon: "pause.circle.fill", color: .green)
            ReminderTimeRow(time: "6:00 PM", title: "Give Thanks", icon: "hand.raised.fill", color: .yellow)
            ReminderTimeRow(time: "8:00 PM", title: "Evening Reflection", icon: "moon.fill", color: .indigo)
            ReminderTimeRow(time: "9:30 PM", title: "Rest in Peace", icon: "moon.stars.fill", color: .blue)
        }
    }
    
    private var minimalRemindersPreview: some View {
        VStack(spacing: 8) {
            ReminderTimeRow(time: "7:00 AM", title: "Morning Verse", icon: "sunrise.fill", color: .orange)
            ReminderTimeRow(time: "2:00 PM", title: "Stay Connected", icon: "heart.fill", color: .pink)
            ReminderTimeRow(time: "7:00 PM", title: "Evening Blessing", icon: "moon.fill", color: .indigo)
        }
    }
    
    // MARK: - Custom Reminders Section
    
    private var customRemindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Reminders")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
            
            if customReminders.isEmpty {
                Button {
                    showingAddReminder = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                        
                        Text("Add Custom Reminder")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            )
                    )
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(customReminders) { reminder in
                        CustomReminderRow(reminder: reminder) {
                            deleteCustomReminder(reminder)
                        }
                    }
                    
                    Button {
                        showingAddReminder = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Another")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Verse of the Day Section
    
    private var verseOfTheDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verse of the Day")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
            
            let verse = notificationManager.getVerseOfTheDay()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                    
                    Text("Today's Verse")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                }
                
                Text("\"\(verse.text)\"")
                    .font(.custom("OpenSans-Italic", size: 15))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                
                Text("— \(verse.reference)")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                Divider()
                
                Text("Receive daily Bible verses at 9:00 AM")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("About Prayer Reminders")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "bell.fill", text: "Reminders include inspirational Bible verses")
                InfoRow(icon: "calendar", text: "Verses rotate daily based on a 30-day cycle")
                InfoRow(icon: "moon.zzz.fill", text: "Do Not Disturb respects your device settings")
                InfoRow(icon: "gear", text: "Manage notification settings in iOS Settings")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Functions
    
    private func loadSettings() async {
        await checkNotificationPermissions()
        await loadScheduledReminders()
        
        // Load saved preferences (you can persist these to UserDefaults)
        remindersEnabled = await notificationManager.areDailyRemindersScheduled()
        
        if remindersEnabled {
            selectedReminderStyle = .standard
        } else {
            selectedReminderStyle = .off
        }
    }
    
    private func checkNotificationPermissions() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationPermissionStatus = settings.authorizationStatus
    }
    
    private func loadScheduledReminders() async {
        let reminders = await notificationManager.getScheduledReminders()
        scheduledRemindersCount = reminders.count
    }
    
    private func applyReminderStyle(_ style: ReminderStyle) {
        Task {
            // Check permissions first
            if notificationPermissionStatus != .authorized {
                let granted = await notificationManager.requestNotificationPermissions()
                if !granted {
                    showingPermissionAlert = true
                    selectedReminderStyle = .off
                    return
                }
            }
            
            switch style {
            case .standard:
                await notificationManager.scheduleDailyReminders()
                await notificationManager.scheduleVerseOfTheDayNotification()
                remindersEnabled = true
                
            case .minimal:
                await notificationManager.scheduleRemindersWithRotatingVerses()
                await notificationManager.scheduleVerseOfTheDayNotification()
                remindersEnabled = true
                
            case .custom:
                await notificationManager.cancelDailyReminders()
                // Keep verse of the day
                await notificationManager.scheduleVerseOfTheDayNotification()
                remindersEnabled = true
                
            case .off:
                await notificationManager.cancelDailyReminders()
                remindersEnabled = false
            }
            
            await loadScheduledReminders()
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            print("✅ Reminder style changed to: \(style.rawValue)")
        }
    }
    
    private func scheduleCustomReminder(_ reminder: CustomReminder) {
        Task {
            await notificationManager.scheduleCustomReminder(
                identifier: "custom_\(reminder.id.uuidString)",
                title: reminder.title,
                body: reminder.message,
                hour: reminder.hour,
                minute: reminder.minute,
                repeats: reminder.repeatsDaily
            )
            
            await loadScheduledReminders()
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    }
    
    private func deleteCustomReminder(_ reminder: CustomReminder) {
        withAnimation {
            customReminders.removeAll { $0.id == reminder.id }
        }
        
        // Cancel notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["custom_\(reminder.id.uuidString)"]
        )
        
        Task {
            await loadScheduledReminders()
        }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
    }
}

// MARK: - Supporting Views

struct ReminderStyleCard: View {
    let style: PrayerReminderSettingsView.ReminderStyle
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.rawValue)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(style.description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.blue : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ReminderTimeRow: View {
    let time: String
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(time)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Custom Reminder Models

struct CustomReminder: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var hour: Int
    var minute: Int
    var repeatsDaily: Bool = true
}

struct CustomReminderRow: View {
    let reminder: CustomReminder
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(reminder.message)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(String(format: "%d:%02d %@",
                       reminder.hour > 12 ? reminder.hour - 12 : (reminder.hour == 0 ? 12 : reminder.hour),
                       reminder.minute,
                       reminder.hour >= 12 ? "PM" : "AM"))
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Add Custom Reminder View

struct AddCustomReminderView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (CustomReminder) -> Void
    
    @State private var title = ""
    @State private var message = ""
    @State private var selectedDate = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.custom("OpenSans-Regular", size: 16))
                    
                    TextField("Message", text: $message, axis: .vertical)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .lineLimit(3...5)
                } header: {
                    Text("Reminder Details")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                
                Section {
                    DatePicker("Time", selection: $selectedDate, displayedComponents: .hourAndMinute)
                        .font(.custom("OpenSans-Regular", size: 16))
                } header: {
                    Text("Reminder Time")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-Regular", size: 16))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveReminder()
                    }
                    .font(.custom("OpenSans-Bold", size: 16))
                    .disabled(title.isEmpty || message.isEmpty)
                }
            }
        }
    }
    
    private func saveReminder() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedDate)
        
        let reminder = CustomReminder(
            title: title,
            message: message,
            hour: components.hour ?? 9,
            minute: components.minute ?? 0
        )
        
        onSave(reminder)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    PrayerReminderSettingsView()
}
