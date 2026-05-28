// SabbathModeView.swift
// AMENAPP — Calm Control + Spiritual Rhythm OS
//
// Dedicated settings view for Sabbath Mode.
// Design rules:
//   • White backgrounds, black text, native iOS controls only.
//   • Status card uses soft system gray — no Liquid Glass on content surfaces.
//   • Grace-based, non-pressuring language throughout.
//   • Full Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency support.

import SwiftUI

// MARK: - SabbathModeView

struct SabbathModeView: View {

    @ObservedObject var service: SpiritualRhythmService

    // Local day-of-week selection state (0 = Sunday, 6 = Saturday)
    @State private var selectedDays: Set<Int> = []
    @State private var startTime: Date = SabbathModeView.defaultStartTime
    @State private var endTime: Date = SabbathModeView.defaultEndTime

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                headerSection
                toggleSection
                if service.rhythm.sabbathModeEnabled {
                    dayPickerSection
                    timeRangeSection
                }
                if service.rhythm.sabbathModeEnabled && isCurrentlyInSabbath {
                    statusCardSection
                }
                infoSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sabbath Mode")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await service.loadAll()
            }
        }
    }

    // MARK: - Computed

    private var isCurrentlyInSabbath: Bool {
        service.rhythm.sabbathModeEnabled
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("A time to rest and be still.")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("When active, notifications pause and your feed quiets. You remain free to read, pray, and reflect.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Toggle Section

    private var toggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { service.rhythm.sabbathModeEnabled },
                set: { newValue in
                    withAnimation(.easeInOut) {
                        let _: Task<Void, Never> = Task { await service.setSabbathMode(enabled: newValue) }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Sabbath Mode")
                        .font(.body)
                    Text(service.rhythm.sabbathModeEnabled ? "Active on selected days and times" : "Pauses notifications and quiets your feed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Enable Sabbath Mode")
            .accessibilityHint("Pauses non-essential notifications and quiets your feed during your selected rest window")
        }
    }

    // MARK: - Day Picker Section

    private var dayPickerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                DayOfWeekPicker(selectedDays: $selectedDays)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Sabbath Days")
        } footer: {
            Text("Tap the days when you observe Sabbath rest.")
                .font(.caption)
        }
    }

    // MARK: - Time Range Section

    private var timeRangeSection: some View {
        Section {
            DatePicker(
                "Starts at",
                selection: $startTime,
                displayedComponents: [.hourAndMinute]
            )
            .accessibilityLabel("Sabbath start time")
            .accessibilityHint("Select the time when Sabbath Mode begins on your chosen days")

            DatePicker(
                "Ends at",
                selection: $endTime,
                displayedComponents: [.hourAndMinute]
            )
            .accessibilityLabel("Sabbath end time")
            .accessibilityHint("Select the time when Sabbath Mode ends on your chosen days")
        } header: {
            Text("Time Window")
        } footer: {
            Text("The window can span midnight — for example, Friday evening to Saturday morning.")
                .font(.caption)
        }
    }

    // MARK: - Status Card Section

    private var statusCardSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("You're in Sabbath Mode.")
                        .font(.headline)
                    Text("Notifications are paused. Rest well.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You are in Sabbath Mode. Notifications are paused. Rest well.")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("What happens during Sabbath Mode")
                    .font(.subheadline.weight(.medium))

                SabbathInfoRow(
                    icon: "bell.slash",
                    text: "Non-essential notifications are paused"
                )
                SabbathInfoRow(
                    icon: "person.2",
                    text: "Feed shows only your circles and saved content"
                )
                SabbathInfoRow(
                    icon: "moon.stars",
                    text: "Your presence shows as \"Sabbathing\""
                )
                SabbathInfoRow(
                    icon: "book",
                    text: "You can still read, reflect, and pray"
                )
            }
            .padding(.vertical, 6)
        } header: {
            Text("About Sabbath Mode")
        } footer: {
            Text("Sabbath Mode is entirely yours to configure. Nothing here is required.")
                .font(.caption)
        }
    }

    // MARK: - Default Times

    private static var defaultStartTime: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 18
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private static var defaultEndTime: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - DayOfWeekPicker

private struct DayOfWeekPicker: View {

    @Binding var selectedDays: Set<Int>

    private let dayAbbreviations = ["S", "M", "T", "W", "T", "F", "S"]
    private let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                DayCircleButton(
                    abbreviation: dayAbbreviations[index],
                    fullName: dayNames[index],
                    isSelected: selectedDays.contains(index),
                    action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if selectedDays.contains(index) {
                                selectedDays.remove(index)
                            } else {
                                selectedDays.insert(index)
                            }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - DayCircleButton

private struct DayCircleButton: View {

    let abbreviation: String
    let fullName: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.primary : Color(.systemGray5))
                    .frame(width: 36, height: 36)
                Text(abbreviation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
        .accessibilityLabel(fullName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Tap to deselect \(fullName)" : "Tap to select \(fullName)")
    }
}

// MARK: - SabbathInfoRow

private struct SabbathInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SabbathModeView(service: SpiritualRhythmService.shared)
}
#endif
