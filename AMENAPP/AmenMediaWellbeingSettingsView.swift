// AmenMediaWellbeingSettingsView.swift
// AMENAPP
//
// Wellbeing controls for the media system. Lets users set intentional
// session defaults — session length, checkpoints, autoplay, late-night
// pause, vanity metric visibility, captions, and sensitive content.

import SwiftUI

struct AmenMediaWellbeingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("media.sessionLengthMinutes") private var sessionLengthMinutes: Int = 15
    @AppStorage("media.autoplayEnabled") private var autoplayEnabled: Bool = false
    @AppStorage("media.checkpointsEnabled") private var checkpointsEnabled: Bool = true
    @AppStorage("media.lateNightPauseEnabled") private var lateNightPauseEnabled: Bool = false
    @AppStorage("media.lateNightPauseHour") private var lateNightPauseHour: Int = 22
    @AppStorage("media.hideVanityMetrics") private var hideVanityMetrics: Bool = true
    @AppStorage("media.sensitiveContentFilter") private var sensitiveContentFilter: Bool = true
    @AppStorage("media.captionsDefaultOn") private var captionsDefaultOn: Bool = true

    private let sessionLengths = [5, 10, 15, 20, 30, 45, 60]
    private let flags = AMENFeatureFlags.shared

    var body: some View {
        NavigationStack {
            Form {
                sessionLengthSection
                if flags.autoplayWithinSessionsEnabled { autoplaySection }
                if flags.mediaSessionCheckpointsEnabled { checkpointSection }
                if flags.lateNightPauseEnabled { lateNightSection }
                vanityMetricsSection
                contentSection
                captionsSection
                aboutSection
            }
            .navigationTitle("Media wellbeing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Session Length

    private var sessionLengthSection: some View {
        Section {
            Picker("Session length", selection: $sessionLengthMinutes) {
                ForEach(sessionLengths, id: \.self) { minutes in
                    Text(sessionLengthLabel(minutes)).tag(minutes)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Preferred session length")
        } header: {
            Text("Session length")
        } footer: {
            Text("Sessions will suggest stopping at this point. You can always continue intentionally.")
        }
    }

    // MARK: Autoplay

    private var autoplaySection: some View {
        Section {
            Toggle("Autoplay next item", isOn: $autoplayEnabled)
                .accessibilityLabel("Autoplay next item in session")
        } header: {
            Text("Autoplay")
        } footer: {
            Text("When off, you tap to advance to the next item. Keeps sessions intentional.")
        }
    }

    // MARK: Checkpoints

    private var checkpointSection: some View {
        Section {
            Toggle("Session checkpoints", isOn: $checkpointsEnabled)
                .accessibilityLabel("Show session checkpoints")
        } header: {
            Text("Checkpoints")
        } footer: {
            Text("Checkpoints appear every few items to help you decide whether to continue, reflect, or end your session.")
        }
    }

    // MARK: Late-night Pause

    private var lateNightSection: some View {
        Section {
            Toggle("Late-night pause", isOn: $lateNightPauseEnabled)
                .accessibilityLabel("Enable late-night pause")
            if lateNightPauseEnabled {
                Picker("Pause after", selection: $lateNightPauseHour) {
                    ForEach(18..<25, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Late-night pause hour")
            }
        } header: {
            Text("Late-night pause")
        } footer: {
            Text("Sessions will gently suggest stopping after this hour. Rest is part of a healthy rhythm.")
        }
    }

    // MARK: Vanity Metrics

    private var vanityMetricsSection: some View {
        Section {
            Toggle("Hide like and view counts", isOn: $hideVanityMetrics)
                .accessibilityLabel("Hide vanity metrics like counts and view counts")
        } header: {
            Text("Metrics")
        } footer: {
            Text("Focus on the content, not the numbers. Likes and view counts are hidden by default.")
        }
    }

    // MARK: Content Filter

    private var contentSection: some View {
        Section {
            Toggle("Sensitive content filter", isOn: $sensitiveContentFilter)
                .accessibilityLabel("Enable sensitive content filter")
        } header: {
            Text("Content")
        } footer: {
            Text("Filters media that may be emotionally heavy, includes strong themes, or is marked sensitive by the creator.")
        }
    }

    // MARK: Captions

    private var captionsSection: some View {
        Section {
            Toggle("Captions on by default", isOn: $captionsDefaultOn)
                .accessibilityLabel("Enable captions by default")
        } header: {
            Text("Captions")
        } footer: {
            Text("Captions are shown by default. Turn off if you prefer a cleaner view and enable them per session.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.systemScaled(18, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Amen is designed to leave you fulfilled, not exhausted. These settings help you stay in control of your time and attention.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Helpers

    private func sessionLengthLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "1 hr"
    }

    private func hourLabel(_ hour: Int) -> String {
        let adjusted = hour > 23 ? hour - 24 : hour
        let suffix = adjusted < 12 ? "AM" : "PM"
        let display = adjusted == 0 ? 12 : (adjusted > 12 ? adjusted - 12 : adjusted)
        return "\(display):00 \(suffix)"
    }
}
