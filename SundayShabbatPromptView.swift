//
//  SundayShabbatPromptView.swift
//  AMENAPP
//
//  Sunday first-open prompt asking users if they want to enable Shabbat Mode
//

import SwiftUI

struct SundayShabbatPromptView: View {
    @ObservedObject private var focusManager = SundayChurchFocusManager.shared
    @State private var glowPulse = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Glassmorphic icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.2),
                                Color.purple.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(glowPulse ? 1.1 : 1.0)
                
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            }
            
            // Title
            Text("Enable Shabbat Mode?")
                .font(.custom("OpenSans-Bold", size: 28))
                .multilineTextAlignment(.center)
            
            // Description
            VStack(spacing: 12) {
                Text("It's Sunday — dedicate time for worship and spiritual growth")
                    .font(.custom("OpenSans-Regular", size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Shabbat Mode limits social features from 6am–4pm")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                // Enable button
                Button {
                    focusManager.dismissSundayPrompt(enableMode: true)
                } label: {
                    Text("Enable for Today")
                        .font(.custom("OpenSans-SemiBold", size: 17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                
                // Not today button
                Button {
                    focusManager.dismissSundayPrompt(enableMode: false)
                } label: {
                    Text("Not Today")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .padding(32)
    }
}

#Preview {
    SundayShabbatPromptView()
}
