import SwiftUI

/// Wraps a thumbnail and provides a tap-to-expand detail sheet with a zoom
/// transition on iOS 18+ and a graceful scale+fade on iOS 17.
///
/// Usage:
/// ```swift
/// ExpandableCard(id: item.id) {
///     ThumbnailView(item: item)
/// } detail: {
///     DetailView(item: item)
/// }
/// ```
struct ExpandableCard<Thumbnail: View, Detail: View>: View {
    let id: AnyHashable
    @ViewBuilder var thumbnail: () -> Thumbnail
    @ViewBuilder var detail: () -> Detail

    @State private var isExpanded = false
    @Namespace private var ns

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                ios18Thumbnail
            } else {
                ios17Thumbnail
            }
        }
        .fullScreenCover(isPresented: $isExpanded) {
            NavigationStack {
                detail()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isExpanded = false }
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
    }

    @available(iOS 18.0, *)
    private var ios18Thumbnail: some View {
        Button { isExpanded = true } label: {
            thumbnail()
                .matchedTransitionSource(id: id, in: ns)
        }
        .buttonStyle(.plain)
    }

    private var ios17Thumbnail: some View {
        Button { withAnimation(.amenSpring) { isExpanded = true } } label: {
            thumbnail()
        }
        .buttonStyle(.plain)
    }
}
