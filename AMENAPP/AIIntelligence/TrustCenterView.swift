// TrustCenterView.swift
// AMENAPP
//
// Trust & Transparency hub — one place that links every Trust/Transparency surface
// built in Waves 1–6. Each row is gated by its own feature flag (default OFF), so
// the hub is empty until a flag is flipped on (fail-closed, honest).
//
// Surfaces that live inline elsewhere (the AI Receipt under Berean answers, the
// provenance badge and "why am I seeing this" in the feed) are noted here but
// rendered at their real call sites.
//
// Gated for display by any Trust flag being on.

import SwiftUI

struct TrustCenterView: View {
    private var flags: AMENFeatureFlags { .shared }

    var body: some View {
        List {
            Section {
                if flags.moderationAuditTrailEnabled {
                    NavigationLink { ModerationTimelineView() } label: {
                        row("Moderation timeline", "Every action on your content, and why", "shield.lefthalf.filled")
                    }
                }
                if flags.constitutionalModerationEnabled && !flags.moderationAuditTrailEnabled {
                    row("Constitutional moderation", "Decisions name the principle invoked", "scalemass")
                }
            } header: { Text("Moderation") }

            Section {
                if flags.memoryLedgerEnabled || flags.dataVaultEnabled {
                    NavigationLink { MemoryLedgerView() } label: {
                        row("Berean memory", "View, pause, export, or delete", "brain.head.profile")
                    }
                }
                if flags.aiPermissionsHubEnabled {
                    NavigationLink { AIPermissionsHubView() } label: {
                        row("AI permissions", "What AI can access, on your terms", "switch.2")
                    }
                }
                if SocialV2RuntimeFlags.shared.isSocialV2Enabled {
                    NavigationLink { SocialV2RootView() } label: {
                        row("Social V2", "Spaces, feeds, search, messages, identity, privacy, and vault", "person.3.sequence")
                    }
                }
            } header: { Text("Your data & AI") }

            Section {
                if flags.flourishingMetricsEnabled || flags.focusModesEnabled {
                    NavigationLink { FlourishingFocusView() } label: {
                        row("Flourishing & focus", "Calm metrics, focus and Sabbath modes", "leaf")
                    }
                }
            } header: { Text("Well-being") }

            Section {
                if flags.childSafetySurfaceEnabled {
                    NavigationLink { ChildSafetyControlsView() } label: {
                        row("Child safety", "Teen-safe defaults and guardian controls", "figure.and.child.holdinghands")
                    }
                }
                if flags.redTeamSurfaceEnabled {
                    NavigationLink { RedTeamView() } label: {
                        row("Red team", "Report a moderation, scam, or AI failure", "ant")
                    }
                }
            } header: { Text("Safety & reporting") }

            Section {
                Text("AI Receipts appear under Berean's answers, and content provenance and \u{201C}why am I seeing this\u{201D} appear in your feed, when those features are on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Trust & Transparency")
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.blue)
        }
    }
}

#if DEBUG
#Preview("Trust Center") {
    NavigationStack { TrustCenterView() }
}
#endif
