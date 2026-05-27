// BereanMessageTray.swift
// AMEN App — Floating action tray for focused/long-pressed Berean AI messages.
//
// Springs in beneath the focused bubble, dissolves on scroll or tap-away.
// AI messages only — guard against .user role is enforced in body.
//
// Usage:
//   BereanMessageTray(message: msg, isVisible: $trayVisible,
//       onRegenerate: { … }, onShare: { … }, onAudio: { … }, onMore: { … })
//
// Integration note: Parent must set isVisible = false in the scroll
// view's onScrollGeometryChange (or equivalent) to auto-dismiss on scroll.

import SwiftUI

// MARK: - BereanMessageTray

struct BereanMessageTray: View {

    let message: BereanChatMsg
    @Binding var isVisible: Bool
    var onRegenerate: () -> Void
    var onShare: () -> Void
    var onAudio: () -> Void
    var onMore: () -> Void

    // MARK: State

    @State private var showCopied = false
    @State private var copyTask: Task<Void, Never>? = nil

    // MARK: Accessibility

    @Environment(\.accessibilityReduceMotion)     private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Animation constants

    private let floatIn = Animation.spring(response: 0.32, dampingFraction: 0.80)

    // MARK: Body

    var body: some View {
        // Only render for AI (assistant) messages
        if message.role == .assistant {
            ZStack(alignment: .top) {
                // "Copied" toast floats above the tray
                if showCopied {
                    copiedToast
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 4)),
                                removal: .opacity
                            )
                        )
                        .zIndex(1)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // Main tray pill
                trayPill
                    .offset(y: showCopied ? 28 : 0)
            }
            .offset(y: isVisible ? 0 : 8)
            .opacity(isVisible ? 1 : 0)
            .animation(reduceMotion ? .none : floatIn, value: isVisible)
            .animation(reduceMotion ? .none : floatIn, value: showCopied)
        }
    }

    // MARK: - Tray Pill

    private var trayPill: some View {
        HStack(spacing: 0) {
            // ── Primary: Copy ───────────────────────────────────────────────
            Button {
                performCopy()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(AMENFont.medium(14))
                    Text("Copy")
                        .font(AMENFont.medium(14))
                }
                .foregroundStyle(BereanColor.textPrimary)
                .frame(minWidth: 80, minHeight: 44)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy message")
            .accessibilityHint("Copies the full message text to clipboard")

            // ── Hairline divider ────────────────────────────────────────────
            Rectangle()
                .fill(BereanColor.separator)
                .frame(width: 0.5, height: 24)

            // ── Secondaries ─────────────────────────────────────────────────
            secondaryButton(
                icon: "arrow.clockwise",
                label: "Regenerate",
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRegenerate()
                    dismiss()
                }
            )
            secondaryButton(
                icon: "square.and.arrow.up",
                label: "Share",
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onShare()
                    dismiss()
                }
            )
            secondaryButton(
                icon: "speaker.wave.2",
                label: "Audio",
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onAudio()
                    dismiss()
                }
            )

            // ── Hairline divider ────────────────────────────────────────────
            Rectangle()
                .fill(BereanColor.separator)
                .frame(width: 0.5, height: 24)

            // ── Overflow: more actions ───────────────────────────────────────
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onMore()
                dismiss()
            } label: {
                Text("···")
                    .font(AMENFont.medium(16))
                    .foregroundStyle(BereanColor.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")
            .accessibilityHint("Opens full message action menu")
        }
        .background(trayBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(BereanColor.glassBorder, lineWidth: 0.5)
        )
        .shadow(
            color: BereanColor.shadowColor.opacity(0.12),
            radius: 14,
            x: 0,
            y: 4
        )
    }

    // MARK: - Secondary button builder

    @ViewBuilder
    private func secondaryButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(AMENFont.medium(14))
                Text(label)
                    .font(AMENFont.regular(10))
            }
            .foregroundStyle(BereanColor.textSecondary)
            .frame(width: 56, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Copied toast

    private var copiedToast: some View {
        Text("Copied")
            .font(AMENFont.medium(12))
            .foregroundStyle(BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(toastBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(BereanColor.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: BereanColor.shadowColor.opacity(0.10), radius: 8, x: 0, y: 2)
            .accessibilityLabel("Message copied to clipboard")
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Copy logic

    private func performCopy() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIPasteboard.general.string = message.content

        // Cancel any previous auto-dismiss in flight
        copyTask?.cancel()

        withAnimation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.78)) {
            showCopied = true
        }

        copyTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.82)) {
                    showCopied = false
                }
            }
        }
    }

    // MARK: - Dismiss

    private func dismiss() {
        withAnimation(reduceMotion ? .none : floatIn) {
            isVisible = false
        }
    }

    // MARK: - Conditional backgrounds

    private var trayBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var toastBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview("AI message — tray visible") {
    struct Container: View {
        @State private var isVisible = true
        var body: some View {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    // Simulated message bubble
                    HStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .frame(maxWidth: 280)
                            .frame(height: 80)
                            .overlay(
                                Text("For God so loved the world…")
                                    .font(AMENFont.regular(16))
                                    .foregroundStyle(BereanColor.textPrimary)
                                    .padding()
                            )
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    // 8pt gap between bubble bottom and tray
                    Spacer().frame(height: 8)

                    BereanMessageTray(
                        message: BereanChatMsg(
                            role: .assistant,
                            content: "For God so loved the world…",
                            timestamp: .now
                        ),
                        isVisible: $isVisible,
                        onRegenerate: {},
                        onShare: {},
                        onAudio: {},
                        onMore: {}
                    )
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .padding(.top, 120)
            }
        }
    }
    return Container()
}

#Preview("User message — tray hidden") {
    struct Container: View {
        @State private var isVisible = true
        var body: some View {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                BereanMessageTray(
                    message: BereanChatMsg(
                        role: .user,
                        content: "What does John 3:16 mean?",
                        timestamp: .now
                    ),
                    isVisible: $isVisible,
                    onRegenerate: {},
                    onShare: {},
                    onAudio: {},
                    onMore: {}
                )
            }
        }
    }
    return Container()
}
