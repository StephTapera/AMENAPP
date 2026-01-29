import SwiftUI
import PhotosUI
import Foundation

// MARK: - PhotoPickerView
// Note: PhotoPickerView is now defined in MessagingComponents.swift to avoid duplication

// MARK: - ModernChatInputBar
// Note: ModernChatInputBar is now defined in MessagingComponents.swift to avoid duplication

// MARK: - ModernMessageBubble
// Note: ModernMessageBubble is now defined in MessagingComponents.swift to avoid duplication

// MARK: - ModernTypingIndicator

struct ModernTypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .scaleEffect(animate ? 0.6 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(i) * 0.2),
                        value: animate
                    )
            }
        }
        .padding(10)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.15))
        )
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Supporting Model

// AppMessage is defined in Message.swift

