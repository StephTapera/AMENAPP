import SwiftUI

struct BereanPulseCurateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State var preference: BereanPulsePreference
    let permissionManager: BereanPulsePermissionManager
    let onSave: (BereanPulsePreference) -> Void
    let onReset: () -> Void

    private let focusModes: [BereanPulseMode] = [.spiritual, .business, .creative, .work, .wellness, .church, .prayer, .learning, .relationships]
    private let avoidModes: [BereanPulseMode] = [.wellness, .work, .church, .openLoops]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.985, green: 0.985, blue: 0.975)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        savedPreferencesSection
                        focusSection
                        avoidSection
                        contextSourcesSection
                        resetSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(String(localized: "Curate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        onSave(preference)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Memory and context controls"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Choose what Berean should prioritize, suppress, and use as context. System permissions are still requested only when an action needs them."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
    }

    private var savedPreferencesSection: some View {
        curateSection(
            title: String(localized: "Saved preferences"),
            subtitle: String(localized: "These settings shape ranking, tone, and card depth."),
            systemImage: "text.bubble"
        ) {
            Picker(String(localized: "Tone"), selection: $preference.preferredTone) {
                ForEach(BereanPulsePreferredTone.allCases) { tone in
                    Text(tone.rawValue.capitalized).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("Preferred tone"))

            Picker(String(localized: "Length"), selection: $preference.preferredLength) {
                ForEach(BereanPulsePreferredLength.allCases) { length in
                    Text(length.rawValue.capitalized).tag(length)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("Preferred card length"))
        }
    }

    private var focusSection: some View {
        curateSection(
            title: String(localized: "Prioritize"),
            subtitle: String(localized: "Cards in these modes get a small ranking boost."),
            systemImage: "scope"
        ) {
            modeGrid(focusModes, selected: preference.preferredModes) { mode, enabled in
                if enabled {
                    if !preference.preferredModes.contains(mode) { preference.preferredModes.append(mode) }
                } else {
                    preference.preferredModes.removeAll { $0 == mode }
                }
            }
        }
    }

    private var avoidSection: some View {
        curateSection(
            title: String(localized: "Reduce"),
            subtitle: String(localized: "Cards in these modes are still possible, but ranked lower."),
            systemImage: "minus.circle"
        ) {
            modeGrid(avoidModes, selected: preference.suppressedModes) { mode, enabled in
                if enabled {
                    if !preference.suppressedModes.contains(mode) { preference.suppressedModes.append(mode) }
                } else {
                    preference.suppressedModes.removeAll { $0 == mode }
                }
            }
        }
    }

    private var contextSourcesSection: some View {
        curateSection(
            title: String(localized: "Context sources"),
            subtitle: String(localized: "Each source shows what it is used for and can be toggled off."),
            systemImage: "lock.shield"
        ) {
            VStack(spacing: 10) {
                ForEach(BereanPulsePermissionSource.allCases) { source in
                    contextSourceRow(source)
                }
            }
        }
    }

    private var resetSection: some View {
        curateSection(
            title: String(localized: "Clear controls"),
            subtitle: String(localized: "Reset Berean Pulse preferences to the default settings."),
            systemImage: "arrow.counterclockwise"
        ) {
            Button(role: .destructive) {
                preference = .default
                onReset()
            } label: {
                Label(String(localized: "Reset personalization"), systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityHint(Text("Restores default Berean Pulse preferences and saves that reset."))
        }
    }

    private func curateSection<Content: View>(title: String, subtitle: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.05), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
        .accessibilityElement(children: .contain)
    }

    private func modeGrid(_ modes: [BereanPulseMode], selected: [BereanPulseMode], onChange: @escaping (BereanPulseMode, Bool) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(modes, id: \.self) { mode in
                Toggle(isOn: Binding(
                    get: { selected.contains(mode) },
                    set: { onChange(mode, $0) }
                )) {
                    Label(String(localized: mode.titleKey), systemImage: mode.systemImage)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(selected.contains(mode) ? .primary : .secondary)
                .accessibilityHint(Text("Toggles this Berean Pulse mode."))
            }
        }
    }

    private func contextSourceRow(_ source: BereanPulsePermissionSource) -> some View {
        Toggle(isOn: Binding(
            get: { permissionManager.preferenceToggles[source] ?? false },
            set: { permissionManager.setConsent($0, for: source) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(String(localized: source.titleKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    statusPill(for: source)
                }
                Text(String(localized: source.explanationKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.primary)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.75))
        .accessibilityHint(Text(source.requiresSystemPrompt ? "May require an iOS permission prompt when Berean needs this source." : "Controls whether Berean can use this app context source."))
    }

    private func statusPill(for source: BereanPulsePermissionSource) -> some View {
        Text(permissionManager.status(for: source).rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.05), in: Capsule(style: .continuous))
    }

    private var surfaceBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial)
    }
}
