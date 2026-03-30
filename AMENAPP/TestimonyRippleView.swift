import SwiftUI

/// Inline pill showing ripple count on testimony posts. Hidden when count < 1.
struct TestimonyRippleView: View {
    let count: Int

    private let amber    = Color(red: 0.784, green: 0.447, blue: 0.165) // #c8722a
    private let textClr  = Color(red: 0.541, green: 0.353, blue: 0.165) // #8a5a2a
    private let bgColor  = Color(red: 0.957, green: 0.957, blue: 0.949) // #f4f4f2

    var body: some View {
        if count > 0 {
            HStack(spacing: 5) {
                Image(systemName: "dot.radiowaves.right")
                    .font(.system(size: 12))
                    .foregroundStyle(amber)
                Text("This testimony sparked \(count) new \(count == 1 ? "prayer" : "prayers")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(textClr)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(bgColor)
            )
            .animation(.easeInOut(duration: 0.5), value: count)
        }
    }
}
