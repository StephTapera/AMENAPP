import SwiftUI

// MARK: - ContextualExperienceModuleRail

/// Horizontal scrolling rail of enabled module pills for ExperienceDetailView.
struct ContextualExperienceModuleRail: View {

    let modules: [ExperienceModuleType]
    @Binding var selectedModule: ExperienceModuleType?

    @Namespace private var railNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(modules, id: \.self) { module in
                    modulePill(module)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Experience modules")
    }

    // MARK: - Module pill

    @ViewBuilder
    private func modulePill(_ module: ExperienceModuleType) -> some View {
        let isSelected = selectedModule == module

        Button {
            HapticManager.impact(style: .light)
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.32, dampingFraction: 0.78)
            ) {
                selectedModule = module
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: module.icon)
                    .imageScale(.small)
                Text(module.displayName)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(
                isSelected
                    ? AmenTheme.Colors.textPrimary
                    : AmenTheme.Colors.textSecondary
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(pillBackground(isSelected: isSelected, module: module))
            .overlay(pillStroke(isSelected: isSelected, module: module))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(module.displayName)
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to view \(module.displayName)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Pill backgrounds

    @ViewBuilder
    private func pillBackground(isSelected: Bool, module: ExperienceModuleType) -> some View {
        if isSelected {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(Color.white.opacity(0.55))
            }
            .matchedGeometryEffect(id: "activePill", in: railNamespace)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.2))
        }
    }

    private func pillStroke(isSelected: Bool, module: ExperienceModuleType) -> some View {
        Capsule()
            .strokeBorder(
                isSelected
                    ? Color.white.opacity(0.5)
                    : Color.white.opacity(0.2),
                lineWidth: 0.5
            )
    }
}
