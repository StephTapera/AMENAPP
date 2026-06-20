// SabbathRhythmSubtraction.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 0)
//
// The ONE mechanism that removes Selah UI during Sabbath (Invariant I3). Any surface
// that should quiet in `.rest` adopts `.sabbathSubtracted(.feeds)` etc. The modifier
// reads the active SabbathSubtractionPolicy — no surface decides to hide on its own.
//
// Inert unless `sabbath_mode_enabled` is ON and the active policy removes the field.

import SwiftUI

private struct SabbathSubtractionModifier: ViewModifier {
    let field: SabbathSubtractionField

    @ObservedObject private var controller = SabbathRhythmController.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared

    private var isRemoved: Bool {
        guard flags.sabbathModeEnabled else { return false }
        return field.isRemoved(by: controller.activePolicy)
    }

    func body(content: Content) -> some View {
        if isRemoved {
            // Removal, not decoration: the field is taken off-screen entirely.
            EmptyView()
        } else {
            content
        }
    }
}

extension View {
    /// Remove this surface while the active Sabbath policy subtracts `field` (I3).
    /// No-op when Sabbath Mode is off or the state is `.normal`.
    func sabbathSubtracted(_ field: SabbathSubtractionField) -> some View {
        modifier(SabbathSubtractionModifier(field: field))
    }
}
