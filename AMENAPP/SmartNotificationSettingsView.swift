import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Settings UI for Smart Notification system
struct SmartNotificationSettingsView: View {
    @StateObject private var viewModel = NotificationSettingsViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {

                    // MARK: - MASTER SWITCH
                    Text("MASTER SWITCH")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Toggle("Push Notifications", isOn: $viewModel.masterPushEnabled)
                            .font(AMENFont.semiBold(15))
                            .tint(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text(viewModel.masterPushEnabled
                         ? "You will receive push notifications per your settings below."
                         : "All push notifications are disabled. You will still see notifications in the app.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if viewModel.masterPushEnabled {

                        // MARK: - NOTIFICATION STYLE
                        Text("NOTIFICATION STYLE")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            Picker("Notification Style", selection: $viewModel.preferences.mode) {
                                Text("Meaningful Only").tag(SmartNotificationPreferences.NotificationMode.meaningful)
                                Text("Balanced").tag(SmartNotificationPreferences.NotificationMode.balanced)
                                Text("Everything").tag(SmartNotificationPreferences.NotificationMode.everything)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            Text(modeDescription)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        Text("Controls how many notifications you receive. Meaningful Only shows only what matters.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // MARK: - BY TYPE
                        Text("BY TYPE")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            let editableCategories = NotificationCategory.allCases.filter { $0 != .crisisAlerts }
                            ForEach(Array(editableCategories.enumerated()), id: \.element) { index, category in
                                QuickCategoryToggleRow(
                                    category: category,
                                    setting: viewModel.bindingSetting(for: category)
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                Divider().padding(.leading, 16)
                            }

                            // Crisis alerts — always on, non-editable
                            HStack {
                                Label("Crisis Alerts", systemImage: "exclamationmark.shield.fill")
                                    .foregroundColor(.red)
                                    .font(AMENFont.semiBold(15))
                                Spacer()
                                Text("Always On")
                                    .font(AMENFont.regular(13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        Text("Tap a type for push, sound, and badge options.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    // MARK: - PRIVACY
                    Text("PRIVACY")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Picker("Lock Screen Privacy", selection: $viewModel.preferences.lockScreenPrivacy) {
                            Text("Show Full Content").tag(SmartNotificationPreferences.LockScreenPrivacy.full)
                            Text("Hide Content").tag(SmartNotificationPreferences.LockScreenPrivacy.minimal)
                            Text("Hide Name & Content").tag(SmartNotificationPreferences.LockScreenPrivacy.nameOnly)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Text(privacyDescription)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Controls what's visible on your lock screen.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: - QUIET TIMES
                    Text("QUIET TIMES")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Toggle("Enable Quiet Hours", isOn: Binding(
                            get: { viewModel.quietHoursEnabled },
                            set: { viewModel.quietHoursEnabled = $0 }
                        ))
                        .font(AMENFont.semiBold(15))
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if viewModel.quietHoursEnabled {
                            Divider().padding(.leading, 16)

                            Button(action: { viewModel.showStartTimePicker = true }) {
                                HStack {
                                    Text("Start Time")
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(viewModel.quietHoursStart)
                                        .font(AMENFont.regular(15))
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider().padding(.leading, 16)

                            Button(action: { viewModel.showEndTimePicker = true }) {
                                HStack {
                                    Text("End Time")
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(viewModel.quietHoursEnd)
                                        .font(AMENFont.regular(15))
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider().padding(.leading, 16)

                            Toggle("Allow DMs during quiet hours", isOn: $viewModel.allowDMsDuringQuiet)
                                .font(AMENFont.regular(15))
                                .tint(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                            Divider().padding(.leading, 16)
                        }

                        Toggle("Sunday Mode", isOn: $viewModel.preferences.sundayMode)
                            .font(AMENFont.semiBold(15))
                            .tint(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Text("Extra quiet on Sundays for worship and rest")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Only crisis alerts (and optionally DMs) arrive during quiet hours.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: - NOTIFICATION BUNDLING
                    Text("NOTIFICATION BUNDLING")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Picker("Digest Frequency", selection: $viewModel.preferences.digestCadence) {
                            Text("Realtime").tag(SmartNotificationPreferences.DigestCadence.realtime)
                            Text("Twice Daily").tag(SmartNotificationPreferences.DigestCadence.twiceDaily)
                            Text("Daily Summary").tag(SmartNotificationPreferences.DigestCadence.daily)
                            Text("Weekly Summary").tag(SmartNotificationPreferences.DigestCadence.weekly)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Text(digestDescription)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Low-priority notifications (likes, follows) bundled into summaries to reduce noise.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: - AI SUMMARY
                    Text("AI SUMMARY")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Toggle("AI Activity Summary", isOn: $viewModel.aiSummaryEnabled)
                            .font(AMENFont.semiBold(15))
                            .tint(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        if viewModel.aiSummaryEnabled {
                            Divider().padding(.leading, 16)

                            Picker("Frequency", selection: $viewModel.aiSummaryFrequency) {
                                Text("Smart (activity-based)").tag("smart")
                                Text("Daily Digest").tag("daily")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            Text("\"Today: 3 replies, 12 likes, 2 new followers\" — one item per window.")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Opt-in. A single summary notification replaces a flood of individual alerts when you have many notifications.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: - ADVANCED
                    Text("ADVANCED")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        NavigationLink(destination: NotificationCategorySettingsView(preferences: $viewModel.preferences)) {
                            HStack {
                                Text("Customize by Category")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: - SUGGESTED MUTES
                    if !viewModel.muteSuggestions.isEmpty {
                        Text("SUGGESTED MUTES")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.muteSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                MuteSuggestionRow(
                                    suggestion: suggestion,
                                    onApply: { Task { await viewModel.applySuggestion(suggestion) } },
                                    onDismiss: { viewModel.dismissSuggestion(suggestion.id) }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                if index < viewModel.muteSuggestions.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        Text("Based on your activity patterns")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task {
                            await viewModel.savePreferences()
                            dismiss()
                        }
                    }
                    .font(AMENFont.semiBold(16))
                }
            }
            .sheet(isPresented: $viewModel.showStartTimePicker) {
                TimePickerSheet(title: "Start Time", selectedTime: $viewModel.quietHoursStart)
            }
            .sheet(isPresented: $viewModel.showEndTimePicker) {
                TimePickerSheet(title: "End Time", selectedTime: $viewModel.quietHoursEnd)
            }
            .task {
                await viewModel.loadPreferences()
                await viewModel.loadMuteSuggestions()
            }
        }
    }

    private var modeDescription: String {
        switch viewModel.preferences.mode {
        case .meaningful:
            return "Only notifications that matter: direct messages, replies with questions, prayer updates"
        case .balanced:
            return "Important notifications plus some social activity"
        case .everything:
            return "All activity and interactions"
        }
    }

    private var privacyDescription: String {
        switch viewModel.preferences.lockScreenPrivacy {
        case .full:
            return "\"Jordan: Hey, are you free tomorrow?\""
        case .minimal:
            return "\"You have a message from Jordan\""
        case .nameOnly:
            return "\"You have a new message\""
        }
    }

    private var digestDescription: String {
        switch viewModel.preferences.digestCadence {
        case .realtime:
            return "No bundling - receive notifications as they happen"
        case .twiceDaily:
            return "Morning (9 AM) and evening (6 PM) summaries"
        case .daily:
            return "One summary each morning at 9 AM"
        case .weekly:
            return "Weekly summary every Sunday at 9 AM"
        }
    }
}

// MARK: - Quick Per-Type Toggle Row (shown inline on main settings screen)

struct QuickCategoryToggleRow: View {
    let category: NotificationCategory
    @Binding var setting: SmartNotificationPreferences.CategorySetting

    var body: some View {
        HStack {
            Label(category.displayName, systemImage: categoryIcon)
                .font(AMENFont.semiBold(15))
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(
                get: { setting.mode != .off },
                set: { enabled in
                    setting.mode = enabled ? category.defaultSetting.mode : .off
                    if enabled { setting.pushEnabled = category.defaultSetting.pushEnabled }
                }
            ))
            .labelsHidden()
            .tint(.blue)
        }
    }

    private var categoryIcon: String {
        switch category {
        case .directMessages:  return "message.fill"
        case .replies:         return "arrowshape.turn.up.left.fill"
        case .mentions:        return "at"
        case .reactions:       return "heart.fill"
        case .follows:         return "person.badge.plus"
        case .prayerUpdates:   return "hands.sparkles.fill"
        case .churchNotes:     return "note.text"
        case .reposts:         return "arrow.2.squarepath"
        case .groupMessages:   return "person.3.fill"
        case .crisisAlerts:    return "exclamationmark.shield.fill"
        }
    }
}

// MARK: - Category Settings View

struct NotificationCategorySettingsView: View {
    @Binding var preferences: SmartNotificationPreferences

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                let categories = NotificationCategory.allCases.filter { $0 != .crisisAlerts }

                VStack(spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        NotificationCategoryRow(
                            category: category,
                            setting: bindingSetting(for: category)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < categories.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("By Category")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bindingSetting(for category: NotificationCategory) -> Binding<SmartNotificationPreferences.CategorySetting> {
        Binding(
            get: {
                preferences.categorySettings[category] ?? category.defaultSetting
            },
            set: { newValue in
                preferences.categorySettings[category] = newValue
            }
        )
    }
}

struct NotificationCategoryRow: View {
    let category: NotificationCategory
    @Binding var setting: SmartNotificationPreferences.CategorySetting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.displayName)
                    .font(AMENFont.semiBold(15))
                Spacer()
                Picker("", selection: $setting.mode) {
                    Text("Off").tag(SmartNotificationPreferences.CategorySetting.CategoryMode.off)
                    Text("Meaningful").tag(SmartNotificationPreferences.CategorySetting.CategoryMode.meaningful)
                    Text("Balanced").tag(SmartNotificationPreferences.CategorySetting.CategoryMode.balanced)
                    Text("All").tag(SmartNotificationPreferences.CategorySetting.CategoryMode.everything)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if setting.mode != .off {
                HStack(spacing: 16) {
                    Toggle("Push", isOn: $setting.pushEnabled)
                        .toggleStyle(.button)
                        .controlSize(.small)

                    Toggle("Sound", isOn: $setting.soundEnabled)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .disabled(!setting.pushEnabled)

                    Toggle("Badge", isOn: $setting.badgeEnabled)
                        .toggleStyle(.button)
                        .controlSize(.small)
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Mute Suggestion Row

struct MuteSuggestionRow: View {
    let suggestion: MuteSuggestion
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(.orange)
                    .font(.systemScaled(20))

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.displayMessage)
                        .font(AMENFont.semiBold(14))

                    if let spike = suggestion.activitySpike {
                        Text("\(Int(spike.currentRate))x normal activity")
                            .font(AMENFont.regular(12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            HStack {
                Button("Mute") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var iconName: String {
        switch suggestion.reason {
        case .activitySpike: return "bell.badge"
        case .repeatedNotifications: return "bell.and.waves.left.and.right"
        case .offHours: return "moon"
        case .lowEngagement: return "bubble.left"
        }
    }
}

// MARK: - Time Picker Sheet

struct TimePickerSheet: View {
    let title: String
    @Binding var selectedTime: String
    @Environment(\.dismiss) var dismiss

    @State private var date: Date = Date()

    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        selectedTime = formatter.string(from: date)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            if let parsedDate = formatter.date(from: selectedTime) {
                date = parsedDate
            }
        }
    }
}

// MARK: - View Model

@MainActor
class NotificationSettingsViewModel: ObservableObject {
    @Published var preferences = SmartNotificationPreferences()
    @Published var muteSuggestions: [MuteSuggestion] = []
    @Published var showStartTimePicker = false
    @Published var showEndTimePicker = false

    // Master push toggle (stored separately so it survives preference reloads)
    @Published var masterPushEnabled: Bool = true
    // Allow DMs to bypass quiet hours
    @Published var allowDMsDuringQuiet: Bool = true
    // AI summary opt-in + frequency
    @Published var aiSummaryEnabled: Bool = false
    @Published var aiSummaryFrequency: String = "smart"

    // MARK: Quiet-hours computed bindings

    var quietHoursEnabled: Bool {
        get { preferences.quietHours?.enabled ?? false }
        set {
            if newValue {
                if preferences.quietHours == nil {
                    preferences.quietHours = SmartNotificationPreferences.QuietHours(
                        startTime: "22:00", endTime: "08:00", enabled: true
                    )
                } else {
                    preferences.quietHours?.enabled = true
                }
            } else {
                preferences.quietHours?.enabled = false
            }
        }
    }

    var quietHoursStart: String {
        get { preferences.quietHours?.startTime ?? "22:00" }
        set { preferences.quietHours?.startTime = newValue }
    }

    var quietHoursEnd: String {
        get { preferences.quietHours?.endTime ?? "08:00" }
        set { preferences.quietHours?.endTime = newValue }
    }

    // MARK: Per-category binding (used by both quick-toggle row and full settings)

    func bindingSetting(for category: NotificationCategory) -> Binding<SmartNotificationPreferences.CategorySetting> {
        Binding(
            get: { [weak self] in
                self?.preferences.categorySettings[category] ?? category.defaultSetting
            },
            set: { [weak self] newValue in
                self?.preferences.categorySettings[category] = newValue
            }
        )
    }

    // MARK: Persistence

    private lazy var db = Firestore.firestore()

    func loadPreferences() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let doc = try? await db.collection("users").document(userId)
            .collection("settings").document("notifications").getDocument()

        guard let data = doc?.data() else { return }

        // Decode main preferences struct
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let prefs = try? JSONDecoder().decode(SmartNotificationPreferences.self, from: jsonData) {
            self.preferences = prefs
        }

        // Load extra fields stored alongside the preferences doc
        masterPushEnabled    = data["masterPushEnabled"]    as? Bool   ?? true
        allowDMsDuringQuiet  = data["allowDMsDuringQuiet"]  as? Bool   ?? true
        aiSummaryEnabled     = data["aiSummaryEnabled"]     as? Bool   ?? false
        aiSummaryFrequency   = data["aiSummaryFrequency"]   as? String ?? "smart"
    }

    func savePreferences() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(preferences),
              var dictionary = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }

        // Merge extra fields
        dictionary["masterPushEnabled"]   = masterPushEnabled
        dictionary["allowDMsDuringQuiet"] = allowDMsDuringQuiet
        dictionary["aiSummaryEnabled"]    = aiSummaryEnabled
        dictionary["aiSummaryFrequency"]  = aiSummaryFrequency

        try? await db.collection("users").document(userId)
            .collection("settings").document("notifications")
            .setData(dictionary, merge: true)
    }

    func loadMuteSuggestions() async {
        await SmartMuteService.shared.loadSuggestions()
        self.muteSuggestions = SmartMuteService.shared.suggestions
    }

    func applySuggestion(_ suggestion: MuteSuggestion) async {
        try? await SmartMuteService.shared.applySuggestion(suggestion)
        self.muteSuggestions = SmartMuteService.shared.suggestions
    }

    func dismissSuggestion(_ suggestionId: String) {
        SmartMuteService.shared.dismissSuggestion(suggestionId)
        self.muteSuggestions = SmartMuteService.shared.suggestions
    }
}

#Preview {
    SmartNotificationSettingsView()
}
