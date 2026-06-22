import SwiftUI

struct CreatorSegmentedControl<T: Hashable & CaseIterable & RawRepresentable>: View where T.RawValue == String {
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(T.allCases), id: \.self) { item in
                Button(item.rawValue) {
                    selection = item
                }
                .buttonStyle(.amenGlass(role: selection == item ? .primary : .neutral, size: .compact, shape: .capsule))
            }
        }
    }
}
