//
//  PostShareOptionsSheet.swift
//  AMENAPP
//
//  Share options for posts - choose between sharing to messages or externally
//

import SwiftUI

struct PostShareOptionsSheet: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @State private var showShareToMessages = false
    @State private var showSystemShare = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Share to messages option
                shareOption(
                    icon: "paperplane.fill",
                    title: "Send in Message",
                    subtitle: "Share with your followers",
                    action: {
                        showShareToMessages = true
                    }
                )
                
                Divider()
                    .padding(.leading, 68)
                
                // Share externally option
                shareOption(
                    icon: "square.and.arrow.up",
                    title: "Share Externally",
                    subtitle: "Share via other apps",
                    action: {
                        showSystemShare = true
                    }
                )
                
                Spacer()
            }
            .navigationTitle("Share Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareToMessages) {
            ShareToMessagesSheet(post: post)
        }
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: [shareText])
        }
    }
    
    private func shareOption(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
    
    private var shareText: String {
        """
        \(post.category.displayName) by \(post.authorName)
        
        \(post.content)
        
        Join the conversation on AMEN APP!
        https://amenapp.com/post/\(post.firestoreId)
        """
    }
}

// MARK: - Preview

#Preview {
    PostShareOptionsSheet(post: Post(
        authorId: "test",
        authorName: "John Doe",
        authorUsername: "johndoe",
        authorInitials: "JD",
        content: "This is a test post",
        category: .openTable,
        timestamp: Date(),
        commentPermissions: .everyone
    ))
}
