import SwiftUI

struct AmenObjectHubDiscussionPrompts: View {
    let prompts: [String]
    let onSelectPrompt: (String) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityContrast) private var accessibilityContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var safePrompts: [String] {
        let source = prompts.isEmpty ? Self.defaults : prompts
        return Array(source.filter { !$0.isEmpty }.prefix(4))
    }

    private var glass: AmenObjectHubLiquidGlassStyle {
        AmenObjectHubLiquidGlassStyle(reduceTransparency: reduceTransparency, increasedContrast: accessibilityContrast == .increased)
    }

    static let defaults = [
        "What point stood out to you?",
        "What should people read, watch, or listen to next?",
        "What scene or moment stayed with you?",
        "What mood or memory does this bring up?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Safe Discussion Prompts")
                .font(.headline)
                .foregroundStyle(glass.primaryText)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(safePrompts, id: \.self) { prompt in
                    Button {
                        onSelectPrompt(prompt)
                    } label: {
                        Text(prompt)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(glass.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(glass.materialSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(glass.glassBorder, lineWidth: 1))
                    }
                    .buttonStyle(AmenHubGlassButtonStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel("Start discussion: \(prompt)")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
