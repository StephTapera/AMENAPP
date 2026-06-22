import SwiftUI

struct ChurchNotesGrowthCard: View {
    @Binding var actionStep: String
    @Binding var prayer: String
    @Binding var revisitMidweek: Bool
    @Binding var isExpanded: Bool
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(ChurchNotesAnimationTokens.sectionExpand) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .amenLiquidGlassCapsuleSurface(isSelected: false)

                    Text("Personal Growth")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                        .frame(width: 42, height: 42)
                        .amenLiquidGlassCapsuleSurface(isSelected: false)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse personal growth" : "Expand personal growth")

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    growthField("Action step this week", text: $actionStep)
                        .onChange(of: actionStep) { _, _ in onChanged() }
                    growthField("Prayer from sermon", text: $prayer)
                        .onChange(of: prayer) { _, _ in onChanged() }
                    Toggle("Revisit this note midweek", isOn: $revisitMidweek)
                        .font(.systemScaled(15, weight: .semibold))
                        .tint(ChurchNotesDesignTokens.Colors.personalTint)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .amenLiquidGlassCapsuleSurface(isSelected: false)
                        .onChange(of: revisitMidweek) { _, _ in onChanged() }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .churchNotesGlassCard()
    }

    private func growthField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(.systemScaled(15))
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .amenLiquidGlassCapsuleSurface(isSelected: false)
    }
}
