// LinkRevokedBanner.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Non-blocking, dismissable banner shown to external members when their
// community's link to this Space is revoked mid-session.
//
// "This Space is no longer shared with your community."
//
// - Auto-dismisses after 5 seconds.
// - Tapping dismisses immediately.
// - Spring animation in/out.
// - Replaces LinkRevokedBannerPlaceholder from Agent C's SpaceDetailView.
//
// Usage: overlay this at the top of SpaceDetailView, driven by
//   CrossCommunityViewModel.showRevokedBanner.

import SwiftUI

struct LinkRevokedBanner: View {

    // MARK: - Parameters

    /// Controls visibility. ViewModel sets this to true when link is revoked.
    @Binding var isVisible: Bool

    // MARK: - Private state

    @State private var autoDismissTask: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        Group {
            if isVisible {
                bannerContent
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)
                        )
                    )
                    .onAppear { scheduleAutoDismiss() }
                    .onDisappear { autoDismissTask?.cancel() }
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring,
            value: isVisible
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This Space is no longer shared with your community.")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Banner content

    private var bannerContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.badge.minus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)

            Text("This Space is no longer shared with your community.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 4)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(6)
                    .background(AmenTheme.Colors.surfaceChip, in: Circle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundPrimary)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(AmenTheme.Colors.amenPurple.opacity(0.08))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .stroke(AmenTheme.Colors.amenPurple.opacity(0.30), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .onTapGesture { dismiss() }
    }

    // MARK: - Auto-dismiss after 5 seconds

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run { dismiss() }
        }
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
            isVisible = false
        }
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview("LinkRevokedBanner") {
    @Previewable @State var shown = true
    VStack {
        if shown {
            LinkRevokedBanner(isVisible: $shown)
        }
        Button("Show banner") { shown = true }
            .buttonStyle(.bordered)
    }
    .padding()
}
#endif
