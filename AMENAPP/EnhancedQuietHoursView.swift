//
//  EnhancedQuietHoursView.swift
//  AMENAPP
//
//  Enhanced Quiet Hours UI with adaptive learning and smart features
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EnhancedQuietHoursView: View {
    @ObservedObject private var adaptiveEngine = AdaptiveQuietHoursEngine.shared
    @ObservedObject private var progressiveEngine = ProgressiveQuietingEngine.shared
    @Environment(\.dismiss) var dismiss

    @State private var quietHoursEnabled = false
    @State private var startTime = "22:00"
    @State private var endTime = "07:00"
    @State private var allowDMs = true
    @State private var progressiveQuieting = true
    @State private var adaptiveLearning = true

    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var showSuggestionDetail: AdaptiveQuietHoursEngine.QuietHoursSuggestion?
    @State private var isSaving = false
    @State private var hasLoadedSettings = false
    @State private var saveTask: Task<Void, Never>?
    @State private var quietHoursSource: String = "manual"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {

                    headerSection
                    masterToggleSection

                    if quietHoursEnabled {
                        timeRangeSection
                        progressiveQuietingSection
                        adaptiveLearningSection
                        suggestionsSection
                        catchUpSummarySection
                        advancedOptionsSection
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Quiet Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await loadSettings()
                await adaptiveEngine.loadLearnedPattern()
                adaptiveEngine.isLearning = adaptiveLearning
            }
            .onChange(of: quietHoursEnabled) { _, _ in
                scheduleSave()
            }
            .onChange(of: startTime) { _, _ in
                scheduleSave()
            }
            .onChange(of: endTime) { _, _ in
                scheduleSave()
            }
            .onChange(of: allowDMs) { _, _ in
                scheduleSave()
            }
            .onChange(of: progressiveQuieting) { _, _ in
                scheduleSave()
            }
            .onChange(of: adaptiveLearning) { _, _ in
                adaptiveEngine.isLearning = adaptiveLearning
                scheduleSave()
            }
            .sheet(isPresented: $showStartPicker) {
                TimePickerSheet(title: "Start Time", selectedTime: $startTime)
            }
            .sheet(isPresented: $showEndPicker) {
                TimePickerSheet(title: "End Time", selectedTime: $endTime)
            }
            .sheet(item: $showSuggestionDetail) { suggestion in
                SuggestionDetailView(suggestion: suggestion) {
                    await applySuggestionToSettings(suggestion)
                    showSuggestionDetail = nil
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)

                Image(systemName: quietHoursEnabled ? "moon.fill" : "moon")
                    .font(.systemScaled(36))
                    .foregroundStyle(.indigo)
                    .symbolEffect(.bounce, value: quietHoursEnabled)
            }

            Text("Quiet Hours")
                .font(AMENFont.bold(22))

            Text("Pause notifications so you can rest without interruption")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Master Toggle

    private var masterToggleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MASTER SWITCH")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $quietHoursEnabled) {
                    Text("Enable Quiet Hours")
                        .font(AMENFont.semiBold(15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .tint(.indigo)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            if quietHoursEnabled {
                let feedback = progressiveEngine.generateQuietFeedback()
                QuietStatusBanner(feedback: feedback)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: quietHoursEnabled)
        .padding(.bottom, 24)
    }

    // MARK: - Time Range Section

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TIME RANGE")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Button {
                    showStartPicker = true
                } label: {
                    HStack {
                        Image(systemName: "moon.stars")
                            .foregroundStyle(.indigo)
                            .frame(width: 24)
                        Text("Start")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(startTime)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider().padding(.leading, 16)

                Button {
                    showEndPicker = true
                } label: {
                    HStack {
                        Image(systemName: "sunrise")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text("End")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(endTime)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("Notifications will be paused between these hours")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Progressive Quieting

    private var progressiveQuietingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROGRESSIVE QUIETING")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $progressiveQuieting) {
                    Text("Gradual Volume Reduction")
                        .font(AMENFont.semiBold(15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .tint(.purple)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if progressiveQuieting {
                    Divider().padding(.leading, 16)

                    ProgressiveLevelsPreview()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.3), value: progressiveQuieting)

            Text("Notification volume gradually decreases as quiet hours approach: 2hr → minimal, 1hr → moderate, 30min → substantial, <15min → critical only")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Adaptive Learning

    private var adaptiveLearningSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ADAPTIVE LEARNING")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $adaptiveLearning) {
                    Text("Learn My Sleep Pattern")
                        .font(AMENFont.semiBold(15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .tint(.teal)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if adaptiveLearning, let pattern = adaptiveEngine.learnedPattern {
                    Divider().padding(.leading, 16)

                    LearnedPatternPreview(pattern: pattern)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.3), value: adaptiveLearning)

            Text("AMEN learns when you're typically active and inactive to suggest optimal quiet hours. Requires \(adaptiveLearning ? "7 days" : "opt-in") of usage data.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .padding(.bottom, 24)
    }

    // MARK: - AI Suggestions

    private var suggestionsSection: some View {
        Group {
            if !adaptiveEngine.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI SUGGESTIONS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(adaptiveEngine.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            SuggestionRow(suggestion: suggestion) {
                                showSuggestionDetail = suggestion
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            if index < adaptiveEngine.suggestions.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Based on your behavior patterns and preferences")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Catch-Up Summary

    private var catchUpSummarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CATCH-UP SUMMARY")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Summary on Wake")
                            .font(AMENFont.semiBold(15))
                        Text("See what you missed while resting")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)

            Text("When you open AMEN after quiet hours, you'll see a smart summary of what happened")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Advanced Options

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ADVANCED")
                .font(AMENFont.bold(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $allowDMs) {
                    Text("Allow DMs During Quiet Hours")
                        .font(AMENFont.regular(15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .tint(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                NavigationLink {
                    FocusModeIntegrationView()
                } label: {
                    HStack {
                        Image(systemName: "moon.circle")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        Text("iOS Focus Mode Sync")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider().padding(.leading, 16)

                NavigationLink {
                    LocationContextView()
                } label: {
                    HStack {
                        Image(systemName: "location")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        Text("Location-Based Rules")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Load Settings

    private func loadSettings() async {
        let defaults = UserDefaults.standard
        if let storedEnabled = defaults.object(forKey: "notifQuietHoursEnabled") as? Bool {
            quietHoursEnabled = storedEnabled
        }
        if let storedStart = defaults.object(forKey: "notifQuietHoursStartMinutes") as? Int {
            startTime = timeString(from: storedStart)
        }
        if let storedEnd = defaults.object(forKey: "notifQuietHoursEndMinutes") as? Int {
            endTime = timeString(from: storedEnd)
        }
        if let storedSource = defaults.string(forKey: "notifQuietHoursSource") {
            quietHoursSource = storedSource
        }
        if let storedAdaptive = defaults.object(forKey: "notifQuietHoursAdaptiveLearning") as? Bool {
            adaptiveLearning = storedAdaptive
        }
        if let storedProgressive = defaults.object(forKey: "notifQuietHoursProgressiveQuieting") as? Bool {
            progressiveQuieting = storedProgressive
        }
        if let storedAllowDMs = defaults.object(forKey: "notifQuietHoursAllowDMs") as? Bool {
            allowDMs = storedAllowDMs
        }

        if let uid = Auth.auth().currentUser?.uid {
            let doc = try? await Firestore.firestore().document("users/\(uid)").getDocument()
            if let data = doc?.data(),
               let settings = data["notificationSettings"] as? [String: Any] {
                if let enabled = settings["quietHoursEnabled"] as? Bool {
                    quietHoursEnabled = enabled
                }
                if let startMinutes = settings["quietHoursStartMinutes"] as? Int {
                    startTime = timeString(from: startMinutes)
                }
                if let endMinutes = settings["quietHoursEndMinutes"] as? Int {
                    endTime = timeString(from: endMinutes)
                }
                if let source = settings["quietHoursSource"] as? String {
                    quietHoursSource = source
                }
                if let adaptive = settings["quietHoursAdaptiveLearning"] as? Bool {
                    adaptiveLearning = adaptive
                }
                if let progressive = settings["quietHoursProgressiveQuieting"] as? Bool {
                    progressiveQuieting = progressive
                }
                if let allow = settings["quietHoursAllowDMs"] as? Bool {
                    allowDMs = allow
                }
            }
        }

        hasLoadedSettings = true
    }

    private func scheduleSave() {
        guard hasLoadedSettings else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await saveSettings()
        }
    }

    private func saveSettings() async {
        guard hasLoadedSettings else { return }
        isSaving = true
        defer { isSaving = false }

        let startMinutes = minutes(from: startTime)
        let endMinutes = minutes(from: endTime)

        let defaults = UserDefaults.standard
        defaults.set(quietHoursEnabled, forKey: "notifQuietHoursEnabled")
        defaults.set(startMinutes, forKey: "notifQuietHoursStartMinutes")
        defaults.set(endMinutes, forKey: "notifQuietHoursEndMinutes")
        defaults.set(quietHoursSource, forKey: "notifQuietHoursSource")
        defaults.set(adaptiveLearning, forKey: "notifQuietHoursAdaptiveLearning")
        defaults.set(progressiveQuieting, forKey: "notifQuietHoursProgressiveQuieting")
        defaults.set(allowDMs, forKey: "notifQuietHoursAllowDMs")

        if let uid = Auth.auth().currentUser?.uid {
            do {
                try await Firestore.firestore().document("users/\(uid)").updateData([
                    "notificationSettings.quietHoursEnabled": quietHoursEnabled,
                    "notificationSettings.quietHoursStartMinutes": startMinutes,
                    "notificationSettings.quietHoursEndMinutes": endMinutes,
                    "notificationSettings.quietHoursSource": quietHoursSource,
                    "notificationSettings.quietHoursAdaptiveLearning": adaptiveLearning,
                    "notificationSettings.quietHoursProgressiveQuieting": progressiveQuieting,
                    "notificationSettings.quietHoursAllowDMs": allowDMs,
                    "notificationSettings.quietHoursUpdatedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                print("EnhancedQuietHoursView: failed to sync quiet hours — \(error.localizedDescription)")
            }
        }
    }

    private func applySuggestionToSettings(_ suggestion: AdaptiveQuietHoursEngine.QuietHoursSuggestion) async {
        quietHoursEnabled = true
        startTime = suggestion.startTime
        endTime = suggestion.endTime
        quietHoursSource = "adaptive_\(suggestion.reason)"
        await adaptiveEngine.applySuggestion(suggestion)
        await saveSettings()
    }

    private func minutes(from timeString: String) -> Int {
        let parts = timeString.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return 0
        }
        return hour * 60 + minute
    }

    private func timeString(from minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - Supporting Views

struct QuietStatusBanner: View {
    let feedback: ProgressiveQuietingEngine.QuietFeedback

    var body: some View {
        HStack(spacing: 12) {
            Text(feedback.emoji)
                .font(.systemScaled(28))

            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.level.displayName)
                    .font(AMENFont.semiBold(13))
                Text(feedback.message)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(feedback.color).opacity(0.1))
        .cornerRadius(12)
    }
}

struct ProgressiveLevelsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LevelRow(time: "2hr before", level: "Minimal", emoji: "🔕")
            LevelRow(time: "1hr before", level: "Moderate", emoji: "🌙")
            LevelRow(time: "30min before", level: "Substantial", emoji: "💤")
            LevelRow(time: "<15min before", level: "Critical Only", emoji: "🛑")
        }
    }
}

struct LevelRow: View {
    let time: String
    let level: String
    let emoji: String

    var body: some View {
        HStack {
            Text(emoji)
            Text(time)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(level)
                .font(AMENFont.semiBold(12))
        }
    }
}

struct LearnedPatternPreview: View {
    let pattern: AdaptiveQuietHoursEngine.QuietHoursPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.teal)
                Text("Learned Pattern")
                    .font(AMENFont.semiBold(13))
                Spacer()
                Text("\(Int(pattern.confidence * 100))% confident")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Weekday:")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pattern.weekdayStart) - \(pattern.weekdayEnd)")
                    .font(AMENFont.semiBold(12))
            }

            HStack {
                Text("Weekend:")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pattern.weekendStart) - \(pattern.weekendEnd)")
                    .font(AMENFont.semiBold(12))
            }
        }
        .padding(12)
        .background(Color.teal.opacity(0.1))
        .cornerRadius(8)
    }
}

struct SuggestionRow: View {
    let suggestion: AdaptiveQuietHoursEngine.QuietHoursSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: iconForReason(suggestion.reason))
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(suggestion.startTime) - \(suggestion.endTime)")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                    Text(reasonText(suggestion.reason))
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(suggestion.confidence * 100))%")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.orange)
                    Text("\(suggestion.dataPoints) samples")
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func iconForReason(_ reason: AdaptiveQuietHoursEngine.QuietHoursSuggestion.SuggestionReason) -> String {
        switch reason {
        case .sleepPattern: return "bed.double"
        case .inactivityPattern: return "moon.zzz"
        case .focusModeSync: return "moon.circle"
        case .calendarEvents: return "calendar"
        case .locationPattern: return "location"
        }
    }

    private func reasonText(_ reason: AdaptiveQuietHoursEngine.QuietHoursSuggestion.SuggestionReason) -> String {
        switch reason {
        case .sleepPattern: return "Based on your sleep pattern"
        case .inactivityPattern: return "Based on inactivity"
        case .focusModeSync: return "From iOS Focus Mode"
        case .calendarEvents: return "From calendar events"
        case .locationPattern: return "Based on location"
        }
    }
}

// MARK: - Placeholder Detail Views

struct SuggestionDetailView: View {
    let suggestion: AdaptiveQuietHoursEngine.QuietHoursSuggestion
    let onApply: () async -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                Text("Apply this suggestion?")
                Text("\(suggestion.startTime) - \(suggestion.endTime)")
                    .font(.title)
            }
            .navigationTitle("Suggestion")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task {
                            await onApply()
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct FocusModeIntegrationView: View {
    var body: some View {
        Text("Focus Mode Integration")
            .navigationTitle("Focus Mode Sync")
    }
}

struct LocationContextView: View {
    var body: some View {
        Text("Location-Based Rules")
            .navigationTitle("Location Context")
    }
}

#Preview {
    EnhancedQuietHoursView()
}
