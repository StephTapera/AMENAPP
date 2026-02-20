//
//  LiquidGlassButtons.swift
//  AMENAPP
//
//  Created by Claude Code on 2/20/26.
//
//  Reusable liquid glass button components for modern UI

import SwiftUI

// MARK: - Glass Action Pill (Multi-Icon)

struct GlassActionPill: View {
    let icons: [String]
    let actions: [() -> Void]
    var isDisabled: Bool = false
    
    @State private var pressedIndex: Int? = nil
    
    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                Button {
                    guard !isDisabled else { return }
                    actions[index]()
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isDisabled ? .black.opacity(0.3) : .black.opacity(0.7))
                        .frame(width: 24, height: 24)
                }
                .scaleEffect(pressedIndex == index ? 0.97 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressedIndex)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            pressedIndex = index
                        }
                        .onEnded { _ in
                            pressedIndex = nil
                        }
                )
                .disabled(isDisabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Glass Circular Button (Primary Action)

struct GlassCircularButton: View {
    let icon: String
    let action: () -> Void
    var isDisabled: Bool = false
    var size: CGFloat = 44
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            guard !isDisabled else { return }
            action()
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(isDisabled ? .black.opacity(0.3) : .black)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(isDisabled ? .ultraThinMaterial : .ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                        )
                        .shadow(color: isDisabled ? .clear : .black.opacity(0.12), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)
                )
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // Glass Action Pill
        GlassActionPill(
            icons: ["paperclip", "face.smiling", "photo"],
            actions: [
                { print("Attach") },
                { print("Emoji") },
                { print("Photo") }
            ]
        )
        
        GlassActionPill(
            icons: ["paperclip", "face.smiling", "photo"],
            actions: [
                { print("Attach") },
                { print("Emoji") },
                { print("Photo") }
            ],
            isDisabled: true
        )
        
        // Glass Circular Button
        HStack(spacing: 20) {
            GlassCircularButton(
                icon: "paperplane.fill",
                action: { print("Send") }
            )
            
            GlassCircularButton(
                icon: "paperplane.fill",
                action: { print("Send") },
                isDisabled: true
            )
        }
    }
    .padding()
    .background(Color(white: 0.95))
}
