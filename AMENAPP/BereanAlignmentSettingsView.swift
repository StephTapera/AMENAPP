import SwiftUI

struct BereanAlignmentSettingsView: View {
    @AppStorage("berean_alignment_lens") private var defaultLensRaw = AlignmentLens.balancedBiblical.rawValue
    @AppStorage("berean_discernment_mode") private var discernmentModeRaw = DiscernmentMode.auto.rawValue
    @AppStorage("berean_scripture_preference") private var scripturePreference = "only_when_relevant"
    @AppStorage("berean_correction_memory") private var correctionMemoryEnabled = true
    @AppStorage("berean_weekly_summary") private var weeklySummaryEnabled = true
    @AppStorage("berean_simple_mode") private var simpleModeEnabled = false
    @AppStorage("berean_explicit_protection") private var explicitProtectionEnabled = true
    @AppStorage("berean_exploitation_protection") private var exploitationProtectionEnabled = true
    @AppStorage("berean_preferred_tone") private var preferredTone = "pastoral"

    @State private var isSaving = false

    private var defaultLens: AlignmentLens {
        get { AlignmentLens(rawValue: defaultLensRaw) ?? .balancedBiblical }
        set { defaultLensRaw = newValue.rawValue }
    }

    private var discernmentMode: DiscernmentMode {
        get { DiscernmentMode(rawValue: discernmentModeRaw) ?? .auto }
        set { discernmentModeRaw = newValue.rawValue }
    }

    var body: some View {
        Form {
            Section("Mode") {
                Toggle("Simple Mode", isOn: $simpleModeEnabled)
                Picker("Discernment Mode", selection: Binding(
                    get: { DiscernmentMode(rawValue: discernmentModeRaw) ?? .auto },
                    set: { discernmentModeRaw = $0.rawValue }
                )) {
                    ForEach(DiscernmentMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                Picker("Default Lens", selection: Binding(
                    get: { AlignmentLens(rawValue: defaultLensRaw) ?? .balancedBiblical },
                    set: { defaultLensRaw = $0.rawValue }
                )) {
                    ForEach(AlignmentLens.allCases) { lens in
                        Text(lens.title).tag(lens)
                    }
                }
            }

            Section("Preferences") {
                Picker("Scripture Preference", selection: $scripturePreference) {
                    Text("Always").tag("always")
                    Text("Ask").tag("ask")
                    Text("Only When Relevant").tag("only_when_relevant")
                    Text("Off").tag("off")
                }
                Toggle("Correction Memory", isOn: $correctionMemoryEnabled)
                Toggle("Weekly Summary", isOn: $weeklySummaryEnabled)
            }

            Section("Protection") {
                Toggle("Explicit Content Protection", isOn: $explicitProtectionEnabled)
                Toggle("Exploitation Protection", isOn: $exploitationProtectionEnabled)
            }

            Section("Tone") {
                Picker("Preferred Tone", selection: $preferredTone) {
                    Text("Pastoral").tag("pastoral")
                    Text("Calm").tag("calm")
                    Text("Direct").tag("direct")
                    Text("Concise").tag("concise")
                    Text("Study").tag("study")
                }
            }
        }
        .navigationTitle("AI Alignment")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            _ = try? await BiblicalAlignmentService.shared.updateAlignmentProfile(
                defaultLens: defaultLens,
                discernmentMode: discernmentMode,
                scripturePreference: scripturePreference,
                correctionMemoryEnabled: correctionMemoryEnabled,
                weeklySummaryEnabled: weeklySummaryEnabled,
                simpleModeEnabled: simpleModeEnabled,
                explicitContentProtectionEnabled: explicitProtectionEnabled,
                exploitationProtectionEnabled: exploitationProtectionEnabled,
                preferredTone: preferredTone
            )
            isSaving = false
        }
    }
}
