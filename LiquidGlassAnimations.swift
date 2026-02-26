//
//  LiquidGlassAnimations.swift
//  AMENAPP
//
//  Premium Liquid Glass animations for high-end UX
//  Fast, smooth, no lag - optimized for 60fps performance
//

import SwiftUI

// MARK: - 1. Metaball Merge/Separate

struct MetaballMergeEffect: ViewModifier {
    let isMerged: Bool
    let mergeScale: CGFloat
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isMerged ? mergeScale : 1.0)
            .blur(radius: isMerged ? 8 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0), value: isMerged)
    }
}

extension View {
    func metaballMerge(merged: Bool, scale: CGFloat = 0.95) -> some View {
        modifier(MetaballMergeEffect(isMerged: merged, mergeScale: scale))
    }
}

// MARK: - 2. Elastic Press Compression

struct ElasticPressEffect: ViewModifier {
    @Binding var isPressed: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .brightness(isPressed ? 0.05 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

extension View {
    /// Premium elastic press effect - use on buttons and interactive cards
    func elasticPress(isPressed: Binding<Bool>) -> some View {
        modifier(ElasticPressEffect(isPressed: isPressed))
    }
}

// MARK: - 3. Sticky Edge Docking

struct StickyEdgeDockEffect: ViewModifier {
    @Binding var offset: CGFloat
    let edge: Edge
    let snapThreshold: CGFloat
    let stretchAmount: CGFloat
    
    func body(content: Content) -> some View {
        content
            .offset(y: calculateOffset())
            .animation(.interpolatingSpring(stiffness: 300, damping: 25), value: offset)
    }
    
    private func calculateOffset() -> CGFloat {
        let distanceFromEdge = abs(offset)
        
        // Magnetic snap when close to edge
        if distanceFromEdge < snapThreshold {
            return 0
        }
        
        // Stretch effect when approaching edge
        if distanceFromEdge < snapThreshold * 2 {
            let stretchFactor = 1 - (distanceFromEdge - snapThreshold) / snapThreshold
            return offset * (1 - stretchFactor * stretchAmount)
        }
        
        return offset
    }
}

extension View {
    func stickyEdgeDock(offset: Binding<CGFloat>, edge: Edge = .top, snapThreshold: CGFloat = 30, stretchAmount: CGFloat = 0.3) -> some View {
        modifier(StickyEdgeDockEffect(offset: offset, edge: edge, snapThreshold: snapThreshold, stretchAmount: stretchAmount))
    }
}

// MARK: - 4. Combined Premium Button Style

struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }
}

// MARK: - 4b. Touch-Down Instant Feedback Button Style (P0 FIX)

/// Premium button style with INSTANT touch-down visual feedback
/// Uses DragGesture to detect touch down immediately (not just tap)
struct InstantFeedbackButtonStyle: ButtonStyle {
    @State private var isTouching = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isTouching ? 0.92 : 1.0)
            .brightness(isTouching ? 0.08 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isTouching)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isTouching {
                            isTouching = true
                        }
                    }
                    .onEnded { _ in
                        isTouching = false
                    }
            )
    }
}

extension ButtonStyle where Self == InstantFeedbackButtonStyle {
    static var instantFeedback: InstantFeedbackButtonStyle { InstantFeedbackButtonStyle() }
}

// MARK: - 5. Floating Action Bubble

struct FloatingActionBubble: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Glass background with blur
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                
                // Color overlay
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 56, height: 56)
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(color)
            }
            .shadow(color: color.opacity(0.3), radius: 12, x: 0, y: 4)
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 0.94
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        scale = 1.0
                    }
                }
        )
    }
}

// MARK: - 6. Metaball Badge Notification

struct MetaballBadge: View {
    let count: Int
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        if count > 0 {
            ZStack {
                // Outer glow
                Circle()
                    .fill(.red.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .blur(radius: 4)
                
                // Badge
                Circle()
                    .fill(.red)
                    .frame(width: 20, height: 20)
                
                // Count
                Text("\(min(count, 99))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
            .onChange(of: count) { oldValue, newValue in
                // Bounce animation when count changes
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    scale = 1.2
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                    scale = 1.0
                }
            }
        }
    }
}

// MARK: - 7. Smooth Card Press Effect

struct LiquidGlassCardStyle: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(isPressed ? 0.1 : 0.05), radius: isPressed ? 8 : 12, y: isPressed ? 2 : 4)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func liquidGlassCard() -> some View {
        modifier(LiquidGlassCardStyle())
    }
}

// MARK: - 8. Tab Bar Icon Bounce

struct TabBarIconBounce: ViewModifier {
    let isSelected: Bool
    @State private var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isSelected) { oldValue, newValue in
                if newValue {
                    // Bounce when selected
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        scale = 1.2
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15)) {
                        scale = 1.0
                    }
                }
            }
    }
}

extension View {
    func tabBarIconBounce(isSelected: Bool) -> some View {
        modifier(TabBarIconBounce(isSelected: isSelected))
    }
}

// MARK: - Performance Optimized Spring Presets

struct LiquidSpring {
    // Fast, snappy interactions
    static let quick = Animation.spring(response: 0.25, dampingFraction: 0.7)
    
    // Smooth, premium feel
    static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.75)
    
    // Bouncy, playful
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    
    // Sticky, magnetic snap
    static let magnetic = Animation.interpolatingSpring(stiffness: 300, damping: 25)
    
    // Elastic compression
    static let elastic = Animation.spring(response: 0.3, dampingFraction: 0.6)
}

// MARK: - Example Usage Container

struct LiquidGlassExampleView: View {
    @State private var isPressed = false
    @State private var badgeCount = 3
    @State private var offset: CGFloat = 0
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 30) {
            // Example: Elastic Press Button
            Button("Tap Me") {
                print("Tapped!")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .buttonStyle(.liquidGlass)
            
            // Example: Floating Action Bubbles
            HStack(spacing: 20) {
                FloatingActionBubble(icon: "heart.fill", color: .red) {
                    print("Heart tapped")
                }
                
                FloatingActionBubble(icon: "message.fill", color: .blue) {
                    print("Message tapped")
                }
                
                FloatingActionBubble(icon: "paperplane.fill", color: .green) {
                    print("Share tapped")
                }
            }
            
            // Example: Badge with metaball effect
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                MetaballBadge(count: badgeCount)
                    .offset(x: 8, y: -8)
            }
            
            Button("Increment Badge") {
                badgeCount += 1
            }
            .buttonStyle(.liquidGlass)
        }
        .padding()
    }
}
