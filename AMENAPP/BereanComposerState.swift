//
//  BereanComposerState.swift
//  AMENAPP
//
//  Liquid Glass composer state management for Berean AI
//

import Foundation
import SwiftUI

// MARK: - Composer State

enum BereanComposerState: Equatable {
    case idle
    case focused
    case typing
    case expandedActions
    case scrollingCompact
    case streaming
    case voiceReady
    case attachmentSelected
    case scriptureMode
    case searchMode
    
    var isCompact: Bool {
        self == .scrollingCompact
    }
    
    var showSuggestions: Bool {
        self == .idle
    }
    
    var showExpandedActions: Bool {
        self == .expandedActions
    }
    
    var composerOpacity: Double {
        switch self {
        case .idle: return 0.08
        case .focused, .typing: return 0.12
        case .expandedActions: return 0.10
        case .scrollingCompact: return 0.06
        case .streaming: return 0.10
        case .voiceReady: return 0.10
        case .attachmentSelected, .scriptureMode, .searchMode: return 0.12
        }
    }
    
    var inputOpacity: Double {
        switch self {
        case .idle: return 0.15
        case .focused, .typing: return 0.20
        case .scrollingCompact: return 0.12
        default: return 0.18
        }
    }
    
    var shadowOpacity: Double {
        switch self {
        case .focused, .typing: return 0.12
        case .expandedActions: return 0.15
        default: return 0.08
        }
    }
}

// MARK: - Quick Action Model

struct BereanLiquidAction: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let color: Color
    let action: ActionType
    
    enum ActionType: Equatable {
        case bibleVerse
        case prayerRequest
        case churchNotes
        case safePhoto
        case voiceNote
        case sermonClip
        case reminder
        case shareToSpace
    }
}

// MARK: - Suggestion Chip

struct BereanLiquidSuggestionChip: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let icon: String?
}

// MARK: - Status Pill Type

enum BereanStatusPillType: Equatable {
    case searchMode
    case voiceReady
    case fileAttached(String)
    case verseLookup
    case messageSent
    case streaming
    
    var text: String {
        switch self {
        case .searchMode: return "Search mode active"
        case .voiceReady: return "Voice ready"
        case .fileAttached(let name): return "Attached: \(name)"
        case .verseLookup: return "Verse lookup enabled"
        case .messageSent: return "Message sent"
        case .streaming: return "Berean is thinking..."
        }
    }
    
    var icon: String {
        switch self {
        case .searchMode: return "magnifyingglass"
        case .voiceReady: return "mic.fill"
        case .fileAttached: return "paperclip"
        case .verseLookup: return "book.fill"
        case .messageSent: return "checkmark"
        case .streaming: return "ellipsis"
        }
    }
}

// MARK: - Composer View Model

@MainActor
class BereanComposerViewModel: ObservableObject {
    @Published var state: BereanComposerState = .idle
    @Published var statusPill: BereanStatusPillType?
    @Published var attachedFile: String?
    @Published var activeMode: String?

    // Scroll tracking
    @Published var scrollOffset: CGFloat = 0
    @Published var isScrollingDown = false

    /// Normalized collapse progress 0 (fully expanded) → 1 (fully compact).
    /// Driven by scroll position; smoothed with spring interpolation.
    @Published private(set) var collapseProgress: CGFloat = 0

    private var lastScrollOffset: CGFloat = 0

    // Thresholds for multi-breakpoint interpolation
    private let collapseStartOffset: CGFloat = 48
    private let collapseFullOffset: CGFloat = 220
    private let deadZone: CGFloat = 14

    func updateScroll(_ offset: CGFloat) {
        let delta = offset - lastScrollOffset
        isScrollingDown = delta < -20
        lastScrollOffset = offset

        // offset is negative when the user has scrolled upward through history
        let scrolledDistance = max(-offset, 0)
        let targetProgress = collapseTarget(for: scrolledDistance)

        if abs(targetProgress - collapseProgress) > 0.003 {
            withAnimation(.interpolatingSpring(stiffness: 210, damping: 32)) {
                collapseProgress = targetProgress
            }
        }

        // Mirror into discrete state for components that still read .state
        let shouldBeCompact = targetProgress > 0.62
        if shouldBeCompact && state != .expandedActions && state != .typing && state != .streaming {
            if state != .scrollingCompact {
                state = .scrollingCompact
            }
        } else if !shouldBeCompact && state == .scrollingCompact {
            state = .idle
        }
    }

    private func collapseTarget(for scrolledDistance: CGFloat) -> CGFloat {
        let adjusted = max(scrolledDistance - collapseStartOffset - deadZone, 0)
        let range = max(collapseFullOffset - collapseStartOffset, 1)
        let raw = min(adjusted / range, 1)

        switch raw {
        case ..<0.32:
            return smoothStep(raw / 0.32) * 0.18
        case ..<0.72:
            let local = (raw - 0.32) / 0.40
            return 0.18 + smoothStep(local) * 0.54
        default:
            let local = (raw - 0.72) / 0.28
            return 0.72 + smoothStep(local) * 0.28
        }
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
    
    func showStatus(_ type: BereanStatusPillType, duration: TimeInterval = 2.0) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            statusPill = type
        }
        
        if duration > 0 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        statusPill = nil
                    }
                }
            }
        }
    }
    
    func setState(_ newState: BereanComposerState) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            state = newState
        }
    }
}
