//
//  FeedPostDivider.swift
//  AMENAPP
//
//  Threads-style subtle hairline divider between posts in feed surfaces.
//  0.5pt height, very low opacity, content-column aligned.
//

import SwiftUI

struct FeedPostDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
