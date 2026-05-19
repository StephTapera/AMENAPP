// AmenMessageContextMenuAction.swift
// AMENAPP
//
// Data model for the Liquid Glass context menu.
// Covers all existing LiquidGlassMessageBubble actions plus
// disabled actions that report unavailable state through the menu toast.

import Foundation

enum AmenContextMenuActionKind {
    // Active actions — map 1:1 to existing .contextMenu buttons
    case reply
    case react
    case copy
    case edit
    case delete
    case report
    case block
    case mute
    // Disabled actions that surface a toast when tapped.
    case translate
    case saveToSelah
    case addToChurchNotes
    case summarize
    case remindMe
}

struct AmenContextMenuAction: Identifiable {
    let id = UUID()
    let kind: AmenContextMenuActionKind
    let label: String
    let systemImage: String
    var isEnabled: Bool = true
    var isDestructive: Bool = false
    var handler: (() -> Void)?
}
