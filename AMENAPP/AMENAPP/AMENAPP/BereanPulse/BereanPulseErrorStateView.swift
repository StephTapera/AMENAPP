import SwiftUI

struct BereanPulseErrorStateView: View {
    let message: String
    let isAuthError: Bool
    let onRetry: () -> Void

    init(message: String, isAuthError: Bool = false, onRetry: @escaping () -> Void) {
        self.message = message
        self.isAuthError = isAuthError
        self.onRetry = onRetry
    }

    var body: some View {
        if isAuthError {
            authPromptContent
        } else {
            errorContent
        }
    }

    private var authPromptContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle")
                .font(.systemScaled(30, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(String(localized: "Sign in to unlock Berean Pulse"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "Berean Pulse uses your activity, reflections, and work context to surface what matters most. Sign in to get started."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Text(String(localized: "Sign In"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .background(Color.accentColor, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the sign-in flow."))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var errorContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(30, weight: .semibold))
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
