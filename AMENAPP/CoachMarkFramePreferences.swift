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

/// Frame reporter for PostCard - reports frame only once on appear.
/// Uses a deferred preference update to avoid "multiple updates per frame" SwiftUI warning
/// that occurs when multiple list cells report their frames in the same render pass.
private struct PostCardFrameReporter: ViewModifier {
    @State private var reportedFrame: EquatableCGRect? = nil

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: PostCardFramePreferenceKey.self,
                        value: reportedFrame
                    )
                    .onAppear {
                        guard reportedFrame == nil else { return }
                        // Defer to next run-loop tick so all cells in the same
                        // render pass don't all fire the preference simultaneously.
                        let frame = geometry.frame(in: .global)
                        DispatchQueue.main.async {
                            reportedFrame = EquatableCGRect(frame)
                        }
                    }
            }
        )
    }
}

/// Frame reporter for Berean button - reports frame only once on appear.
/// Uses a deferred preference update to avoid "multiple updates per frame" SwiftUI warning
/// that occurs when multiple list cells report their frames in the same render pass.
private struct BereanButtonFrameReporter: ViewModifier {
    @State private var reportedFrame: EquatableCGRect? = nil
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: BereanButtonFramePreferenceKey.self,
                            value: reportedFrame
                        )
                        .onAppear {
                            guard reportedFrame == nil else { return }
                            // Defer to next run-loop tick so all cells in the same
                            // render pass don't all fire the preference simultaneously.
                            let frame = geometry.frame(in: .global)
                            DispatchQueue.main.async {
                                reportedFrame = EquatableCGRect(frame)
                            }
                        }
                }
            )
    }
}
