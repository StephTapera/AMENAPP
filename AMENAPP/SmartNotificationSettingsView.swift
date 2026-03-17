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
            Form {
                // MARK: Master Push Toggle
                Section {
                    Toggle("Push Notifications", isOn: $viewModel.masterPushEnabled)
                } header: {
                    Text("Master Switch")
                } footer: {
                    Text(viewModel.masterPushEnabled
                         ? "You will receive push notifications per your settings below."
                         : "All push notifications are disabled. You will still see notifications in the app.")
                }

                // MARK: Notification Style
                if viewModel.masterPushEnabled {
                    Section {
                        Picker("Notification Style", selection: $viewModel.preferences.mode) {
                            Text("Meaningful Only").tag(SmartNotificationPreferences.NotificationMode.meaningful)
                            Text("Balanced").tag(SmartNotificationPreferences.NotificationMode.balanced)
                            Text("Everything").tag(SmartNotificationPreferences.NotificationMode.everything)
                        }
                        .pickerStyle(.segmented)

                        Text(modeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Notification Style")
                    } footer: {
                        Text("Controls how many notifications you receive. Meaningful Only shows only what matters.")
                    }

                    // MARK: Per-Type Quick Toggles
                    Section {
                        ForEach(NotificationCategory.allCases, id: \.self) { category in
                            if category != .crisisAlerts {
                                QuickCategoryToggleRow(
                                    category: category,
                                    setting: viewModel.bindingSetting(for: category)
                                )
                            }
                        }
                        // Crisis alerts — always on, non-editable
                        HStack {
                            Label("Crisis Alerts", systemImage: "exclamationmark.shield.fill")
                                .foregroundColor(.red)
                            Spacer()
                            Text("Always On")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("By Type")
                    } footer: {
                        Text("Tap a type for push, sound, and badge options.")
                    }
                }

                // MARK: Lock Screen Privacy
                Section {
                    Picker("Lock Screen Privacy", selection: $viewModel.preferences.lockScreenPrivacy) {
                        Text("Show Full Content").tag(SmartNotificationPreferences.LockScreenPrivacy.full)
                        Text("Hide Content").tag(SmartNotificationPreferences.LockScreenPrivacy.minimal)
                        Text("Hide Name & Content").tag(SmartNotificationPreferences.LockScreenPrivacy.nameOnly)
                    }

                    Text(privacyDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Controls what's visible on your lock screen.")
                }

                // MARK: Quiet Hours
                Section {
                    Toggle("Enable Quiet Hours", isOn: $viewModel.quietHoursEnabled)

                    if viewModel.quietHoursEnabled {
                        HStack {
                            Text("Start Time")
                            Spacer()
                            Text(viewModel.quietHoursStart)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.showStartTimePicker = true }

                        HStack {
                            Text("End Time")
                            Spacer()
                            Text(viewModel.quietHoursEnd)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.showEndTimePicker = true }

                        Toggle("Allow DMs during quiet hours", isOn: $viewModel.allowDMsDuringQuiet)
                            .font(.subheadline)
                    }

                    Toggle("Sunday Mode", isOn: $viewModel.preferences.sundayMode)

                    Text("Extra quiet on Sundays for worship and rest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Quiet Times")
                } footer: {
                    Text("Only crisis alerts (and optionally DMs) arrive during quiet hours.")
                }

                // MARK: Digest / Rollup
                Section {
                    Picker("Digest Frequency", selection: $viewModel.preferences.digestCadence) {
                        Text("Realtime").tag(SmartNotificationPreferences.DigestCadence.realtime)
                        Text("Twice Daily").tag(SmartNotificationPreferences.DigestCadence.twiceDaily)
                        Text("Daily Summary").tag(SmartNotificationPreferences.DigestCadence.daily)
                        Text("Weekly Summary").tag(SmartNotificationPreferences.DigestCadence.weekly)
                    }

                    Text(digestDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Notification Bundling")
                } footer: {
                    Text("Low-priority notifications (likes, follows) bundled into summaries to reduce noise.")
                }

                // MARK: AI Summary
                Section {
                    Toggle("AI Activity Summary", isOn: $viewModel.aiSummaryEnabled)

                    if viewModel.aiSummaryEnabled {
                        Picker("Frequency", selection: $viewModel.aiSummaryFrequency) {
                            Text("Smart (activity-based)").tag("smart")
                            Text("Daily Digest").tag("daily")
                        }
                        Text("\"Today: 3 replies, 12 likes, 2 new followers\" — one item per window.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("AI Summary")
                } footer: {
                    Text("Opt-in. A single summary notification replaces a flood of individual alerts when you have many notifications.")
                }

                // MARK: Advanced (full per-category config)
                Section {
                    NavigationLink("Customize by Category") {
                        NotificationCategorySettingsView(preferences: $viewModel.preferences)
                    }
                } header: {
                    Text("Advanced")
                }

                // MARK: Smart Mute Suggestions
                if !viewModel.muteSuggestions.isEmpty {
                    Section {
                        ForEach(viewModel.muteSuggestions) { suggestion in
                            MuteSuggestionRow(
                                suggestion: suggestion,
                                onApply: { Task { await viewModel.applySuggestion(suggestion) } },
                                onDismiss: { viewModel.dismissSuggestion(suggestion.id) }
                            )
                        }
                    } header: {
                        Text("Suggested Mutes")
                    } footer: {
                        Text("Based on your activity patterns")
                    }
                }
            }
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
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(
                get: { setting.mode != .off },
                set: { enabled in
                    setting.mode = enabled ? category.defaultSetting.mode : .off
                    if enabled { setting.pushEnabled = category.defaultSetting.pushEnabled }
                }
            ))
            .labelsHidden()
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
        Form {
            ForEach(NotificationCategory.allCases, id: \.self) { category in
                if category != .crisisAlerts {
                    NotificationCategoryRow(
                        category: category,
                        setting: bindingSetting(for: category)
                    )
                }
            }
        }
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
                    .font(.headline)
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
        .padding(.vertical, 4)
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
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.displayMessage)
                        .font(.subheadline)
                    
                    if let spike = suggestion.activitySpike {
                        Text("\(Int(spike.currentRate))x normal activity")
                            .font(.caption)
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
        .padding(.vertical, 4)
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
            // Parse current time
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

    private let db = Firestore.firestore()

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
