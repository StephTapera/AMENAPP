// AmenMessageContextMenuPresenter.swift
// AMENAPP
//
// @MainActor singleton driving the Liquid Glass context menu overlay.
// Call present(anchorFrame:actions:) from the bubble's long-press handler.
// Call dismiss() from the backdrop tap or after an action fires.

import SwiftUI

@MainActor
final class AmenMessageContextMenuPresenter: ObservableObject {

    static let shared = AmenMessageContextMenuPresenter()
    private init() {}

    @Published var isPresented: Bool = false
    @Published var anchorFrame: CGRect = .zero
    @Published var actions: [AmenContextMenuAction] = []

    func present(anchorFrame: CGRect, actions: [AmenContextMenuAction]) {
        self.anchorFrame = anchorFrame
        self.actions = actions
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            isPresented = true
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) {
            isPresented = false
        }
    }
}
