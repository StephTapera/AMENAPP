
//  ChurchNotesDiscipleshipSurfaces.swift
//  AMENAPP
//
//  W5 — Glanceable qualitative surfaces: Sunday Reflection card + formation view.
//  No counts that can decrease. No streaks. Decay-aware. Dismissable. (S9)
//  Confidential notes never appear here. (S1)
//

import SwiftUI

// MARK: - Sunday Reflection Card

/// A glanceable card shown in the main feed or on the lock screen widget.
/// Never shows a count. Never shows a streak. Qualitative only.
struct ChurchNotesSundayReflectionCard: View {

    let action: SpiritualAction          // single highlighted action, pre-screened (non-confidential)
    let onDismiss: () -> Void
    let onOpenNote: () -> Void

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                summaryText
                actionRow
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
    }

    private var headerRow: some View {
        HStack {
            Label("Sunday Reflection", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.amenGold)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss reflection card")
        }
    }

    private var summaryText: some View {
        Text(action.summary)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .accessibilityLabel("Reflection: \(action.summary)")
    }

    private var actionRow: some View {
        Button {
            onOpenNote()
        } label: {
            Label(action.kind.defaultSummary, systemImage: action.kind.sfSymbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.amenPurple)
        }
        .accessibilityHint("Opens your church notes to continue this action.")
    }
}

// MARK: - Berean Island Card

/// Compact card for the Berean Island / Live Activity region.
/// Glanceable, dismissable. No counts. (S9)
struct ChurchNotesBereanIslandCard: View {

    let action: SpiritualAction
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.kind.sfSymbol)
                .font(.title3)
                .foregroundStyle(Color.amenGold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("From your notes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(action.summary)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean Island: \(action.summary)")
    }
}

// MARK: - Formation View (qualitative — no counts)

/// Qualitative formation surface. Displays recent actions in a word-based
/// visual — no charts, no tallies, no streak indicators. (S9)
struct ChurchNotesDiscipleshipFormationView: View {

    let actions: [SpiritualAction]    // pre-screened: no confidential items

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your Spiritual Formation")
                .font(.headline)
                .padding(.horizontal)

            if actions.isEmpty {
                emptyState
            } else {
                themeCloud
                actionList
            }
        }
        .padding(.vertical)
    }

    // MARK: Theme Cloud (qualitative only — no numeric count)

    private var themeCloud: some View {
        let kinds = Array(Set(actions.map(\.kind)))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(kinds, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.sfSymbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.amenPurple.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.amenPurple)
                }
            }
            .padding(.horizontal)
        }
        .accessibilityLabel("Formation themes: \(kinds.map(\.displayName).joined(separator: ", "))")
    }

    // MARK: Action List

    private var actionList: some View {
        LazyVStack(spacing: 12) {
            ForEach(actions.prefix(5)) { action in
                HStack(spacing: 12) {
                    Image(systemName: action.kind.sfSymbol)
                        .foregroundStyle(Color.amenGold)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(action.summary)
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(action.kind.displayName): \(action.summary)")
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.circle")
                .font(.largeTitle)
                .foregroundStyle(Color.amenGold.opacity(0.6))
                .accessibilityHidden(true)
            Text("Your formation story grows as you take notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - ActionKind display name

extension ActionKind {
    var displayName: String {
        switch self {
        case .pray:     return "Prayer"
        case .read:     return "Reading"
        case .reachOut: return "Outreach"
        case .fast:     return "Fasting"
        case .memorize: return "Scripture"
        case .apply:    return "Application"
        case .attend:   return "Gathering"
        }
    }
}

// MARK: - Surface Manager

/// Determines whether a surface can be shown for a given action.
/// Confidential actions are never shown proactively. (S1)
/// Surfaces are decay-aware via the governor.
struct DiscipleshipSurfaceManager {

    private let governor = ChurchNotesNotificationGovernorImpl.shared

    /// Filter actions to only those safe for proactive surfaces.
    func surfaceableActions(from actions: [SpiritualAction]) -> [SpiritualAction] {
        actions.filter { $0.sensitivity != .confidential }
    }

    /// Best single action for the Island card (most recent non-confidential).
    func islandAction(from actions: [SpiritualAction]) -> SpiritualAction? {
        surfaceableActions(from: actions).first
    }
}
