// AILProvenanceLabel.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Language Surface (A3)
//
// SHARED tiny views reused across every AIL language surface (and by other AIL
// agents). Two iron-rule primitives live here so they are defined once:
//
//   • AILProvenanceLabel  — the small pill that LABELS every AI output
//     (iron rule: every AI output shows provenance).
//   • AILViewOriginalButton — the one-tap "View original" control
//     (iron rule: every transform is reversible to the original).
//
// These are intentionally `internal` (module-visible) so the other AIL files in
// this module reuse them rather than re-rolling their own.
//
// No tier checks anywhere — accessibility is free at every tier.
// Honors Reduce Transparency (opaque fallback) and Reduce Motion.

import SwiftUI

// MARK: - Provenance pill

/// A small, quiet pill that surfaces the provenance label of an AI transform.
/// Rendered beneath every AI-produced string in the language surfaces.
struct AILProvenanceLabel: View {
    let provenance: A11yProvenance

    /// Reduce Transparency collapses the glass material to an OPAQUE fill.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label {
            Text(provenance.label)
                .font(.caption2.weight(.medium))
        } icon: {
            Image(systemName: iconName)
                .font(.caption2)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(pillBackground)
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Source: \(provenance.label)"))
    }

    private var iconName: String {
        switch provenance {
        case .aiGenerated:   return "sparkles"
        case .aiHumanEdited: return "sparkles"
        case .human:         return "person"
        }
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            // Opaque fallback — no glass when transparency is reduced.
            Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }
}

// MARK: - View original

/// One-tap control to reverse any transform back to the original content.
/// Caller owns the toggle state; this view only fires `action`.
struct AILViewOriginalButton: View {
    /// When true, the control reads "Show translation" so the same button can
    /// toggle both directions. Defaults to the "View original" affordance.
    var isShowingOriginal: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityHint(Text("Switches between the original and the transformed text."))
    }

    private var title: String {
        isShowingOriginal ? "Show translation" : "View original"
    }
}
