// LongPressableViewModifier.swift
// AMENAPP — Long-Press Intelligence Layer (Wave 1)
//
// Wraps any object card view with:
//   - A long-press gesture that opens LongPressIntelligenceMenu
//   - VoiceOver custom actions as the non-gesture accessibility path
// Apply via .longPressIntelligence(…) on any View.

import SwiftUI

struct LongPressableModifier: ViewModifier {

    let objectType: LongPressObjectType
    let objectId: String
    let surface: LongPressSourceSurface
    let payload: LongPressPayload
    let onAction: (IntelligenceAction) -> Void

    @State private var showMenu: Bool = false
    @State private var activeContext: BereanObjectContext? = nil
    // Centralized result routing (Wave 2): the menu only emits an action; this
    // modifier is the single place that decides which result surface to present.
    @State private var presentedSmartAction: IntelligenceAction? = nil
    @State private var whyPassage: WhyPassage? = nil
    @State private var depthCoordinator: LongPressDepthDialCoordinator? = nil

    func body(content: Content) -> some View {
        guard AMENFeatureFlags.shared.longPressIntelligenceEnabled else {
            return AnyView(content)
        }
        return AnyView(
            content
                // Real long-press (matches the iOS system hold duration). NOT 0 —
                // a 0 duration fires on a plain tap and would hijack navigation taps
                // on every wired surface the moment this flag is flipped ON.
                .onLongPressGesture(minimumDuration: 0.5) {
                    presentIntelligenceMenu()
                }
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: Text("Open intelligence actions")) {
                    presentIntelligenceMenu()
                }
                .overlay {
                    if showMenu, let ctx = activeContext {
                        LongPressIntelligenceMenu(
                            context: ctx,
                            onAction: { action in
                                route(action)
                            },
                            onDismiss: {
                                showMenu = false
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                    }
                }
                // AI action → streaming result surface (self-gates on its own flag).
                .sheet(item: $presentedSmartAction) { action in
                    if let ctx = activeContext, let coordinator = depthCoordinator {
                        LongPressStreamingResultView(
                            action: action,
                            context: ctx,
                            depthState: coordinator.dialState,
                            onDepthChange: { newDepth in coordinator.overrideDepth(newDepth) },
                            onDismiss: { presentedSmartAction = nil }
                        )
                    }
                }
                // "Ask Berean Why" → dedicated five-section experience.
                .sheet(item: $whyPassage) { wp in
                    NavigationStack {
                        AskBereanWhyView(passage: wp.passage)
                    }
                }
        )
    }

    /// Single routing decision for every emitted action. Preserves the host's
    /// onAction callback, then presents the appropriate result surface for AI actions.
    /// Quick / relationship / safety actions are left to the host (and the menu's
    /// own internal handling) — only `.smart` actions open a Berean result surface.
    private func route(_ action: IntelligenceAction) {
        onAction(action)
        showMenu = false

        guard action.category == .smart, let ctx = activeContext else { return }

        // The five-section "why" experience is verse-specific.
        if action.id == "verse_ask_why", AMENFeatureFlags.shared.askBereanWhyEnabled {
            let passage = ctx.payloadReference ?? ctx.payloadText ?? ""
            whyPassage = WhyPassage(passage: passage)
            return
        }

        // All other AI actions → streaming result surface.
        depthCoordinator = LongPressDepthDialCoordinator(context: ctx)
        presentedSmartAction = action
    }

    private func presentIntelligenceMenu() {
        let context = LongPressObjectContextBuilder.build(
            objectType: objectType,
            objectId: objectId,
            surface: surface,
            payload: payload
        )
        activeContext = context
        showMenu = true
    }
}

extension View {
    func longPressIntelligence(
        objectType: LongPressObjectType,
        objectId: String,
        surface: LongPressSourceSurface,
        payload: LongPressPayload,
        onAction: @escaping (IntelligenceAction) -> Void
    ) -> some View {
        modifier(LongPressableModifier(
            objectType: objectType,
            objectId: objectId,
            surface: surface,
            payload: payload,
            onAction: onAction
        ))
    }
}

/// Identifiable wrapper so a passage string can drive `.sheet(item:)`.
private struct WhyPassage: Identifiable {
    let id = UUID()
    let passage: String
}
