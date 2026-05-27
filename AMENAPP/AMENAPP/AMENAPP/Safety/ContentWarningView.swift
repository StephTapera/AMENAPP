import SwiftUI

// MARK: - ContentWarningOverlay
// Overlay shown over borderline content (moderationStatus == "borderline").
// The user can tap to reveal the content, or scroll past.

struct ContentWarningOverlay: View {
    let warning: String
    let onReveal: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Content Notice")
                .font(.headline)
            Text(warning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Don't Show") {
                    onHide()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                Button("View Post") {
                    onReveal()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }
}

// MARK: - ContentWarningCard
// Wraps arbitrary content with a content warning that must be dismissed
// before the content is visible.

struct ContentWarningCard<Content: View>: View {
    let warning: String
    @ViewBuilder let content: () -> Content

    @State private var revealed = false
    @State private var hidden = false

    var body: some View {
        if hidden {
            EmptyView()
        } else if revealed {
            content()
        } else {
            ZStack {
                content()
                    .blur(radius: 12)
                    .allowsHitTesting(false)
                ContentWarningOverlay(
                    warning: warning,
                    onReveal: { withAnimation { revealed = true } },
                    onHide: { withAnimation { hidden = true } }
                )
            }
        }
    }
}

// MARK: - ContentWarningBanner
// Inline banner for composers when a post has a borderline score.
// Shown above the submit button to inform the author their post will carry a label.

struct ContentWarningBanner: View {
    let warning: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Content notice will be added")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Button("Got it") { onDismiss() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
