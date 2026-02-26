//
//  SundayChurchFocusGateView.swift
//  AMENAPP
//
//  Shabbat Mode - Gating screen shown when restricted features accessed during Sunday 6am-4pm
//

import SwiftUI

struct SundayChurchFocusGateView: View {
    @StateObject private var focusManager = SundayChurchFocusManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var candleFlicker = false
    @Binding var selectedTab: Int  // To navigate to actual tabs
    
    var body: some View {
        VStack(spacing: 24) {
            // Subtle toggle button at top
            HStack {
                Spacer()
                LiquidGlassToggleButton {
                    focusManager.setOptOut(true)
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Spacer()
            
            // Glassmorphic Bible Icon
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.primary.opacity(0.15),
                                Color.primary.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                
                // Glassmorphic container
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                
                // Bible icon
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.9),
                                Color.primary.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(candleFlicker ? 1.03 : 1.0)
                
                // Subtle shimmer overlay
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .frame(width: 100, height: 100)
                    .opacity(candleFlicker ? 0.4 : 0.6)
            }
            .onAppear {
                // Gentle pulse animation
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    candleFlicker = true
                }
            }
            
            // Title
            Text("Shabbat Mode")
                .font(.custom("OpenSans-Bold", size: 28))
                .multilineTextAlignment(.center)
            
            // Description
            VStack(spacing: 12) {
                Text("Focus on worship and spiritual growth")
                    .font(.custom("OpenSans-Regular", size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Active: \(focusManager.windowDescription)")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            
            Spacer()
            
            // Available features
            VStack(alignment: .leading, spacing: 16) {
                Text("Available Features")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.secondary)
                
                FeatureButton(
                    icon: "note.text",
                    title: "Church Notes",
                    subtitle: "Take notes during service"
                ) {
                    // Navigate to Church Notes tab (index 3)
                    selectedTab = 3
                    dismiss()
                }
                
                FeatureButton(
                    icon: "building.columns",
                    title: "Find a Church",
                    subtitle: "Discover churches near you"
                ) {
                    // Navigate to Find Church tab (index 4)
                    selectedTab = 4
                    dismiss()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Settings link
            Button {
                NotificationCenter.default.post(name: .navigateToAccountSettings, object: nil)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Manage in Settings")
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.blue)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(32)
    }
}

struct FeatureButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liquid Glass Toggle Button

struct LiquidGlassToggleButton: View {
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                Text("Exit")
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    // Liquid glass material
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle gradient border
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    
                    // Inner shimmer
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToChurchNotes = Notification.Name("navigateToChurchNotes")
    static let navigateToFindChurch = Notification.Name("navigateToFindChurch")
    static let navigateToSettings = Notification.Name("navigateToSettings")
    static let navigateToAccountSettings = Notification.Name("navigateToAccountSettings")
    static let showShabbatModeGate = Notification.Name("showShabbatModeGate")
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab = 0
        
        var body: some View {
            SundayChurchFocusGateView(selectedTab: $selectedTab)
        }
    }
    
    return PreviewWrapper()
}
