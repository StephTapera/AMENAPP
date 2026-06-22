// AILReadingUnderstandingSettingsView.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// Form host for AILAccessibilitySettingsSection. The section renders SwiftUI
// `Section`s, which require a Form/List container — this provides it so the
// section can be pushed from the app's Accessibility settings screen.
// No logic of its own; the section binds to AILProfileService.shared.

import SwiftUI

struct AILReadingUnderstandingSettingsView: View {
    var body: some View {
        Form {
            AILAccessibilitySettingsSection()
        }
        .navigationTitle("Reading & Understanding")
        .navigationBarTitleDisplayMode(.inline)
    }
}
