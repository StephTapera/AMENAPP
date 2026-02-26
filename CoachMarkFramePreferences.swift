//
//  CoachMarkFramePreferences.swift
//  AMENAPP
//
//  Preference keys for capturing UI element frames for coach marks
//

import SwiftUI

// MARK: - Preference Keys

/// Equatable wrapper for CGRect to enable efficient preference updates
struct EquatableCGRect: Equatable {
    let rect: CGRect
    
    init(_ rect: CGRect) {
        self.rect = rect
    }
    
    static func == (lhs: EquatableCGRect, rhs: EquatableCGRect) -> Bool {
        // Only consider frames different if they change by more than 1pt
        // This prevents updates from floating-point precision differences
        return abs(lhs.rect.origin.x - rhs.rect.origin.x) <= 1 &&
               abs(lhs.rect.origin.y - rhs.rect.origin.y) <= 1 &&
               abs(lhs.rect.size.width - rhs.rect.size.width) <= 1 &&
               abs(lhs.rect.size.height - rhs.rect.size.height) <= 1
    }
}

struct PostCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: EquatableCGRect? = nil
    
    static func reduce(value: inout EquatableCGRect?, nextValue: () -> EquatableCGRect?) {
        // Take the first non-nil value (only need first post card)
        value = value ?? nextValue()
    }
}

struct BereanButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: EquatableCGRect? = nil
    
    static func reduce(value: inout EquatableCGRect?, nextValue: () -> EquatableCGRect?) {
        value = value ?? nextValue()
    }
}

// MARK: - View Extensions

extension View {
    /// Reports this view's frame for post card coach mark
    /// PERFORMANCE: Uses debouncing to prevent multiple updates per frame
    func reportPostCardFrame() -> some View {
        self.modifier(PostCardFrameReporter())
    }
    
    /// Reports this view's frame for Berean button coach mark
    func reportBereanButtonFrame() -> some View {
        self.modifier(BereanButtonFrameReporter())
    }
}

// MARK: - Frame Reporters (Debounced)

/// Frame reporter for PostCard - reports frame only once on appear
private struct PostCardFrameReporter: ViewModifier {
    @State private var hasReported = false
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: PostCardFramePreferenceKey.self,
                        value: hasReported ? nil : EquatableCGRect(geometry.frame(in: .global))
                    )
                    .onAppear {
                        // Mark as reported to prevent further updates
                        hasReported = true
                    }
            }
        )
    }
}

/// Frame reporter for Berean button - reports frame only once on appear
private struct BereanButtonFrameReporter: ViewModifier {
    @State private var hasReported = false
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: BereanButtonFramePreferenceKey.self,
                        value: hasReported ? nil : EquatableCGRect(geometry.frame(in: .global))
                    )
                    .onAppear {
                        hasReported = true
                    }
            }
        )
    }
}
