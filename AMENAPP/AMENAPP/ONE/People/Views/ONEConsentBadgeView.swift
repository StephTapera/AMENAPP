// ONEConsentBadgeView.swift
// ONE — Per-message consent DNA badge shown below outgoing bubbles.

import SwiftUI

struct ONEConsentBadgeView: View {
    let permissions: ONEMomentPermissions

    private var label: String {
        var parts: [String] = []
        if !permissions.saveAllowed    { parts.append("No save") }
        if !permissions.forwardAllowed { parts.append("No forward") }
        if !permissions.quoteAllowed   { parts.append("No quote") }
        if permissions.reactAllowed    { parts.append("React ✓") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if !label.isEmpty {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ONE.Colors.privateIndigo.opacity(0.8))
                .accessibilityLabel("Message consent: \(label)")
        }
    }
}
