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
                                onAction(action)
                            },
                            onDismiss: {
                                showMenu = false
                            }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                    }
                }
        )
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
