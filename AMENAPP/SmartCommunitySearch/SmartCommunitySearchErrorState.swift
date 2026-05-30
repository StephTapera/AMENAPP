import SwiftUI

struct SmartCommunitySearchErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            AmenGlass3DIcon(systemName: "exclamationmark.triangle", tint: AmenTheme.Colors.amenGold, size: 72)
                .accessibilityHidden(true)

            Text("Something went wrong")
                .font(.headline)

            Text("We couldn't complete this search. Please check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: onRetry) {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(AmenTheme.Colors.amenPurple, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("Retry search")

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
