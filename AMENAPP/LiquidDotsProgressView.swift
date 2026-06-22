// LiquidDotsProgressView.swift
// AMEN App — Custom liquid dots progress indicator for AutoLoginSplashView

import SwiftUI

struct LiquidDotsProgressView: View {
    @State private var scales: [CGFloat] = [1, 1, 1]
    @State private var opacities: [Double] = [0.3, 0.3, 0.3]

    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 10
    private let color: Color

    init(color: Color = Color(red: 0.79, green: 0.66, blue: 0.30)) {
        self.color = color
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(scales[i])
                    .opacity(opacities[i])
                    .blur(radius: scales[i] > 1.1 ? 0.5 : 0)
            }
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0..<3 {
            let delay = Double(i) * 0.22
            withAnimation(
                .easeInOut(duration: 0.55)
                .repeatForever(autoreverses: true)
                .delay(delay)
            ) {
                scales[i] = 1.55
                opacities[i] = 1.0
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        LiquidDotsProgressView()
    }
}
