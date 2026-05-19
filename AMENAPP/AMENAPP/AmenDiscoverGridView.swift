import SwiftUI

struct AmenDiscoverGridView: View {
    let items: [AmenDiscoverItem]
    let onTap: (AmenDiscoverItem) -> Void
    let onAppear: (AmenDiscoverItem) -> Void
    let namespace: Namespace.ID

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                AmenDiscoverTileView(item: item, namespace: namespace)
                    .onTapGesture { onTap(item) }
                    .onAppear { onAppear(item) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.type.rawValue) \(item.title)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 120)
    }
}
