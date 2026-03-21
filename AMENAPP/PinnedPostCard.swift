//
//  PinnedPostCard.swift
//  AMENAPP
//
//  Component for displaying pinned posts with special styling and animations.
//  Shows pin indicator, expiry countdown, and enhanced visual treatment.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct PinnedPostCard: View {
    let post: Post
    let onUnpin: () -> Void
    
    @State private var showUnpinConfirmation = false
    @State private var isPinAnimating = false
    @State private var timeRemaining: String = ""
    
    var body: some View {
        pinnedCardContent
            .onAppear {
                startPinAnimation()
                updateTimeRemaining()
            }
            .confirmationDialog("Unpin Post", isPresented: $showUnpinConfirmation) {
                Button("Unpin Post", role: .destructive) {
                    onUnpin()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove this post from your pinned section?")
            }
    }
    
    private var pinnedCardContent: some View {
        VStack(spacing: 0) {
            // Pin header
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .rotationEffect(.degrees(isPinAnimating ? 15 : 0))
                
                Text("Pinned Post")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.purple.opacity(0.8))
                    .tracking(0.5)
                
                Spacer()
                
                if let expiresAt = post.pinnedExpiresAt {
                    if expiresAt > Date() {
                        Text(timeRemaining)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.05))
                            )
                    }
                }
                
                Button {
                    showUnpinConfirmation = true
                } label: {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.purple.opacity(0.08))
            
            // Accent line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.6),
                            Color.purple.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
            
            // Post content placeholder - integrate PostCard here based on your PostCard implementation
            VStack(alignment: .leading, spacing: 8) {
                Text(post.authorName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(post.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(4)
                
                Text(post.timeAgo)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.purple.opacity(0.15), lineWidth: 1)
            )
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: Color.purple.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private func startPinAnimation() {
        withAnimation(
            Animation
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
        ) {
            isPinAnimating = true
        }
    }
    
    private func updateTimeRemaining() {
        guard let expiresAt = post.pinnedExpiresAt else { return }
        
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            let remaining = expiresAt.timeIntervalSince(Date())
            if remaining <= 0 {
                timeRemaining = "Expired"
            } else {
                let hours = Int(remaining) / 3600
                let days = hours / 24
                
                if days > 0 {
                    timeRemaining = "\(days)d left"
                } else if hours > 0 {
                    timeRemaining = "\(hours)h left"
                } else {
                    timeRemaining = "< 1h left"
                }
            }
        }
        
        // Initial calculation
        let remaining = expiresAt.timeIntervalSince(Date())
        if remaining <= 0 {
            timeRemaining = "Expired"
        } else {
            let hours = Int(remaining) / 3600
            let days = hours / 24
            
            if days > 0 {
                timeRemaining = "\(days)d left"
            } else if hours > 0 {
                timeRemaining = "\(hours)h left"
            } else {
                timeRemaining = "< 1h left"
            }
        }
    }
}

// MARK: - Pin Post Button (for UserProfileView)

struct PinPostButton: View {
    let post: Post
    let onPin: () -> Void
    
    var body: some View {
        Button {
            onPin()
        } label: {
            Label("Pin to Profile", systemImage: "pin.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Pin Duration Picker

struct PinDurationPicker: View {
    @Binding var selectedDuration: PinDuration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin Duration")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            
            ForEach(PinDuration.allCases, id: \.self) { duration in
                DurationOptionButton(
                    duration: duration,
                    isSelected: selectedDuration == duration,
                    action: { selectedDuration = duration }
                )
            }
        }
        .padding(16)
    }
}

// MARK: - Helper Views

private struct DurationOptionButton: View {
    let duration: PinDuration
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(duration.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Text(durationDescription(for: duration))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.purple)
                } else {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
            }
            .padding(12)
            .background(backgroundForSelection)
            .overlay(overlayForSelection)
        }
    }
    
    private var backgroundForSelection: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.purple.opacity(0.15) : Color.white.opacity(0.05))
    }
    
    private var overlayForSelection: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? Color.purple.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
    }
    
    private func durationDescription(for duration: PinDuration) -> String {
        switch duration {
        case .h24: return "Pin will expire in 24 hours"
        case .h48: return "Pin will expire in 48 hours"
        case .week: return "Pin will expire in 7 days"
        case .sunday: return "Pin expires on Sunday"
        case .indefinite: return "Pin won't expire automatically"
        }
    }
}
