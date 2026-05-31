// BereanDriveSetupView.swift
// AMEN — Berean Drive CarPlay
//
// iPhone companion setup screen for Berean Drive.
// Shown on the phone (not in CarPlay) to configure the driving experience.
// Uses Liquid Glass design language for iPhone/iPad — not in CarPlay UI.
//
// Surfaces:
//   - Default drive mode
//   - Preferred scripture translation
//   - Prayer style
//   - Church search radius
//   - Small group contacts allowed in driving mode
//   - Youth safety restrictions
//   - Privacy controls (location, personalization, message read-aloud)
//   - "Resume in CarPlay" / "Start Berean Drive" status

import SwiftUI

struct BereanDriveSetupView: View {

    @State private var preferences = BereanDrivePreferences.load()
    @State private var showSaved = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let translations = ["NIV", "ESV", "KJV", "NLT", "CSB", "NASB", "MSG", "NKJV"]
    private let radiusOptions: [Double] = [5, 10, 15, 25, 50]

    var body: some View {
        NavigationStack {
            List {
                defaultModeSection
                scriptureSection
                prayerStyleSection
                churchSearchSection
                privacySection
                youthSafetySection
                proactiveSuggestionsSection
            }
            .navigationTitle("Berean Drive")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePreferences() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if showSaved {
                    Text("Settings saved")
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.adaptive(.spring(response: 0.4)), value: showSaved)
        }
    }

    // MARK: - Sections

    private var defaultModeSection: some View {
        Section {
            Picker("Default Mode", selection: $preferences.defaultMode) {
                ForEach(BereanDriveMode.allCases.filter { $0 != .home }, id: \.self) { mode in
                    Text(mode.displayTitle).tag(mode)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Drive Experience")
        } footer: {
            Text("Berean Drive opens to this mode when CarPlay connects.")
        }
    }

    private var scriptureSection: some View {
        Section("Scripture") {
            Picker("Translation", selection: $preferences.preferredScriptureTranslation) {
                ForEach(translations, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var prayerStyleSection: some View {
        Section("Prayer Style") {
            Picker("Style", selection: $preferences.prayerStyle) {
                ForEach(BereanDrivePrayerStyle.allCases, id: \.self) { style in
                    Text(style.displayTitle).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var churchSearchSection: some View {
        Section {
            Picker("Search Radius", selection: $preferences.churchSearchRadiusMiles) {
                ForEach(radiusOptions, id: \.self) { r in
                    Text("\(Int(r)) miles").tag(r)
                }
            }
            .pickerStyle(.navigationLink)

            Toggle("Personalize Church Suggestions", isOn: $preferences.churchDiscoveryPersonalizationEnabled)
        } header: {
            Text("Church Search")
        } footer: {
            Text("Personalization uses your Amen church activity. No data leaves the app.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Use Location While Driving", isOn: $preferences.locationPersonalizationEnabled)
            Toggle("Read Messages Aloud", isOn: $preferences.messageReadAloudEnabled)
            Toggle("Share Driving Context with Berean", isOn: $preferences.drivingContextEnabled)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Location is used only to find nearby churches and is never stored. Messages are screened before being read aloud.")
        }
    }

    private var youthSafetySection: some View {
        Section {
            Toggle("Youth Safety Mode", isOn: $preferences.youthSafetyEnabled)
        } header: {
            Text("Youth Safety")
        } footer: {
            Text("Applies stricter content filters across all CarPlay features. Recommended when minors may be in the vehicle.")
        }
    }

    private var proactiveSuggestionsSection: some View {
        Section {
            Toggle("Proactive Suggestions", isOn: $preferences.proactiveSuggestionsEnabled)
        } header: {
            Text("Suggestions")
        } footer: {
            Text("Allow Berean Drive to suggest prayers and reflections based on time of day and recent Amen activity.")
        }
    }

    // MARK: - Save

    private func savePreferences() {
        preferences.save()
        withAnimation(reduceMotion ? nil : .default) { showSaved = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { withAnimation(reduceMotion ? nil : .default) { showSaved = false } }
        }
    }
}

// MARK: - "Resume in CarPlay" Banner

/// Shown inside the main Amen app when a relevant session is active
/// that could continue in CarPlay.
struct BereanDriveResumeBanner: View {
    let surface: BereanDriveContinuationSurface
    let onResume: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Continue in Berean Drive")
                    .font(.subheadline.weight(.semibold))
                Text(surfaceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Continue") { onResume() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var surfaceLabel: String {
        switch surface {
        case .bereanConversation: return "Your Berean conversation"
        case .churchNotes:        return "Church notes recap"
        case .sermonAudio:        return "Sermon audio"
        case .savedChurch:        return "Saved church details"
        case .prayerSession:      return "Prayer session"
        }
    }
}

#if DEBUG
#Preview("Setup") {
    BereanDriveSetupView()
}

#Preview("Resume Banner") {
    BereanDriveResumeBanner(
        surface: .bereanConversation,
        onResume: {},
        onDismiss: {}
    )
    .padding()
}
#endif
