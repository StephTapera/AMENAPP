import SwiftUI

struct GuideMyFeedConfirmationToast: View {
    let response: SubmitFeedDirectionResponse
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 15, weight: .semibold))
                Text(response.confirmationTitle)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Undo") { onUndo() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !response.confirmationBullets.isEmpty {
                Text(response.confirmationBullets.prefix(2).joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(reduceTransparency ? Color(.systemBackground) : .regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -8)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { onDismiss() }
            UIAccessibility.post(notification: .announcement, argument: response.confirmationTitle)
        }
    }
}
