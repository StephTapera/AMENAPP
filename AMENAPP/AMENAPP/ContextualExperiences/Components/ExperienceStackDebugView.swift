import SwiftUI

// MARK: - ContextualExperienceDebugView (DEBUG only)

#if DEBUG
struct ContextualExperienceDebugView: View {

    let resolved: ResolvedExperience

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(AmenTheme.Colors.statusWarning)
                Text("Resolver Debug")
                    .font(AMENFont.bold(13))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .padding(.bottom, 2)

            Divider()

            row(key: "Layer", value: resolved.sourceLayer.rawValue)
            row(key: "Experience ID",
                value: resolved.activeExperienceId ?? "none")
            row(key: "Banner Title", value: resolved.activeBannerTitle ?? "—")
            row(key: "Banner Subtitle", value: resolved.activeBannerSubtitle ?? "—")
            row(key: "Accent Color",
                value: resolved.themeTokens?.accentColorHex ?? "—")
            row(key: "Motion Intensity",
                value: resolved.themeTokens.map {
                    String(format: "%.2f", $0.motionIntensity)
                } ?? "—")
            row(key: "Modules",
                value: resolved.allowedModules.map(\.displayName).joined(separator: ", "))
            row(key: "Notification Behavior",
                value: resolved.notificationBehavior)
            row(key: "Safety Behavior",
                value: resolved.safetyBehavior)

            if !resolved.secondaryExperiences.isEmpty {
                row(
                    key: "Secondary (\(resolved.secondaryExperiences.count))",
                    value: resolved.secondaryExperiences.map(\.title).joined(separator: ", ")
                )
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AmenTheme.Colors.statusWarning.opacity(0.08))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.statusWarning.opacity(0.3), lineWidth: 1)
            }
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Resolver debug information")
    }

    // MARK: - Row

    private func row(key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(AMENFont.semiBold(11))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(AMENFont.regular(11))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(value)")
    }
}
#endif
