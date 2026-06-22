//
//  ScrollOffsetPreference.swift
//  AMENAPP
//
//  Shared scroll-offset preference helpers for scroll-reactive surfaces.
//

import SwiftUI

struct ScrollOffsetPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BereanScrollOffsetReader: View {
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollOffsetPreference.self,
                    value: geo.frame(in: .named(coordinateSpaceName)).minY
                )
        }
    }
}
