// BereanAgentSurface.swift
// AMEN — Berean Agent Surface (BAS) Wave 4, Lane I
//
// Root coordinator view that wires all BereanAgent sub-surfaces together.
// Design §2: Liquid Glass native APIs, warm paper bg, wine-red accent (one per screen),
//            24pt card corners, soft shadows. SF system font. Fully accessible.
// All animations gated by @Environment(\.accessibilityReduceMotion).
//
// Lane rule: ONLY writes to BereanAgent/. No outside-lane references.
// Type prefix: BAS* for all new types in this file.

import SwiftUI

// MARK: - BereanAgentSurface

/// Root coordinator that assembles all BAS sub-surfaces into a single composed view.
/// Owns top-level state and routes composer actions to the appropriate sub-surface.
@MainActor
struct BereanAgentSurface: View {

    // MARK: State

    @State private var activeMode: BASComposerMode = .ask
    @State private var composerText: String = ""
    @State private var showPluginDrawer: Bool = false
    @State private var activePlugin: BASPluginID? = nil
    @State private var showSafetyLayer: Bool = false
    @State private var pendingAudit: BASSafetyAudit? = nil
    @State private var safetyService = BereanAgentSafetyService()
    @State private var agentIsRunning: Bool = false
    @State private var activeAgentPlugins: [BASPlugin] = []

    // Observed directly so permission changes propagate without environment injection.
    @State private var broker = BASPermissionBroker.shared

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Full-height content column ────────────────────────────────
            VStack(spacing: 0) {
                BereanAgentTopBarView(activeMode: $activeMode)
                    .padding(.top, 8)

                modeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // ── Floating composer anchored above keyboard ─────────────────
            BereanAgentComposerView(
                onSend: { text, mode in
                    handleSend(text: text, mode: mode)
                },
                onPluginDrawerRequested: {
                    withAnimation(
                        reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                    ) {
                        showPluginDrawer = true
                    }
                },
                onVoiceRequested: {
                    // Voice input: wired to future VoiceOS integration (Wave 5+).
                }
            )
            .padding(.bottom, 8)

            // ── Plugin Drawer — slides up from bottom ─────────────────────
            if showPluginDrawer {
                BereanAgentPluginDrawerView(
                    onPluginSelected: { id in
                        activePlugin = id
                        withAnimation(
                            reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                        ) {
                            showPluginDrawer = false
                        }
                    },
                    onDismiss: {
                        withAnimation(
                            reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                        ) {
                            showPluginDrawer = false
                        }
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                .zIndex(10)
            }
        }
        .background(Color.basWarmPaper.ignoresSafeArea())
        // ── Safety Layer sheet ────────────────────────────────────────────
        .sheet(isPresented: $showSafetyLayer) {
            if let audit = pendingAudit {
                BereanAgentSafetyLayerView(
                    audit: audit,
                    onShare: {
                        showSafetyLayer = false
                    },
                    onRevise: {
                        showSafetyLayer = false
                    },
                    onCancel: {
                        showSafetyLayer = false
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .animation(
            reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
            value: showPluginDrawer
        )
    }

    // MARK: Mode-Switched Content

    @ViewBuilder
    private var modeContent: some View {
        switch activeMode {
        case .agent:
            BereanAgentModeView(
                isRunning: agentIsRunning,
                activePlugins: activeAgentPlugins,
                currentTask: composerText,
                pastTasks: [],
                onTaskSuggestionTapped: { suggestion in
                    composerText = suggestion
                },
                onFocusComposer: {
                    // Focus hint: composer is always visible; no keyboard forcing needed.
                },
                onCancel: {
                    withAnimation(
                        reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                    ) {
                        agentIsRunning = false
                        activeAgentPlugins = []
                    }
                }
            )
            .transition(.opacity)

        default:
            // All other modes: content area for Wave 5+ surface mounting.
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear.frame(height: 1)
            }
            .transition(.opacity)
        }
    }

    // MARK: Send Handler

    /// Routes a composer send to the appropriate pipeline based on mode.
    private func handleSend(text: String, mode: BASComposerMode) {
        composerText = text

        switch mode {
        case .post:
            // Post mode: run safety audit before sharing.
            Task {
                let audit = await safetyService.runAudit(
                    content: text,
                    isInterpretation: false
                )
                await MainActor.run {
                    pendingAudit = audit
                    showSafetyLayer = true
                }
            }

        case .agent:
            // Agent mode: activate plugins for the mode's toolset.
            withAnimation(
                reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
            ) {
                agentIsRunning = true
                activeAgentPlugins = resolvePlugins(for: mode)
            }

        default:
            // All other modes (ask, study, pray, create, research, summarize):
            // pass-through to backend in Wave 5+.
            break
        }
    }

    /// Resolves BASPlugin instances from the registry for a given mode's toolset.
    private func resolvePlugins(for mode: BASComposerMode) -> [BASPlugin] {
        let registry = BASPluginRegistry.shared
        return mode.toolset.compactMap { pluginID in
            registry.plugins.first(where: { $0.id == pluginID })
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("BereanAgentSurface — Ask") {
    BereanAgentSurface()
}

#Preview("BereanAgentSurface — Agent running") {
    BereanAgentSurface()
}
#endif
