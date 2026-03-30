//
//  FullScreenAvatarView.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/26/26.
//

import SwiftUI

/// Full-screen avatar viewer with zoom and pan gestures
struct FullScreenAvatarView: View {
    @Environment(\.dismiss) var dismiss
    
    let name: String
    let initials: String
    let profileImageURL: String?
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            // Avatar Image
            avatarContent
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .gesture(dragGesture)
            
            // Close Button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
            
            // Name Label at Bottom
            VStack {
                Spacer()
                Text(name)
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .padding(.bottom, 40)
            }
        }
        .statusBarHidden()
        .onTapGesture(count: 2) {
            // Double tap to reset zoom
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
                offset = .zero
                lastScale = 1.0
                lastOffset = .zero
            }
        }
    }
    
    @ViewBuilder
    private var avatarContent: some View {
        if let imageURL = profileImageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    avatarPlaceholder
                case .empty:
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                @unknown default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 300, height: 300)
            .overlay(
                Text(initials)
                    .font(.custom("OpenSans-Bold", size: 100))
                    .foregroundStyle(.black)
            )
    }
    
    // MARK: - Gestures
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale *= delta
                
                // Limit zoom scale
                if scale < 1.0 {
                    scale = 1.0
                } else if scale > 4.0 {
                    scale = 4.0
                }
            }
            .onEnded { _ in
                lastScale = 1.0
                
                // Reset if zoomed out too much
                if scale < 1.0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}

#Preview {
    FullScreenAvatarView(
        name: "John Doe",
        initials: "JD",
        profileImageURL: nil
    )
}
