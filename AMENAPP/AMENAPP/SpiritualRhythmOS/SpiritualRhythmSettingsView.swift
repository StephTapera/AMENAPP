// SpiritualRhythmSettingsView.swift
// AMENAPP — SpiritualRhythmOS
//
// Settings surface for rhythm tracking, notifications, and Sabbath mode.
// White background, native controls, grace-based language throughout.
// No shame, no gamification pressure.

import SwiftUI

// MARK: - SpiritualRhythmSettingsView

struct SpiritualRhythmSettingsView: View {
    @StateObject private var service = SpiritualRhythmOSService.shared

    var body: some View {
        List {
            activeRhythmsSection
            remindersSection
            notificationIntensitySection
            notificationTypesSection
            sabbathModeSection
            wellbeingSection
            aboutYourRhythmSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Your Rhythm")
        .navigationBarTitleDisplayMode(.large)
        .task { service.startListening() }
    }

    // MARK: - Section 1: Active Rhythms

    private var activeRhythmsSection: some View {
        Section {
            ForEach(SpiritualStreakType.allCases, id: \.rawValue) { type in
                StreakTypeToggleRow(type: type, service: service)
            }
        } header: {
            Text("Active Rhythms")
        } footer: {
            Text("Track only what matters to you. No pressure.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Section 2: Reminders

    private var remindersSection: some View {
        Section {
            DatePicker(
                "Daily Verse Time",
                selection: verseTimeBinding,
                displayedComponents: [.hourAndMinute]
            )
            DatePicker(
                "Evening Reminder",
                selection: reminderTimeBinding,
                displayedComponents: [.hourAndMinute]
            )
            Toggle(
                "Morning Digest",
                isOn: Binding(
                    get: { service.settings.notificationPreferences.morningDigestEnabled },
                    set: { newValue in
                        service.settings.notificationPreferences.morningDigestEnabled = newValue
                        Task { await service.updateNotificationPreferences(service.settings.notificationPreferences) }
                    }
                )
            )
            Toggle(
                "Evening Digest",
                isOn: Binding(
                    get: { service.settings.notificationPreferences.eveningDigestEnabled },
                    set: { newValue in
                        service.settings.notificationPreferences.eveningDigestEnabled = newValue
                        Task { await service.updateNotificationPreferences(service.settings.notificationPreferences) }
                    }
                )
            )
        } header: {
            Text("Reminders")
        }
    }

    // MARK: - Section 3: Notification Intensity

    private var notificationIntensitySection: some View {
        Section {
            Picker(
                "Notifications",
                selection: Binding(
                    get: { service.settings.notificationPreferences.intensity },
                    set: { newValue in
                        service.settings.notificationPreferences.intensity = newValue
                        Task { await service.updateNotificationPreferences(service.settings.notificationPreferences) }
                    }
                )
            ) {
                ForEach(SpiritualNotificationIntensityMode.allCases, id: \.rawValue) { mode in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                        Text(mode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("Notification Intensity")
        } footer: {
            Text("Controls how often Amen sends you reminders.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Section 4: Notification Types

    private var notificationTypesSection: some View {
        Section {
            ForEach(visibleNotificationCategories, id: \.rawValue) { category in
                Toggle(
                    category.humanReadableName,
                    isOn: notificationCategoryBinding(for: category)
                )
            }
        } header: {
            Text("Notification Types")
        }
    }

    private var visibleNotificationCategories: [SpiritualNotificationCategory] {
        // quietReturn is system-managed — never shown to the user
        SpiritualNotificationCategory.allCases.filter { $0 != .quietReturn }
    }

    private func notificationCategoryBinding(for category: SpiritualNotificationCategory) -> Binding<Bool> {
        Binding(
            get: { service.settings.notificationPreferences.enabledCategories.contains(category) },
            set: { enabled in
                if enabled {
                    service.settings.notificationPreferences.enabledCategories.insert(category)
                } else {
                    service.settings.notificationPreferences.enabledCategories.remove(category)
                }
                Task { await service.updateNotificationPreferences(service.settings.notificationPreferences) }
            }
        )
    }

    // MARK: - Section 5: Sabbath Mode

    private var sabbathModeSection: some View {
        Section {
            Toggle(
                "Sabbath Mode",
                isOn: Binding(
                    get: { service.settings.sabbathMode.enabled },
                    set: { enabled in
                        service.settings.sabbathMode.enabled = enabled
                        if enabled {
                            Task { await service.enableSabbathMode(service.settings.sabbathMode) }
                        } else {
                            Task { await service.disableSabbathMode() }
                        }
                    }
                )
            )

            if service.settings.sabbathMode.enabled {
                Picker(
                    "Starts",
                    selection: Binding(
                        get: { service.settings.sabbathMode.startDay },
                        set: { service.settings.sabbathMode.startDay = $0 }
                    )
                ) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        Text(weekdayName(for: dayIndex)).tag(dayIndex)
                    }
                }

                Picker(
                    "Starts at",
                    selection: Binding(
                        get: { service.settings.sabbathMode.startHour },
                        set: { newValue in
                            service.settings.sabbathMode.startHour = newValue
                            Task { await service.enableSabbathMode(service.settings.sabbathMode) }
                        }
                    )
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hourLabel(for: hour)).tag(hour)
                    }
                }

                Picker(
                    "Ends",
                    selection: Binding(
                        get: { service.settings.sabbathMode.endDay },
                        set: { service.settings.sabbathMode.endDay = $0 }
                    )
                ) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        Text(weekdayName(for: dayIndex)).tag(dayIndex)
                    }
                }

                Picker(
                    "Ends at",
                    selection: Binding(
                        get: { service.settings.sabbathMode.endHour },
                        set: { newValue in
                            service.settings.sabbathMode.endHour = newValue
                            Task { await service.enableSabbathMode(service.settings.sabbathMode) }
                        }
                    )
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hourLabel(for: hour)).tag(hour)
                    }
                }
            }
        } header: {
            Text("Sabbath Mode")
        } footer: {
            Text("During Sabbath, notifications and social features are paused. You choose the window.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Section 6: About Your Rhythm

    private var aboutYourRhythmSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(service.settings.momentumState.displayName)
                    .font(.headline)
                Text(service.settings.momentumState.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            Text("About Your Rhythm")
        } footer: {
            Text("Your spiritual momentum is private. It's here to encourage, not to grade you.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Time Bindings

    /// Converts the stored HH:mm String to a Date for DatePicker, and back.
    private var verseTimeBinding: Binding<Date> {
        Binding(
            get: { date(from: service.settings.notificationPreferences.preferredVerseTime) },
            set: { newDate in
                service.settings.notificationPreferences.preferredVerseTime = hhMM(from: newDate)
                Task { await service.updateNotificationPreferences(service.settings.notificationPreferences) }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { date(from: service.settings.notificationPreferences.preferredReminderTime) },
            set: { newDate in
                service.settings.notificationPreferences.preferredReminderTime = hhMM(from: newDate)
                Task { await service.updateNotificationPreferences(service.settings.notificationPreferences) }
            }
        )
    }

    // MARK: - Helpers

    private func date(from hhMM: String) -> Date {
        let parts = hhMM.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return Date() }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts[0]
        components.minute = parts[1]
        return Calendar.current.date(from: components) ?? Date()
    }

    private func hhMM(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = components.hour ?? 0
        let m = components.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    private func weekdayName(for index: Int) -> String {
        // index 0 = Sunday … 6 = Saturday
        let symbols = Calendar.current.weekdaySymbols
        guard index < symbols.count else { return "" }
        return symbols[index]
    }

    private func hourLabel(for hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    // MARK: - Section 7: Digital Wellbeing

    private var wellbeingSection: some View {
        Section {
            NavigationLink(destination: WellbeingDashboardView()) {
                Label("Digital Wellbeing", systemImage: "chart.bar.xaxis")
            }
        } header: {
            Text("Screen Time")
        } footer: {
            Text("Track how you use AMEN. Opt-in only, stored only on this device.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - StreakTypeToggleRow

/// Isolated row so each toggle has its own contained binding without
/// capturing the mutable Set by value inside a closure.
private struct StreakTypeToggleRow: View {
    let type: SpiritualStreakType
    @ObservedObject var service: SpiritualRhythmOSService

    private var isEnabled: Bool {
        service.settings.enabledStreakTypes.contains(type)
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isEnabled },
            set: { on in
                var updated = service.settings.enabledStreakTypes
                if on { updated.insert(type) } else { updated.remove(type) }
                Task { await service.updateEnabledStreakTypes(updated) }
            }
        )) {
            Label {
                Text(type.displayName)
            } icon: {
                Image(systemName: type.icon)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SpiritualNotificationCategory human-readable names

private extension SpiritualNotificationCategory {
    var humanReadableName: String {
        switch self {
        case .dailyVerse:          return "Daily Verse"
        case .readingReminder:     return "Reading Reminder"
        case .prayerReminder:      return "Prayer Reminder"
        case .communityDigest:     return "Community Digest"
        case .streakReminder:      return "Rhythm Reminder"
        case .quietReturn:         return "" // system-managed, not shown
        case .milestoneReflection: return "Milestone Moments"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        SpiritualRhythmSettingsView()
    }
}
#endif
