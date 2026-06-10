// AILAccessibilitySettingsSection.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// A SwiftUI settings group for embedding inside any Form/List. It binds directly
// to AILProfileService.shared.profile (an @Observable singleton that persists to
// UserDefaults and syncs to Firestore), so every choice follows the account.
//
// Mirrors the structure/look of AmenSimpleModeSettingsSection.swift: top-aligned
// SF Symbol + a title row + a one-line plain-language explanation per control.
//
// IRON RULES (do not relax):
//  • Accessibility is FREE at every tier. No copy implies an upgrade or paywall,
//    and there are NO tier checks anywhere in this view.
//  • Profile portability: this view owns no state of its own — it only reads and
//    writes AILProfileService.shared, which already handles persistence + sync.
//  • Plain-language copy throughout — no jargon.
//  • Reduce Transparency → opaque surfaces (no glass when that setting is on).

import SwiftUI

// MARK: - AILAccessibilitySettingsSection

struct AILAccessibilitySettingsSection: View {

    /// The frozen, account-synced profile service. Mutations persist automatically.
    @State private var service = AILProfileService.shared

    /// Honor system accessibility preference: prefer opaque surfaces when set.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Presentation flags for the linked flows.
    @State private var showSetup = false
    @State private var showCalibration = false

    var body: some View {
        // @Bindable lets us build SwiftUI bindings from the @Observable service.
        @Bindable var bindable = service

        Section {
            readingLevelRow(bindable)
            autoTranslateRow(bindable)
            toneHintsRow(bindable)
            calmModeRow(bindable)
            touchTargetsRow(bindable)
            voiceNavRow(bindable)
        } header: {
            Text("Reading & Understanding")
        } footer: {
            Text("These settings are free for everyone and you can change them at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        sensitivitySection
        toolsSection
    }

    // MARK: - Rows: Reading & Understanding

    private func readingLevelRow(_ bindable: AILProfileService) -> some View {
        Picker(selection: Binding(
            get: { service.profile.readingLevel },
            set: { service.setReadingLevel($0) }
        )) {
            ForEach(ReadingLevel.allCases, id: \.self) { level in
                Text(level.displayName).tag(level)
            }
        } label: {
            settingLabel(
                symbol: "textformat.alt",
                title: "Reading Level",
                detail: "Rewrite posts in plainer words, or keep them as written."
            )
        }
        .accessibilityHint("Choose how plainly posts are written for you. Original keeps the author's words.")
    }

    private func autoTranslateRow(_ bindable: AILProfileService) -> some View {
        Toggle(isOn: Binding(
            get: { service.profile.autoTranslate },
            set: { service.setAutoTranslate($0) }
        )) {
            settingLabel(
                symbol: "character.bubble",
                title: "Translate Automatically",
                detail: "Show posts in your language when they're written in another one."
            )
        }
        .accessibilityHint("When on, posts in other languages are translated for you automatically.")
    }

    private func toneHintsRow(_ bindable: AILProfileService) -> some View {
        Toggle(isOn: Binding(
            get: { service.profile.toneHintsEnabled },
            set: { service.setToneHints($0) }
        )) {
            settingLabel(
                symbol: "face.smiling",
                title: "Tone Hints",
                // Iron rule 7: tone hints are opt-in and default OFF.
                detail: "Optional. A gentle note about the feeling behind a message. Off by default."
            )
        }
        .accessibilityHint("Optional. When on, you may see a gentle hint about the tone of a message.")
    }

    private func calmModeRow(_ bindable: AILProfileService) -> some View {
        Toggle(isOn: Binding(
            get: { service.profile.calmMode },
            set: { service.setCalmMode($0) }
        )) {
            settingLabel(
                symbol: "leaf",
                title: "Calm Mode",
                detail: "A quieter screen with less motion and fewer things competing for attention."
            )
        }
        .accessibilityHint("When on, the app uses calmer visuals with less movement.")
    }

    private func touchTargetsRow(_ bindable: AILProfileService) -> some View {
        Picker(selection: Binding(
            get: { service.profile.largerTouchTargets },
            set: { service.setTouchTargets($0) }
        )) {
            ForEach(A11yProfile.TouchTargets.allCases, id: \.self) { size in
                Text(touchTargetName(size)).tag(size)
            }
        } label: {
            settingLabel(
                symbol: "hand.point.up.left",
                title: "Bigger Buttons",
                detail: "Make buttons and tap areas larger so they're easier to reach."
            )
        }
        .accessibilityHint("Choose larger tap areas to make buttons easier to press.")
    }

    private func voiceNavRow(_ bindable: AILProfileService) -> some View {
        Toggle(isOn: Binding(
            get: { service.profile.voiceNavEnabled },
            set: { service.setVoiceNav($0) }
        )) {
            settingLabel(
                symbol: "mic",
                title: "Move Around by Voice",
                detail: "Use simple spoken commands to get around the app, hands-free."
            )
        }
        .accessibilityHint("When on, you can navigate the app using your voice.")
    }

    // MARK: - Section: Topics to ease in on

    private var sensitivitySection: some View {
        Section {
            ForEach(SensitivityTopic.allCases) { topic in
                Button {
                    service.toggleSensitivity(topic)
                } label: {
                    HStack {
                        settingLabel(
                            symbol: symbol(for: topic),
                            title: topic.displayName,
                            detail: detail(for: topic)
                        )
                        Spacer(minLength: 12)
                        if service.profile.sensitivityFilters.contains(topic) {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(
                    service.profile.sensitivityFilters.contains(topic) ? [.isButton, .isSelected] : .isButton
                )
                .accessibilityHint("Double-tap to gently ease in on \(topic.displayName.lowercased()) topics.")
            }
        } header: {
            Text("Topics to Ease In On")
        } footer: {
            Text("Pick any topics you'd like a gentle heads-up before. You'll still choose whether to look — nothing is hidden from you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Section: Setup & calibration links

    private var toolsSection: some View {
        Section {
            Button {
                showSetup = true
            } label: {
                settingLabel(
                    symbol: "sparkles",
                    title: "Set Up These Options",
                    detail: "Walk through everything step by step in plain language."
                )
            }
            .accessibilityHint("Opens a short, friendly walkthrough of these settings.")

            Button {
                showCalibration = true
            } label: {
                settingLabel(
                    symbol: "target",
                    title: "Find Your Button Size",
                    detail: "A quick on-device check to pick a comfortable tap size. Stays on your phone."
                )
            }
            .accessibilityHint("Opens an on-device check to help choose a comfortable button size.")
        } header: {
            Text("Helpful Tools")
        } footer: {
            Text("Everything here is free for everyone. Change it whenever you like.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showSetup) {
            AILAccessibilitySetupView()
        }
        .sheet(isPresented: $showCalibration) {
            // The calibration view is owned by the Interaction lane (C9). When it
            // isn't present in a target, this lightweight placeholder keeps the
            // section self-contained and parse-clean. Result lands as a plain
            // `largerTouchTargets` preference — no metrics leave the device.
            AILTouchTargetCalibrationPlaceholder()
        }
    }

    // MARK: - Shared label builder (mirrors AmenSimpleModeSettingsSection)

    private func settingLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Plain-language helpers

    private func touchTargetName(_ value: A11yProfile.TouchTargets) -> String {
        switch value {
        case .off:   return "Normal"
        case .large: return "Large"
        case .xl:    return "Extra Large"
        }
    }

    private func symbol(for topic: SensitivityTopic) -> String {
        switch topic {
        case .grief:    return "heart"
        case .conflict: return "exclamationmark.bubble"
        case .politics: return "building.columns"
        case .trauma:   return "bandage"
        case .graphic:  return "eye.slash"
        }
    }

    private func detail(for topic: SensitivityTopic) -> String {
        switch topic {
        case .grief:    return "A soft heads-up before posts about loss."
        case .conflict: return "A soft heads-up before heated back-and-forth."
        case .politics: return "A soft heads-up before political posts."
        case .trauma:   return "A soft heads-up before posts about hard experiences."
        case .graphic:  return "A soft heads-up before strong or graphic images."
        }
    }
}

// MARK: - Calibration placeholder

/// Minimal, self-contained stand-in for the C9 on-device calibration flow so this
/// settings section parses and runs on its own. Writes only the resulting size
/// PREFERENCE — never any motor metrics (iron rule 5).
private struct AILTouchTargetCalibrationPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = AILProfileService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pick the size that feels easiest to tap. We test it right here on your phone — nothing about how you tap is ever saved or sent.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Section("Button Size") {
                    ForEach(A11yProfile.TouchTargets.allCases, id: \.self) { size in
                        Button {
                            service.setTouchTargets(size)
                            dismiss()
                        } label: {
                            HStack {
                                Text(name(for: size))
                                Spacer()
                                if service.profile.largerTouchTargets == size {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Find Your Button Size")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func name(for value: A11yProfile.TouchTargets) -> String {
        switch value {
        case .off:   return "Normal"
        case .large: return "Large"
        case .xl:    return "Extra Large"
        }
    }
}

// MARK: - Preview

#Preview("AILAccessibilitySettingsSection") {
    NavigationStack {
        Form {
            AILAccessibilitySettingsSection()
        }
        .navigationTitle("Accessibility")
    }
}
