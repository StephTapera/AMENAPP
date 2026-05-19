import SwiftUI

struct AmenAIReviewActionsView: View {
    let isApproveEnabled: Bool
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onReject: () -> Void
    let onApprove: () -> Void

    var body: some View {
        AmenIntentiveActionTray(label: "Review actions", density: .compact) {
            AmenLiquidGlassPillButton(title: "Edit", systemImage: "pencil", isLoading: false, isDisabled: false, action: onEdit)
            AmenLiquidGlassPillButton(title: "Regenerate", systemImage: "arrow.clockwise", isLoading: false, isDisabled: false, action: onRegenerate)
            AmenLiquidGlassPillButton(title: "Reject", systemImage: "xmark", isLoading: false, isDisabled: false, action: onReject)
            AmenLiquidGlassPillButton(title: "Approve", systemImage: "checkmark", isLoading: false, isDisabled: !isApproveEnabled, action: onApprove)
        }
    }
}
