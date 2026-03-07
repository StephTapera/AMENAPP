//
//  PostImagesView.swift
//  AMENAPP
//
//  Displays one or more images attached to a post
//

import SwiftUI

struct PostImagesView: View {
    let imageURLs: [String]

    var body: some View {
        if imageURLs.count == 1 {
            singleImage(imageURLs[0])
        } else if imageURLs.count > 1 {
            scrollingImages
        }
    }

    private func singleImage(_ urlString: String) -> some View {
        CachedAsyncImage(url: URL(string: urlString)) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .overlay(ProgressView())
        }
    }

    private var scrollingImages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(imageURLs, id: \.self) { urlString in
                    CachedAsyncImage(url: URL(string: urlString)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                            .frame(width: 200, height: 160)
                            .overlay(ProgressView())
                    }
                }
            }
        }
    }
}
