import SwiftUI

struct BereanPulseErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.65))
                .accessibilityHidden(true)

            Text(String(localized: "Berean Pulse could not load"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Label(String(localized: "Try again"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.primary, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Attempts to load Berean Pulse again."))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
