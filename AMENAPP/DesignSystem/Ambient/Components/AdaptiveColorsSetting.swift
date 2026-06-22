//
//  AdaptiveColorsSetting.swift
//  AMEN — Adaptive Ambient UI System
//
//  The single user-facing control for the Adaptive Ambient system. Renders a
//  Form `Section` with a Picker bound to @AppStorage(AmbientStorageKeys.mode).
//  Default-safe: when the stored mode is `.off`, the whole system renders a
//  byte-identical neutral surface (invariant C2), so this control is the only
//  thing a user needs to opt in or out.
//
//  Self-contained: drop this Section into any Form / List. (Hosting it inside a
//  Form is required for the explanatory `footer` to render.)
//

import SwiftUI

/// Settings control for Adaptive Colors. Place inside a `Form` or `List`.
public struct AdaptiveColorsSetting: View {
    @AppStorage(AmbientStorageKeys.mode)
    private var modeRaw: String = AdaptiveColorsMode.balanced.rawValue

    public init() {}

    public var body: some View {
        Section {
            Picker("Adaptive Colors", selection: $modeRaw) {
                ForEach(AdaptiveColorsMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
        } footer: {
            Text("Lets AMEN gently take on the colors of photos, profiles, and rooms. Off keeps the classic look.")
        }
    }
}
