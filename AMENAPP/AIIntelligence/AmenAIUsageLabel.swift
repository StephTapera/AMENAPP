import SwiftUI

struct AmenAIUsageLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.8))
            .accessibilityLabel("AI usage label: \(text)")
    }
}
