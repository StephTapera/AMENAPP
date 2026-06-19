// SabbathRhythmSettingsView.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 1)
//
// The user-facing configuration for the v2 rhythm: set a weekly rest window (the seam that
// makes a *scheduled* Sabbath actually fire), opt into the Wave 1 ambient triggers, and begin
// a manual rest. Every control writes through `SabbathRhythmController.applyConfig`, which
// persists locally and recomputes.
//
// Self-contained and embeddable in any settings list. Inert unless `sabbath_mode_enabled` is ON.

import SwiftUI

struct SabbathRhythmSettingsView: View {

    @ObservedObject private var controller = SabbathRhythmController.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared

    // Editable mirror of the persisted config. Seeded from the controller on appear.
    @State private var scheduleEnabled = false
    @State private var weekday = 1            // 1 = Sunday … 7 = Saturday
    @State private var startHour = 9
    @State private var endHour = 12
    @State private var usageEnabled = false
    @State private var locationEnabled = false
    @State private var motionEnabled = false

    var body: some View {
        Form {
            if !flags.sabbathModeEnabled {
                Section {
                    Text("Sabbath Mode is currently turned off. These preferences are saved, but rest will not begin until it's enabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            statusSection
            scheduleSection
            ambientSection
            manualSection
        }
        .navigationTitle("Sabbath rhythm")
        .onAppear(perform: seedFromConfig)
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Right now") {
            HStack {
                Text("State")
                Spacer()
                Text(stateLabel)
                    .foregroundStyle(.secondary)
            }
            if !controller.currentConfig.hasAnyActiveTrigger {
                Text("No rest is scheduled and no ambient triggers are on, so Selah will never quiet on its own yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateLabel: String {
        switch controller.state {
        case .normal:     return "Full app"
        case .rest:       return "Resting"
        case .presence:   return "In worship"
        case .holyGround: return "Holy ground"
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            Toggle("Weekly rest window", isOn: $scheduleEnabled)
                .onChange(of: scheduleEnabled) { _, _ in persist() }

            if scheduleEnabled {
                Picker("Day", selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Self.weekdayName(day)).tag(day)
                    }
                }
                .onChange(of: weekday) { _, _ in persist() }

                Picker("Starts", selection: $startHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                }
                .onChange(of: startHour) { _, _ in persist() }

                Picker("Ends", selection: $endHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                }
                .onChange(of: endHour) { _, _ in persist() }
            }
        } header: {
            Text("Schedule")
        } footer: {
            if scheduleEnabled && endHour <= startHour {
                Text("This window wraps past midnight — it runs from \(Self.hourLabel(startHour)) until \(Self.hourLabel(endHour)) the next morning.")
            } else {
                Text("Selah quiets automatically during this window each week.")
            }
        }
    }

    // MARK: - Ambient triggers

    private var ambientSection: some View {
        Section {
            Toggle("Long scrolling", isOn: $usageEnabled)
                .onChange(of: usageEnabled) { _, _ in persist() }
            Toggle("At a place of worship", isOn: $locationEnabled)
                .onChange(of: locationEnabled) { _, _ in persist() }
            Toggle("During a walk", isOn: $motionEnabled)
                .onChange(of: motionEnabled) { _, _ in persist() }
        } header: {
            Text("Gentle invitations to rest")
        } footer: {
            Text("When these are on, Selah may quietly invite you to rest. You can always leave with one tap.")
        }
    }

    // MARK: - Manual

    @ViewBuilder
    private var manualSection: some View {
        if flags.sabbathModeEnabled, flags.sabbathTriggerManualEnabled, controller.state == .normal {
            Section {
                Button {
                    controller.requestBeginRest()
                } label: {
                    Label("Begin rest now", systemImage: "leaf")
                }
            }
        }
    }

    // MARK: - Config bridge

    private func seedFromConfig() {
        let config = controller.currentConfig
        if let schedule = config.schedule {
            scheduleEnabled = true
            weekday = schedule.weekday
            startHour = schedule.startHour
            endHour = schedule.endHour
        } else {
            scheduleEnabled = false
        }
        usageEnabled = config.usageTriggerEnabled
        locationEnabled = config.locationTriggerEnabled
        motionEnabled = config.motionTriggerEnabled
    }

    private func persist() {
        let schedule = scheduleEnabled
            ? SabbathSchedule(weekday: weekday, startHour: startHour, endHour: endHour)
            : nil
        controller.applyConfig(
            SabbathRhythmConfig(
                schedule: schedule,
                usageTriggerEnabled: usageEnabled,
                locationTriggerEnabled: locationEnabled,
                motionTriggerEnabled: motionEnabled
            )
        )
    }

    // MARK: - Formatting

    private static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols      // ["Sunday", … , "Saturday"]
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "Day \(weekday)" }
        return symbols[index]
    }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        guard let date = Calendar.current.date(from: components) else { return "\(hour):00" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"                        // "9 AM"
        return formatter.string(from: date)
    }
}
