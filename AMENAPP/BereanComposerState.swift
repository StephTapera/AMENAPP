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
        case attachFile
        case camera
        case voiceNote
        case verseLookup
        case summarize
        case searchScripture
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
    private var lastScrollOffset: CGFloat = 0
    
    func updateScroll(_ offset: CGFloat) {
        let delta = offset - lastScrollOffset
        isScrollingDown = delta < -20
        lastScrollOffset = offset
        
        // Auto-compact when scrolling down
        if isScrollingDown && state != .expandedActions && state != .typing {
            withAnimation(.easeOut(duration: 0.2)) {
                state = .scrollingCompact
            }
        } else if offset > -30 && state == .scrollingCompact {
            withAnimation(.easeOut(duration: 0.2)) {
                state = .idle
            }
        }
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
