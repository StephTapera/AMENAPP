//
//  SabbathFocusModeModifier.swift
//  AMENAPP
//
//  A ViewModifier that activates Sabbath Focus Mode: all chrome is hidden,
//  the reader fills the screen, and a faint progress dot at bottom center
//  provides the only affordance for exiting the mode.
//
//  Usage:
//      myView.sabbathFocusMode(isActive)
//

import SwiftUI

// MARK: - Modifier

struct SabbathFocusModeModifier: ViewModifier {

    let isActive: Bool

    @State private var showExitConfirmation: Bool = false

    func body(content: Content) -> some View {
        content
            .toolbar(isActive ? .hidden : .automatic, for: .tabBar)
            .toolbar(isActive ? .hidden : .automatic, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if isActive {
                    exitAffordance
                }
            }
    }

    // MARK: - Exit Affordance

    /// A faint progress dot that, when tapped, presents a menu to leave
    /// Sabbath Focus Mode. The dot is intentionally unobtrusive so it does
    /// not distract from reading; `.secondary.opacity(0.3)` matches spec.
    private var exitAffordance: some View {
        Circle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
            .padding(.bottom, 24)
            .contentShape(Rectangle().size(CGSize(width: 44, height: 44)))
            .frame(width: 44, height: 44)
            .onTapGesture {
                showExitConfirmation = true
            }
            .accessibilityLabel("Exit Sabbath Focus Mode")
            .accessibilityIdentifier("sabbathMode.exitButton")
            .confirmationDialog(
                "Exit Sabbath Focus Mode?",
                isPresented: $showExitConfirmation,
                titleVisibility: .visible
            ) {
                Button("Exit Focus Mode", role: .destructive) {
                    // The caller drives `isActive`; notify via the environment.
                    // We post a notification that the parent reader view observes
                    // and uses to clear its sabbathFocusModeActive state variable.
                    NotificationCenter.default.post(
                        name: .selahSabbathFocusModeExitRequested,
                        object: nil
                    )
                }
                Button("Stay in Focus Mode", role: .cancel) {
                    showExitConfirmation = false
                }
            } message: {
                Text("You will return to the normal reading view.")
            }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the user taps "Exit Focus Mode" inside SabbathFocusModeModifier.
    /// The parent view should observe this and set `sabbathFocusModeActive = false`.
    static let selahSabbathFocusModeExitRequested = Notification.Name(
        "com.amenapp.selah.sabbathFocusMode.exitRequested"
    )
}

// MARK: - View Extension

extension View {
    /// Activates Sabbath Focus Mode when `isActive` is true:
    /// hides the tab bar and nav bar, and shows a faint exit dot at the bottom.
    func sabbathFocusMode(_ isActive: Bool) -> some View {
        modifier(SabbathFocusModeModifier(isActive: isActive))
    }
}
