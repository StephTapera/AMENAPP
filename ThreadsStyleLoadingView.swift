//
//  ThreadsStyleLoadingView.swift
//  AMENAPP
//
//  Threads-style 3-dot loading indicator
//

import SwiftUI

struct ThreadsStyleLoadingView: View {
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.primary.opacity(0.8))
                        .frame(width: 10, height: 10)
                        .scaleEffect(dotScale(for: index))
                        .opacity(dotOpacity(for: index))
                }
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                animationPhase = 3
            }
        }
    }
    
    private func dotScale(for index: Int) -> CGFloat {
        let phase = animationPhase - CGFloat(index) * 0.33
        let normalized = (sin(phase * .pi) + 1) / 2
        return 0.7 + (normalized * 0.3)
    }
    
    private func dotOpacity(for index: Int) -> Double {
        let phase = animationPhase - CGFloat(index) * 0.33
        let normalized = (sin(phase * .pi) + 1) / 2
        return 0.3 + (normalized * 0.7)
    }
}

#Preview {
    ThreadsStyleLoadingView()
}
