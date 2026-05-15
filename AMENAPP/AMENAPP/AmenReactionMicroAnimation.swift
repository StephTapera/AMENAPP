// AmenReactionMicroAnimation.swift
// AMENAPP
//
// Droplet-snap landing animation for reaction badges.
// Lands from slightly above with spring overshoot.
// Purely visual — no Firestore writes, no state mutations.

import SwiftUI

struct AmenReactionLandingModifier: ViewModifier {
    let isLanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: (!isLanded && !reduceMotion) ? -6 : 0)
            .scaleEffect(isLanded ? 1.0 : 0.4, anchor: .bottom)
            .opacity(isLanded ? 1.0 : 0.0)
    }
}

extension View {
    func amenReactionLanding(isLanded: Bool) -> some View {
        modifier(AmenReactionLandingModifier(isLanded: isLanded))
    }
}
