import SwiftUI

// MARK: - Smart Tools Grid

struct WellnessSmartToolsGrid: View {
    let tools: [WellnessSmartTool]
    let onToolTap: (String) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY'S TOOLS")
                    .font(.custom("OpenSans-SemiBold", size: 10))
                    .tracking(2.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Reordered for now")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tools) { tool in
                    WellnessToolCard(tool: tool) {
                        onToolTap(tool.name)
                    }
                }
            }
        }
    }
}

// MARK: - Tool Card

struct WellnessToolCard: View {
    let tool: WellnessSmartTool
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tool.name)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        Text(tool.memoryLine)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(1.5)
                    }
                    Spacer(minLength: 4)
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(tool.accent.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: tool.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tool.accent)
                    }
                }
                .padding(.bottom, 10)

                Text(tool.suggestion)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(1.5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) { isPressed = false }
                }
        )
        .accessibilityLabel("\(tool.name): \(tool.suggestion)")
        .accessibilityHint(tool.memoryLine)
    }
}
