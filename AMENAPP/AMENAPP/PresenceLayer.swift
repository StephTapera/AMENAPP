// PresenceLayer.swift
// AMENAPP
//
// Phase 3 — Spatial Social OS.
// Lightweight indicator that surfaces "co-presence" — how many other people
// are currently looking at the same media. Phase 3 ships the surface shell
// only. Phase 5 wires it to the `presenceSessions` collection. Until then
// the view renders nothing unless an explicit `coViewerCount` is supplied
// (used by integration tests and previews).
//
// Liquid Glass:
//   - Capsule with .ultraThinMaterial (Reduce Transparency falls back to
//     Color(.secondarySystemBackground))
//   - No glass-on-glass — host this directly on a media background
//   - No animation when Reduce Motion is on
//
// Trust contract:
//   - Presence is shown only when AMENFeatureFlags.shared.sharedViewingEnabled
//     is true AND the count is > 0.
//   - Never name individual co-viewers in this compact view. A future
//     PresenceRoster sheet (Phase 5) can show names with explicit consent.

import SwiftUI

struct PresenceLayer: View {

    // MARK: Inputs

    /// Stable identifier for the media being viewed.
    let mediaId: String

    /// Optional explicit override (mainly for previews and tests). When nil
    /// the view defers to its model, which is currently a stub until
    /// presenceSessions wiring lands in Phase 5.
    var coViewerCount: Int? = nil

    // MARK: Environment

    @ObservedObject private var flags = AMENFeatureFlags.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State

    @StateObject private var model = PresenceLayerModel()

    // MARK: Body

    var body: some View {
        Group {
            if flags.sharedViewingEnabled, effectiveCount > 0 {
                capsule
                    .transition(
                        reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96))
                    )
            } else {
                EmptyView()
            }
        }
        .task(id: mediaId) {
            await model.refresh(mediaId: mediaId)
        }
    }

    private var effectiveCount: Int {
        coViewerCount ?? model.coViewerCount
    }

    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(layerBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        let n = effectiveCount
        return n == 1 ? "1 other viewing" : "\(n) viewing"
    }

    private var accessibilityLabel: String {
        let n = effectiveCount
        return n == 1
            ? "One other person is viewing this media."
            : "\(n) other people are viewing this media."
    }

    private var layerBackground: some View {
        Group {
            if reduceTransparency {
                Color(.secondarySystemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - PresenceLayerModel

/// Stub model. Phase 5 will replace `refresh` with a real Firestore listener
/// on `presenceSessions where mediaId == ? and active == true`. Reading
/// presence from the client is allowed by rules; writes happen server-side
/// via a Cloud Function.
@MainActor
final class PresenceLayerModel: ObservableObject {
    @Published private(set) var coViewerCount: Int = 0

    func refresh(mediaId: String) async {
        // No-op until Phase 5. Leaving this surface here so the compose-in
        // point exists in every immersive media viewer ahead of time.
        _ = mediaId
    }
}

#if DEBUG
#Preview("Presence — 3 viewing (flag forced on)") {
    ZStack {
        Color.black
        PresenceLayer(mediaId: "preview_media", coViewerCount: 3)
            .padding()
    }
}
#endif
