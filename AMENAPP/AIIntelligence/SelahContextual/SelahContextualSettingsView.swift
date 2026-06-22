import SwiftUI

// MARK: - Selah Contextual Settings
// The user-facing controls for the contextual intelligence engine: which features may
// surface, how interruptible Selah is, the chosen Sabbath day, and per-signal consent.
// The master + cluster gates live in Remote Config; this screen shows their availability
// and lets the user shape what they've been given. It writes only to the controller's
// persisted preferences — it never flips a Remote Config flag.

struct SelahContextualSettingsView: View {
    @ObservedObject private var controller = SelahContextualController.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        Form {
            availabilitySection

            if flags.selahContextualEnabled {
                toleranceSection
                sabbathSection
                ForEach(SelahContextualCluster.allCases, id: \.self) { cluster in
                    clusterSection(cluster)
                }
                permissionsSection
            }
        }
        .navigationTitle("Contextual Selah")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Availability

    private var availabilitySection: some View {
        Section {
            HStack {
                Image(systemName: flags.selahContextualEnabled ? "checkmark.seal.fill" : "lock.fill")
                    .foregroundStyle(flags.selahContextualEnabled ? .green : .secondary)
                Text(flags.selahContextualEnabled ? "Contextual Selah is available" : "Not yet enabled")
                    .font(.subheadline)
            }
        } footer: {
            Text("Selah's ambient intelligence is mic-free, on-device, and confidence-gated. It earns the right to interrupt by being right, consented, and quiet. Each cluster is turned on remotely as it's verified.")
        }
    }

    // MARK: Tolerance

    private var toleranceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Interrupt tolerance")
                    Spacer()
                    Text(toleranceLabel)
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { controller.preferences.interruptTolerance },
                        set: { controller.setInterruptTolerance($0) }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Interrupt tolerance")
            }
        } footer: {
            Text("Lower means Selah stays silent unless it's very sure. Confidence-gated silence is a feature, not a fallback.")
        }
    }

    private var toleranceLabel: String {
        switch controller.preferences.interruptTolerance {
        case ..<0.34: return "Rarely"
        case ..<0.67: return "Balanced"
        default:      return "Open"
        }
    }

    // MARK: Sabbath

    private var sabbathSection: some View {
        Section {
            Picker(
                "Sabbath day",
                selection: Binding(
                    get: { controller.preferences.chosenSabbathWeekday ?? 0 },
                    set: { controller.setSabbathWeekday($0 == 0 ? nil : $0) }
                )
            ) {
                Text("None").tag(0)
                ForEach(1...7, id: \.self) { weekday in
                    Text(weekdayName(weekday)).tag(weekday)
                }
            }
        } footer: {
            Text("On your Sabbath, Selah gets quieter — prompts are silenced and only a single rest surface may appear.")
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = weekday - 1
        return (index >= 0 && index < symbols.count) ? symbols[index] : "Day \(weekday)"
    }

    // MARK: Clusters / features

    @ViewBuilder
    private func clusterSection(_ cluster: SelahContextualCluster) -> some View {
        let clusterOn = SelahContextualFlags.isClusterEnabled(cluster)
        Section {
            ForEach(features(in: cluster), id: \.self) { feature in
                Toggle(isOn: Binding(
                    get: { controller.preferences.enabledFeatures.contains(feature) },
                    set: { controller.setFeatureEnabled(feature, $0) }
                )) {
                    Text(feature.displayName)
                }
                .disabled(!clusterOn || !SelahContextualFlags.sensitiveOverrideSatisfied(for: feature))
            }
        } header: {
            Text(clusterName(cluster))
        } footer: {
            if !clusterOn {
                Text("This cluster isn't enabled yet.")
            }
        }
    }

    private func features(in cluster: SelahContextualCluster) -> [SelahContextualFeature] {
        SelahContextualFeature.allCases.filter { $0.cluster == cluster }
    }

    private func clusterName(_ cluster: SelahContextualCluster) -> String {
        switch cluster {
        case .inTheRoom:      return "In the Room"
        case .acrossTheWeek:  return "Across the Week"
        case .flowOfLife:     return "In the Flow of Life"
        case .restraintSpine: return "Rest & Restraint"
        case .trustAndDepth:  return "Trust & Depth"
        }
    }

    // MARK: Permissions / consent

    private var permissionsSection: some View {
        Section {
            ForEach(SelahContextualPermission.allCases, id: \.self) { permission in
                Toggle(isOn: Binding(
                    get: { controller.preferences.grantedPermissions.contains(permission) },
                    set: { controller.setPermissionGranted(permission, $0) }
                )) {
                    Text(permissionName(permission))
                }
            }
        } header: {
            Text("Signals you allow")
        } footer: {
            Text("Each signal is opt-in. Turning one on here records your consent; sensitive signals (Photos, Screen Time, Health) also require their own system permission and remote enablement.")
        }
    }

    private func permissionName(_ permission: SelahContextualPermission) -> String {
        switch permission {
        case .camera:              return "Camera (bulletin & slide capture)"
        case .calendar:            return "Calendar (small-group sync)"
        case .groupMembership:     return "Group membership"
        case .foregroundAudio:     return "Foreground audio (worship & sermon)"
        case .motionOrCarPlay:     return "Motion / CarPlay (commute)"
        case .locationCategory:    return "Place awareness"
        case .sermonHistory:       return "Sermon history"
        case .clipboardOrShareSheet: return "Clipboard & share sheet"
        case .photos:              return "Photos (memory anchoring)"
        case .socialGraph:         return "Social graph (prayer radar)"
        case .socialPresence:      return "Reading presence"
        case .screenTime:          return "Screen Time (doomscroll off-ramp)"
        case .health:              return "Health (stress-aware rest)"
        }
    }
}
