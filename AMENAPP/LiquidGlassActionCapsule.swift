//
//  LiquidGlassActionCapsule.swift
//  AMENAPP
//
//  Created by Gemini CLI on 2026-06-09.
//  Copyright © 2026 AMEN. All rights reserved.
//
//  The LiquidGlassActionCapsule renders contextual actions surfaced by the AI Engine.
//  It conforms to the Liquid Glass design system and animates state transitions.

import SwiftUI

struct LiquidGlassActionCapsule: View {
    let actions: [ActionOption]
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Collapsed state: Primary action only
            if !isExpanded && !actions.isEmpty {
                Button(action: { withAnimation(.spring()) { isExpanded = true } }) {
                    HStack {
                        Image(systemName: actions.first!.systemImage)
                        Text(actions.first!.title)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .amenLiquidGlassCapsuleSurface()
            } else if isExpanded {
                // Expanded state: Surface up to 3 primary actions
                HStack(spacing: 8) {
                    ForEach(actions.prefix(3), id: \.title) { action in
                        Button(action: action.action) {
                            Text(action.title)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .amenLiquidGlassCapsuleSurface()
                    }
                    Button(action: { withAnimation(.spring()) { isExpanded = false } }) {
                        Image(systemName: "chevron.up")
                            .font(.caption)
                            .padding(8)
                    }
                    .amenLiquidGlassCapsuleSurface()
                }
            }
        }
    }
}

struct ActionOption {
    let title: String
    let systemImage: String
    let action: () -> Void
}
