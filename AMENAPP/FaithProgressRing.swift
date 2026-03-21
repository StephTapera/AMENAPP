// FaithProgressRing.swift
// AMENAPP
import SwiftUI

struct FaithProgressRing: View {
    let progress: Double        // 0.0–1.0
    let size: CGFloat           // ring diameter
    let lineWidth: CGFloat
    let color: Color
    let displayPercent: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color(.systemGray5), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
            // Fill
            Circle()
                .trim(from: 0, to: reduceMotion ? progress : progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            // Label
            Text("\(displayPercent)%")
                .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}
