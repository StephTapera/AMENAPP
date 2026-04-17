//
//  BereanInputBarState.swift
//  AMENAPP
//
//  Display state for the adaptive Berean input bar.
//

import Foundation

enum BereanInputBarDisplayState: Equatable {
    case expanded
    case compact
    case focused
    case typing
    case toolsExpanded
}

struct BereanInputBarState: Equatable {
    var displayState: BereanInputBarDisplayState = .expanded
    var isFocused: Bool = false
    var isTyping: Bool = false
}
