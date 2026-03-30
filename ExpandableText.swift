//
//  ExpandableText.swift
//  AMENAPP
//
//  Reusable expandable text component with consistent "See more"/"See less"
//  behavior across all content surfaces (PostCard, ProfilePostCard, Comments, etc.)
//

import SwiftUI

struct ExpandableText: View {
    let text: String
    var lineLimit: Int = 4
    var characterThreshold: Int = 120
    var font: Font = .custom("OpenSans-Regular", size: 15)
    var foregroundColor: Color = .primary
    var expandButtonColor: Color = .secondary

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(font)
                .foregroundStyle(foregroundColor)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : lineLimit)
                .background(
                    // Invisible geometry reader to detect truncation
                    Text(text)
                        .font(font)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(GeometryReader { fullSize in
                            Text(text)
                                .font(font)
                                .lineSpacing(4)
                                .lineLimit(lineLimit)
                                .background(GeometryReader { limitedSize in
                                    Color.clear.onAppear {
                                        isTruncated = fullSize.size.height > limitedSize.size.height
                                            || text.count > characterThreshold
                                    }
                                })
                        })
                )

            if isTruncated {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "See less" : "See more")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(expandButtonColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
