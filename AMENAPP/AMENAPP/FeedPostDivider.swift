//
//  FeedPostDivider.swift
//  AMENAPP
//
//  Threads-style subtle hairline divider between posts in feed surfaces.
//  Content-column aligned, matte and quiet — not glassy.
//

import SwiftUI

struct FeedPostDivider: View {
    var leadingInset: CGFloat = 16
    var trailingInset: CGFloat = 16
    var opacity: Double = 0.12
    var verticalPadding: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(opacity))
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.vertical, verticalPadding)
    }
}
