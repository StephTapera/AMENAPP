//
//  AdaptiveLayout.swift
//  AMENAPP
//
//  iPad layout adaptation utilities. Provides size-class-aware modifiers
//  and a content width limiter for readable layouts on large screens.
//

import SwiftUI

// MARK: - Readable Content Width

/// Constrains content to a readable width on iPad (max 600pt)
/// while staying full-width on iPhone. Apply to ScrollView content.
struct ReadableWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Constrains content to a readable width on iPad.
    func readableWidth() -> some View {
        modifier(ReadableWidthModifier())
    }
}

// MARK: - Adaptive Columns

/// Returns appropriate grid columns based on horizontal size class.
struct AdaptiveGrid {
    static func columns(for sizeClass: UserInterfaceSizeClass?, minWidth: CGFloat = 300) -> [GridItem] {
        if sizeClass == .regular {
            // iPad: 2-3 columns
            return [
                GridItem(.adaptive(minimum: minWidth), spacing: 16),
            ]
        } else {
            // iPhone: single column
            return [GridItem(.flexible())]
        }
    }
}

// MARK: - Adaptive Padding

extension View {
    /// Applies larger horizontal padding on iPad for breathing room.
    func adaptivePadding() -> some View {
        modifier(AdaptivePaddingModifier())
    }
}

struct AdaptivePaddingModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) var sizeClass

    func body(content: Content) -> some View {
        content.padding(.horizontal, sizeClass == .regular ? 40 : 16)
    }
}

// MARK: - Adaptive Sheet Sizing

extension View {
    /// On iPad, presents sheets as popovers with a sensible default size.
    func adaptiveSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            content()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Device Check

enum DeviceType {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}
