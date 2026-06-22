// SettingsFlagGate.swift
// AMEN — Settings/Safety system · Foundation
//
// Renders `enabled` content only when the surface's flag is on; otherwise renders
// `disabled` (typically a SettingsDisabledSurface). Observes SettingsFlagsService so
// it reacts live to Remote Config activation.

import SwiftUI

struct SettingsFlagGate<Enabled: View, Disabled: View>: View {
    @ObservedObject private var flags = SettingsFlagsService.shared
    private let flag: SettingsFeatureFlag
    private let enabled: () -> Enabled
    private let disabled: () -> Disabled

    init(
        _ flag: SettingsFeatureFlag,
        @ViewBuilder enabled: @escaping () -> Enabled,
        @ViewBuilder disabled: @escaping () -> Disabled
    ) {
        self.flag = flag
        self.enabled = enabled
        self.disabled = disabled
    }

    var body: some View {
        if flags.isEnabled(flag) {
            enabled()
        } else {
            disabled()
        }
    }
}

extension SettingsFlagGate where Disabled == SettingsDisabledSurface {
    /// Convenience: fall back to the standard disabled surface when the flag is off.
    init(
        _ flag: SettingsFeatureFlag,
        disabledTitle: String,
        disabledReason: String,
        dependency: String,
        @ViewBuilder enabled: @escaping () -> Enabled
    ) {
        self.init(
            flag,
            enabled: enabled,
            disabled: { SettingsDisabledSurface(title: disabledTitle, reason: disabledReason, dependency: dependency) }
        )
    }
}
