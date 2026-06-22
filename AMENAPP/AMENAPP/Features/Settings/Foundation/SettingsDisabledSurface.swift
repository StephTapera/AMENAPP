// SettingsDisabledSurface.swift
// AMEN — Settings/Safety system · Foundation
//
// Standard, safe flag-off / missing-dependency state for any Settings surface.
// Never a dead button, never a crash — a clear, reviewable explanation instead.

import SwiftUI

struct SettingsDisabledSurface: View {
    let title: String
    let reason: String
    /// Name of the backend / dependency this surface waits on (shown to the user in plain copy).
    let dependency: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(title: String, reason: String, dependency: String) {
        self.title = title
        self.reason = reason
        self.dependency = dependency
    }

    var body: some View {
        // TODO(dependency): becomes live once "\(dependency)" is deployed/verified and its flag is enabled.
        SettingsSectionCard(title: title) {
            VStack(alignment: .leading, spacing: SettingsDesignToken.Spacing.small) {
                Label {
                    Text(reason)
                        .font(SettingsDesignToken.Typography.rowTitle)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Text("This will turn on once \(dependency) is ready. Nothing here is active yet.")
                    .font(SettingsDesignToken.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, SettingsDesignToken.Spacing.xSmall)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), not available yet. \(reason)")
    }
}
