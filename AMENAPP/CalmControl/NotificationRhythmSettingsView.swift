// NotificationRhythmSettingsView.swift
// AMENAPP — Calm Control + Spiritual Rhythm OS
//
// Settings for notification rhythm: intensity, verse, digests, rhythm reminders, quiet hours.
// Design rules:
//   • White backgrounds, black text, native iOS controls only.
//   • No dark patterns. No guilt-based copy.
//   • Full Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency support.

import SwiftUI

// MARK: - NotificationIntensityMode

enum NotificationIntensityMode: String, CaseIterable, Identifiable {
    case minimal
    case balanced
    case encouraging
    case activeCommunity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal:           return "Minimal"
        case .balanced:          return "Balanced"
        case .encouraging:       return "Encouraging"
        case .activeCommunity:   return "Active Community"
        }
    }

    var description: String {
        switch self {
        case .minimal:
            return "One gentle nudge per day. Quiet presence, no noise."
        case .balanced:
            return "A handful of thoughtful notifications spread through the day."
        case .encouraging:
            return "Regular reminders to help you stay connected to your rhythm."
        case .activeCommunity:
            return "Stay fully connected — community activity, verses, and reminders throughout the day."
        }
    }
}

// MARK: - NotificationRhythmSettingsView

struct NotificationRhythmSettingsView: View {

    @ObservedObject var rhythmService: SpiritualRhythmService
    @State private var intensityMode: NotificationIntensityMode = .balanced

    // Daily Verse
    @State private var dailyVerseEnabled: Bool = true
    @State private var dailyVerseTime: Date = NotificationRhythmSettingsView.defaultVerseTime

    // Morning Digest
    @State private var morningDigestEnabled: Bool = true
    @State private var morningDigestTime: Date = NotificationRhythmSettingsView.defaultMorningTime

    // Evening Digest
    @State private var eveningDigestEnabled: Bool = true
    @State private var eveningDigestTime: Date = NotificationRhythmSettingsView.defaultEveningTime

    // Rhythm Reminders
    @State private var rhythmRemindersEnabled: Bool = true

