import SwiftUI

struct AuthenticityBadge: View {
    let label: CreatorProvenanceLabel

    var body: some View {
        Label(label.publicDisclosureText, systemImage: iconName)
            .font(AMENFont.semiBold(12))
            .foregroundStyle(label.canShowShotRealBadge ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .amenGlassSurface(shape: .capsule, background: .quiet, placement: .inline)
            .accessibilityLabel(accessibilityText)
            .onAppear {
                CreatorSpacesAnalytics.track(
                    .authenticityBadgeViewed,
                    parameters: ["badge_type": label.publicDisclosureText]
                )
            }
    }

    private var iconName: String {
        if label.canShowShotRealBadge { return "checkmark.seal.fill" }
        if label.editedWithAI { return "wand.and.stars" }
        if !label.editHistory.isEmpty { return "slider.horizontal.3" }
        return "info.circle"
    }

    private var accessibilityText: String {
        if label.canShowShotRealBadge {
            return "Shot Real. Captured on device in AMEN with no edit history and no AI editing."
        }
        return "Media disclosure: \(label.publicDisclosureText)."
    }
}

struct ProvenanceNutritionLabelView: View {
    let label: CreatorProvenanceLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Media Label")
                    .font(AMENFont.semiBold(18))
                    .foregroundStyle(.primary)
                Spacer()
                AuthenticityBadge(label: label)
            }

            VStack(spacing: 10) {
                row("Captured on device", value: label.capturedOnDevice ? "Yes" : "No")
                row("Source camera", value: label.sourceCamera.isEmpty ? "Not disclosed" : label.sourceCamera)
                row("Edit history", value: label.editHistory.isEmpty ? "None" : "\(label.editHistory.count) edit(s)")
                row("AI editing", value: label.editedWithAI ? "Disclosed" : "None disclosed")
                row("Synthetic elements", value: phaseTwoValue(label.syntheticElementsPresent))
                row("Confidence score", value: label.authenticityConfidence.map { "\(Int($0 * 100))%" } ?? "Not measured")
            }
        }
        .padding(16)
        .amenGlassSurface(shape: .rounded(24), background: .balanced, placement: .inline)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AMENFont.medium(13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func phaseTwoValue(_ value: Bool?) -> String {
        guard let value else { return "Not measured" }
        return value ? "Detected" : "Not detected"
    }
}

#Preview {
    ProvenanceNutritionLabelView(
        label: CreatorProvenanceLabel(
            labelId: "preview",
            assetId: "asset",
            capturedOnDevice: true,
            sourceCamera: "iPhone back wide",
            timestampChain: [CreatorProvenanceEvent(event: "capture", ts: Date())],
            editHistory: [],
            editedWithAI: false,
            aiAssistedPercent: nil,
            syntheticElementsPresent: nil,
            authenticityConfidence: nil,
            signature: "preview"
        )
    )
    .padding()
}
