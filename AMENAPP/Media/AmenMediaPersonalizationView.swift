// AmenMediaPersonalizationView.swift
// AMENAPP
//
// User-controlled preferences for all media experiences.
// All settings are stored locally (AppStorage / UserDefaults).
// Defaults follow the spec: finite sessions on, checkpoints on,
// infinite autoplay off, community-first on, vanity metrics hidden.

import SwiftUI

// MARK: - Storage Keys

private enum MediaPrefKey {
    static let sessionLength          = "media.pref.sessionLength"
    static let autoplayWithinSession  = "media.pref.autoplayWithinSession"
    static let checkpointsEnabled     = "media.pref.checkpointsEnabled"
    static let communityFirstRanking  = "media.pref.communityFirstRanking"
    static let friendsFirstRanking    = "media.pref.friendsFirstRanking"
    static let hideVanityMetrics      = "media.pref.hideVanityMetrics"
    static let sensitiveFilter        = "media.pref.sensitiveFilter"
    static let lateNightPause         = "media.pref.lateNightPause"
    static let reduceStimulation      = "media.pref.reduceStimulation"
    static let captionsAlwaysOn       = "media.pref.captionsAlwaysOn"
    static let defaultSoundOn         = "media.pref.defaultSoundOn"
    static let localInsightEnabled    = "media.pref.localInsightEnabled"
}

// MARK: - AmenMediaPersonalizationView

struct AmenMediaPersonalizationView: View {
    @Environment(\.dismiss) private var dismiss

    // Session
    @AppStorage(MediaPrefKey.sessionLength)         private var sessionLength        = 1    // 0=short, 1=medium, 2=long
    @AppStorage(MediaPrefKey.autoplayWithinSession) private var autoplaySession      = true
    @AppStorage(MediaPrefKey.checkpointsEnabled)    private var checkpointsEnabled   = true

    // Ranking
    @AppStorage(MediaPrefKey.communityFirstRanking) private var communityFirst       = true
    @AppStorage(MediaPrefKey.friendsFirstRanking)   private var friendsFirst         = true
    @AppStorage(MediaPrefKey.hideVanityMetrics)     private var hideVanityMetrics    = true

    // Safety
    @AppStorage(MediaPrefKey.sensitiveFilter)       private var sensitiveFilter      = true
    @AppStorage(MediaPrefKey.lateNightPause)        private var lateNightPause       = false
    @AppStorage(MediaPrefKey.reduceStimulation)     private var reduceStimulation    = false

    // Accessibility
    @AppStorage(MediaPrefKey.captionsAlwaysOn)      private var captionsAlwaysOn     = false
    @AppStorage(MediaPrefKey.defaultSoundOn)        private var defaultSoundOn       = true

    // Privacy
    @AppStorage(MediaPrefKey.localInsightEnabled)   private var localInsightEnabled  = true

    private let sessionLengthLabels = ["Short · ~5 min", "Medium · ~15 min", "Long · ~30 min"]

    var body: some View {
        NavigationStack {
            List {
                // MARK: Session
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preferred session length")
                            .font(.subheadline)
                        Picker("Session length", selection: $sessionLength) {
                            ForEach(0..<sessionLengthLabels.count, id: \.self) { i in
                                Text(sessionLengthLabels[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    Toggle("Autoplay within sessions", isOn: $autoplaySession)
                    Toggle("Reflection checkpoints", isOn: $checkpointsEnabled)
                } header: {
                    Text("Sessions")
                } footer: {
                    Text("Checkpoints appear after a few videos or 8 minutes — a gentle pause, not a gate.")
                }

                // MARK: Ranking
                Section {
                    Toggle("Community-first ranking", isOn: $communityFirst)
                    Toggle("Friends & family first", isOn: $friendsFirst)
                    Toggle("Hide vanity metrics", isOn: $hideVanityMetrics)
                } header: {
                    Text("What you see")
                } footer: {
                    Text("Hiding metrics removes like counts and view numbers from media cards. Content quality stays; scorekeeping goes.")
                }

                // MARK: Safety
                Section {
                    Toggle("Sensitive content filter", isOn: $sensitiveFilter)
                    Toggle("Late-night pause (after 10 PM)", isOn: $lateNightPause)
                    Toggle("Reduce stimulation mode", isOn: $reduceStimulation)
                } header: {
                    Text("Safety & pacing")
                } footer: {
                    Text("Reduce stimulation slows pacing, limits rapid content transitions, and removes animated thumbnails.")
                }

                // MARK: Accessibility
                Section {
                    Toggle("Captions always on", isOn: $captionsAlwaysOn)
                    Toggle("Sound on by default", isOn: $defaultSoundOn)
                } header: {
                    Text("Accessibility")
                }

                // MARK: Privacy
                Section {
                    Toggle("Quiet local insight", isOn: $localInsightEnabled)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Local insight notices patterns like \"you tend to reflect more after teaching clips\" — computed on this device, never uploaded.")
                }

                // MARK: Guardrails Note
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No streaks or engagement scores", systemImage: "nosign")
                        Label("No infinite autoplay outside sessions", systemImage: "stop.circle")
                        Label("No notification pressure campaigns", systemImage: "bell.slash")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color(.tertiarySystemBackground))
                } header: {
                    Text("What this app will never do")
                }
            }
            .navigationTitle("Media preferences")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    AmenMediaPersonalizationView()
}