    // Quiet Hours
    @State private var quietHoursEnabled: Bool = false
    @State private var quietHoursStart: Date = NotificationRhythmSettingsView.defaultQuietStart
    @State private var quietHoursEnd: Date = NotificationRhythmSettingsView.defaultQuietEnd

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                intensitySection
                dailyVerseSection
                morningDigestSection
                eveningDigestSection
                rhythmRemindersSection
                quietHoursSection
                globalFooterSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Notification Rhythm")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await rhythmService.loadAll()
                syncFromService()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityLabel("Save notification rhythm settings")
                        .accessibilityHint("Saves your notification preferences")
                }
            }
        }
    }

    // MARK: - Section: Intensity

    private var intensitySection: some View {
        Section {
            ForEach(NotificationIntensityMode.allCases) { mode in
                IntensityOptionRow(
                    mode: mode,
                    isSelected: intensityMode == mode,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            intensityMode = mode
                        }
                    }
                )
            }
        } header: {
            Text("Intensity")
        } footer: {
            Text("Controls how often Amen reaches out. You can change this at any time.")
                .font(.caption)
        }
    }

    // MARK: - Section: Daily Verse

    private var dailyVerseSection: some View {
        Section {
            Toggle(isOn: $dailyVerseEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Verse")
                        .font(.body)
                    Text("A verse arrives at your chosen time each day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Daily Verse notification")
            .accessibilityHint("Sends one verse to you each day at the time you choose")

            if dailyVerseEnabled {
                DatePicker(
                    "Deliver at",
                    selection: $dailyVerseTime,
                    displayedComponents: [.hourAndMinute]
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Daily verse delivery time")
                .accessibilityHint("Select the time each day when your verse arrives")
            }
        } header: {
            Text("Daily Verse")
        }
    }

    // MARK: - Section: Morning Digest

    private var morningDigestSection: some View {
        Section {
            Toggle(isOn: $morningDigestEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Morning Digest")
                        .font(.body)
                    Text("Receive a calm morning summary of your community")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Morning Digest notification")
            .accessibilityHint("Sends a calm summary of your community's activity each morning")

            if morningDigestEnabled {
                DatePicker(
                    "Arrives at",
                    selection: $morningDigestTime,
                    displayedComponents: [.hourAndMinute]
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Morning digest delivery time")
                .accessibilityHint("Select the morning hour when the digest arrives")
            }
        } header: {
            Text("Morning Digest")
        }
    }

    // MARK: - Section: Evening Digest

    private var eveningDigestSection: some View {
        Section {
            Toggle(isOn: $eveningDigestEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evening Digest")
                        .font(.body)
                    Text("A gentle close-of-day summary of your circles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Evening Digest notification")
            .accessibilityHint("Sends a calm summary of community activity each evening")

            if eveningDigestEnabled {
                DatePicker(
                    "Arrives at",
                    selection: $eveningDigestTime,
                    displayedComponents: [.hourAndMinute]
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Evening digest delivery time")
                .accessibilityHint("Select the evening hour when the digest arrives")
            }
        } header: {
            Text("Evening Digest")
        }
    }

    // MARK: - Section: Rhythm Reminders

    private var rhythmRemindersSection: some View {
        Section {
            Toggle(isOn: $rhythmRemindersEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adaptive Rhythm Reminders")
                        .font(.body)
                    Text("We'll remind you based on your natural rhythm, not a fixed schedule")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Adaptive Rhythm Reminders")
            .accessibilityHint("Sends gentle reminders timed to your personal activity patterns rather than a fixed clock")
        } header: {
            Text("Rhythm Reminders")
        } footer: {
            Text("Adaptive reminders observe when you naturally engage and gently reach out at those moments.")
                .font(.caption)
        }
    }

    // MARK: - Section: Quiet Hours

    private var quietHoursSection: some View {
        Section {
            Toggle(isOn: $quietHoursEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quiet Hours")
                        .font(.body)
                    Text("No notifications during your rest window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Quiet Hours")
            .accessibilityHint("Prevents all notifications from arriving during the time window you choose")

            if quietHoursEnabled {
                DatePicker(
                    "Quiet starts",
                    selection: $quietHoursStart,
                    displayedComponents: [.hourAndMinute]
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Quiet hours start time")
                .accessibilityHint("Select when notifications begin to pause each night")

                DatePicker(
                    "Quiet ends",
                    selection: $quietHoursEnd,
                    displayedComponents: [.hourAndMinute]
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Quiet hours end time")
                .accessibilityHint("Select when notifications resume each morning")
            }
        } header: {
            Text("Quiet Hours")
        } footer: {
            Text("Quiet Hours apply every day, including streak and rhythm reminders.")
                .font(.caption)
        }
    }

    // MARK: - Global Footer

    private var globalFooterSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("We never send guilt-based messages. All reminders can be turned off at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sync & Save

    private func syncFromService() {
        let notifSettings = rhythmService.rhythm
        morningDigestEnabled = notifSettings.scriptureStreakEnabled
        eveningDigestEnabled = notifSettings.bibleReadingStreakEnabled
        rhythmRemindersEnabled = notifSettings.graceRecoveryEnabled

        morningDigestTime = hourToDate(notifSettings.preferredReminderHour)
        eveningDigestTime = hourToDate(notifSettings.preferredEveningDigestHour)
    }

    private func save() {
        rhythmService.rhythm.preferredReminderHour = Calendar.current.component(.hour, from: morningDigestTime)
        rhythmService.rhythm.preferredEveningDigestHour = Calendar.current.component(.hour, from: eveningDigestTime)
        Task { await rhythmService.checkInactivityPolicy() }
    }

    // MARK: - Helpers

    private func hourToDate(_ hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Default Times

    private static var defaultVerseTime: Date { makeTime(hour: 8, minute: 0) }
    private static var defaultMorningTime: Date { makeTime(hour: 7, minute: 30) }
    private static var defaultEveningTime: Date { makeTime(hour: 18, minute: 0) }
    private static var defaultQuietStart: Date { makeTime(hour: 22, minute: 0) }
    private static var defaultQuietEnd: Date { makeTime(hour: 7, minute: 0) }

    private static func makeTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - IntensityOptionRow

private struct IntensityOptionRow: View {

    let mode: NotificationIntensityMode
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.primary : Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 11, height: 11)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.label). \(mode.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select \(mode.label) notification intensity")
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NotificationRhythmSettingsView(rhythmService: SpiritualRhythmService.shared)
}
#endif
