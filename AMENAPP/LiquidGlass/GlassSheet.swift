import SwiftUI

/// Pull-up sheet wrapper with glass background and standardised detents.
/// Prefer this over raw `.sheet()` for all media-interaction surfaces
/// (save-to-collection, verse picker, mood tags, etc.).
///
/// Usage:
///   GlassSheet(isPresented: $showPicker, detent: .medium) {
///       CollectionPickerView()
///   }
enum GlassSheetDetent {
    /// ~40 % of screen height.
    case small
    /// ~55 % of screen height.
    case medium
    /// Full height (large).
    case large
    /// Multiple detents; user can drag between them.
    case adaptive([GlassSheetDetent])

    var presentationDetents: Set<PresentationDetent> {
        switch self {
        case .small:           return [.fraction(0.40)]
        case .medium:          return [.fraction(0.55)]
        case .large:           return [.large]
        case .adaptive(let ds): return Set(ds.flatMap { $0.presentationDetents })
        }
    }
}

struct LiquidGlassSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var detent: GlassSheetDetent = .medium
    var cornerRadius: CGFloat = 28
    @ViewBuilder var sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            sheetContent()
                .presentationDetents(detent.presentationDetents)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(cornerRadius)
                .presentationBackground(.regularMaterial)
        }
    }
}

extension View {
    func glassSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        detent: GlassSheetDetent = .medium,
        cornerRadius: CGFloat = 28,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(LiquidGlassSheetModifier(
            isPresented: isPresented,
            detent: detent,
            cornerRadius: cornerRadius,
            sheetContent: content
        ))
    }
}
