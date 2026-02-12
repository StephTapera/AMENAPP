//
//  ModerationToastView.swift
//  AMENAPP
//
//  Created by Assistant on 2/11/26.
//
//  Liquid glass toast for moderation feedback
//

import SwiftUI
import Combine

// MARK: - Moderation Toast View

struct ModerationToastView: View {
    let reasons: [String]
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var offset: CGFloat = 50
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            if isVisible {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Content Flagged")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    
                    // Reasons
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(reasons, id: \.self) { reason in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.primary.opacity(0.6))
                                    .frame(width: 4, height: 4)
                                
                                Text(reason)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary.opacity(0.8))
                            }
                        }
                    }
                    
                    // Footer
                    Text("Please review and edit your content")
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.6))
                        .padding(.top, 4)
                }
                .padding(16)
                .background(
                    // Liquid glass effect
                    ZStack {
                        // Frosted glass background
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                        
                        // Subtle border
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.primary.opacity(0.2),
                                        Color.primary.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                        
                        // Subtle inner shadow for depth
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                )
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .offset(y: offset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            // Animate in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
                offset = 0
            }
            
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                dismiss()
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            offset = 50
            isVisible = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Toast Manager

@MainActor
class ModerationToastManager: ObservableObject {
    static let shared = ModerationToastManager()
    
    @Published var isShowing = false
    @Published var reasons: [String] = []
    
    private init() {}
    
    func show(reasons: [String]) {
        self.reasons = reasons
        self.isShowing = true
    }
    
    func dismiss() {
        self.isShowing = false
        self.reasons = []
    }
}

// MARK: - View Extension for Easy Integration

extension View {
    func moderationToast() -> some View {
        ZStack {
            self
            
            if ModerationToastManager.shared.isShowing {
                ModerationToastView(
                    reasons: ModerationToastManager.shared.reasons,
                    onDismiss: {
                        ModerationToastManager.shared.dismiss()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(999)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        Text("Sample Content")
            .font(.headline)
        Spacer()
    }
    .moderationToast()
    .onAppear {
        ModerationToastManager.shared.show(reasons: [
            "Inappropriate language detected",
            "Please keep conversations respectful"
        ])
    }
}
