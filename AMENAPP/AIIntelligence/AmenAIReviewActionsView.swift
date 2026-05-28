import SwiftUI

struct AmenAIReviewActionsView: View {
    let isApproveEnabled: Bool
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onReject: () -> Void
    let onApprove: () -> Void

    var body: some View {
        AmenIntentiveActionTray(label: "Review actions", density: .compact) {
            AmenLiquidGlassPillButton(title: "Edit", systemImage: "pencil", isLoading: false, isDisabled: false, hint: "Allows you to modify the text before approving", action: onEdit)
            AmenLiquidGlassPillButton(title: "Regenerate", systemImage: "arrow.clockwise", isLoading: false, isDisabled: false, hint: "Requests a new response from Berean AI", action: onRegenerate)
            AmenLiquidGlassPillButton(title: "Reject", systemImage: "xmark", isLoading: false, isDisabled: false, hint: "Discards this response without saving", action: onReject)
            AmenLiquidGlassPillButton(title: "Approve", systemImage: "checkmark", isLoading: false, isDisabled: !isApproveEnabled, hint: "Confirms this response and adds it to your note", action: onApprove)
        }
    }
}
