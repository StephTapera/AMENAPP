//
//  SpiritualBlock_View.swift
//  AMENAPP
//
//  Shown when user hasn't spent time with God
//

import SwiftUI

struct SpiritualBlock_View: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Animated icon
                ZStack {
                    // Pulsing circles
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 120 + CGFloat(index * 40), height: 120 + CGFloat(index * 40))
                            .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                            .opacity(pulseAnimation ? 0 : 0.6)
                            .animation(
                                .easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.4),
                                value: pulseAnimation
                            )
                    }
                    
                    // Central icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "hands.sparkles")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .symbolEffect(.pulse, options: .repeating)
                    }
                }
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0)
                
                // Message
                VStack(spacing: 16) {
                    Text("Take Time with God First")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Before diving into the app, spend quality time in prayer, worship, or reading the Word. God desires your presence above all else.")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                    
                    // Bible verse
                    VStack(spacing: 8) {
                        Text("\"But seek first the kingdom of God and his righteousness, and all these things will be added to you.\"")
                            .font(.custom("OpenSans-Italic", size: 15))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Text("Matthew 6:33")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
                .opacity(isAnimating ? 1.0 : 0)
                
                Spacer()
                
                // Encouragement text
                VStack(spacing: 12) {
                    Text("Come back after you've spent time with Him")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                    
                    // Suggestions
                    VStack(alignment: .leading, spacing: 8) {
                        SuggestionRow(icon: "book.fill", text: "Read a chapter from the Bible")
                        SuggestionRow(icon: "hands.sparkles", text: "Pray for 10 minutes")
                        SuggestionRow(icon: "music.note", text: "Listen to worship music")
                        SuggestionRow(icon: "heart.fill", text: "Journal what God is speaking")
                    }
                    .padding(.horizontal, 40)
                }
                .padding(.bottom, 60)
                .opacity(isAnimating ? 1.0 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isAnimating = true
            }
            pulseAnimation = true
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.8))
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    SpiritualBlock_View()
}
