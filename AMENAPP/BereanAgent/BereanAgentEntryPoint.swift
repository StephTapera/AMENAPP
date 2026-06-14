// BereanAgentEntryPoint.swift
// AMEN — Berean Agent Surface (BAS) Wave 4, Lane I
//
// Lightweight flag-gated entry point. Checked by the caller before mounting
// BereanAgentSurface into the app's navigation hierarchy.
//
// Flag: AMENFeatureFlags.shared.bereanAgentSurfaceEnabled
//   Default: false (Remote Config key: berean_agent_surface)
//   When false: EmptyView() — zero impact on app graph.
//   When true: BereanAgentSurface() — full BAS coordinator.
//
// Lane rule: ONLY writes to BereanAgent/. No outside-lane references.
// Type prefix: BAS* for all new types in this file.

import SwiftUI

// MARK: - BereanAgentEntryPoint

/// Flag-gated entry point for the Berean Agent Surface.
///
/// Mount this view wherever the surface should appear (e.g., a tab, modal, or
/// sheet destination). It renders nothing when the feature flag is off, so it is
/// safe to include unconditionally in the app's view hierarchy.
///
/// Access pattern mirrors other flag-gated views in this codebase:
///   `@ObservedObject private var flags = AMENFeatureFlags.shared`
struct BereanAgentEntryPoint: View {

    // MARK: Flags

    /// Observed so the view re-renders if Remote Config pushes a flag change at runtime.
    @ObservedObject private var flags = AMENFeatureFlags.shared

    // MARK: Body

    var body: some View {
        if flags.bereanAgentSurfaceEnabled {
            BereanAgentSurface()
        } else {
            // Flagged OFF per §2 and Wave 0 contract. EmptyView is intentional —
            // no placeholder, no skeleton. The surface simply does not exist until
            // the flag is enabled via Remote Config.
            EmptyView()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Entry Point — flag ON (surface direct)") {
    // Simulate flag enabled by previewing the surface directly.
    BereanAgentSurface()
}

#Preview("Entry Point — flag OFF (EmptyView)") {
    // When flagged OFF the entry point renders nothing.
    BereanAgentEntryPoint()
}
#endif
