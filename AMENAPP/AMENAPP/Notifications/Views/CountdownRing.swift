// CountdownRing.swift
// AMENAPP — Notifications/Views
//
// 18×18 circular progress ring that drains anti-clockwise as the undo window
// counts down. Used as the trailing decoration on the Undo button in AmenToast.

import SwiftUI

// MARK: - CountdownRing

struct CountdownRing: View {

    /// Total duration of the countdown (e.g. 4.2 or 6.0 seconds).
    let total: TimeInterval

    /// Remaining time — drives the ring progress. Updated by the caller.
    let remaining: TimeInterval

    private let size: CGFloat    = 18
    private let lineWidth: CGFloat = 2

    /// Progress fraction 0 → 1 where 1 = full ring (just started), 0 = empty (expired).
    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(remaining / total, 1)))
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(NotifGlassTokens.goldPrimary.opacity(0.20), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Active arc — anti-clockwise drain means we trim from 0 → (1 - progress)
            // SwiftUI's trim draws clockwise from startAngle, so to get an anti-clockwise
            // drain we track from 0 to `progress` but rotate so the gap is at the top.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    NotifGlassTokens.goldPrimary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // start at 12 o'clock
                .scaleEffect(x: -1)            // mirror → anti-clockwise drain
                .frame(width: size, height: size)
                .animation(.linear(duration: 0.25), value: progress)
        }
        .accessibilityLabel("Undo countdown")
        .accessibilityValue("\(Int(remaining)) seconds remaining")
    }
}

// MARK: - Preview

#Preview("CountdownRing — all states") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()

        HStack(spacing: 24) {
            ForEach([1.0, 0.75, 0.50, 0.25, 0.05], id: \.self) { fraction in
                VStack(spacing: 8) {
                    CountdownRing(
                        total: 4.2,
                        remaining: 4.2 * fraction
                    )
                    Text("\(Int(fraction * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding()
    }
}

#Preview("CountdownRing — live animation") {
    LiveCountdownRingPreview()
}

private struct LiveCountdownRingPreview: View {
    @State private var remaining: TimeInterval = 4.2
    let total: TimeInterval = 4.2
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            CountdownRing(total: total, remaining: remaining)
                .onReceive(timer) { _ in
                    remaining = max(0, remaining - 0.1)
                    if remaining == 0 { remaining = total }
                }
        }
    }
}
