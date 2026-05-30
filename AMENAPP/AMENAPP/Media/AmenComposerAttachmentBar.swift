//
//  AmenComposerAttachmentBar.swift
//  AMENAPP
//
//  Standalone attachment chip row + bottom toolbar for the post composer.
//  Injected into MediaPostComposerView — no direct coupling to parent state.
//

import SwiftUI

// MARK: - AmenComposerChipRow

/// Horizontal scrollable chip row displayed above the text input.
/// Shows selected community, music, and scripture as dismissible chips.
struct AmenComposerChipRow: View {

    let communityName: String?
    let musicTitle: String?
    let scriptureRef: String?

    var onTapCommunity: () -> Void
    var onTapMusic: () -> Void
    var onTapScripture: () -> Void
    var onRemoveCommunity: () -> Void
    var onRemoveMusic: () -> Void
    var onRemoveScripture: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {

                // Community chip
                _AttachmentChip(
                    icon: "plus",
                    emptyLabel: "Community or topic",
                    filledLabel: communityName,
                    accentColor: AmenTheme.Colors.amenPurple,
                    onTap: onTapCommunity,
                    onRemove: communityName != nil ? onRemoveCommunity : nil,
                    reduceMotion: reduceMotion
                )
                .accessibilityLabel(
                    communityName != nil
                        ? "Community: \(communityName!). Double-tap to change, swipe to remove."
                        : "Add community or topic"
                )

                // Music chip
                _AttachmentChip(
                    icon: "music.note",
                    emptyLabel: "Music",
                    filledLabel: musicTitle,
                    accentColor: AmenTheme.Colors.amenGold,
                    onTap: onTapMusic,
                    onRemove: musicTitle != nil ? onRemoveMusic : nil,
                    reduceMotion: reduceMotion
                )
                .accessibilityLabel(
                    musicTitle != nil
                        ? "Music: \(musicTitle!). Double-tap to change, swipe to remove."
                        : "Attach music"
                )

                // Scripture chip
                _AttachmentChip(
                    icon: "text.book.closed",
                    emptyLabel: "Scripture",
                    filledLabel: scriptureRef,
                    accentColor: AmenTheme.Colors.amenPurple,
                    onTap: onTapScripture,
                    onRemove: scriptureRef != nil ? onRemoveScripture : nil,
                    reduceMotion: reduceMotion
                )
                .accessibilityLabel(
                    scriptureRef != nil
                        ? "Scripture: \(scriptureRef!). Double-tap to change, swipe to remove."
                        : "Add scripture reference"
                )
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - AmenComposerAttachmentToolbar

/// Bottom icon toolbar with media attachment actions.
struct AmenComposerAttachmentToolbar: View {

    var onPhoto: () -> Void
    var onVideo: () -> Void
    var onGIF: () -> Void
    var onMusic: () -> Void
    var onScripture: () -> Void
    var onPrayer: () -> Void
    var onMore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 1pt separator above toolbar
            Rectangle()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(height: 1)

            HStack(spacing: 0) {
                _ToolbarIcon(systemName: "photo", label: "Add photo", action: onPhoto)
                _ToolbarIcon(systemName: "video", label: "Add video", action: onVideo)
                _ToolbarIcon(systemName: "sparkles", label: "Add GIF", accessibilityLabel: "Add GIF", action: onGIF)
                _ToolbarIcon(systemName: "music.note", label: "Attach music", action: onMusic)
                _ToolbarIcon(systemName: "text.book.closed", label: "Add scripture", action: onScripture)
                _ToolbarIcon(systemName: "hands.sparkles", label: "Add prayer request", action: onPrayer)
                _ToolbarIcon(systemName: "ellipsis", label: "More options", action: onMore)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Private: _AttachmentChip

private struct _AttachmentChip: View {

    let icon: String
    let emptyLabel: String
    let filledLabel: String?
    let accentColor: Color
    let onTap: () -> Void
    let onRemove: (() -> Void)?
    let reduceMotion: Bool

    @GestureState private var isPressed = false

    private var isFilled: Bool { filledLabel != nil }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isFilled ? accentColor : AmenTheme.Colors.textSecondary)
                    .accessibilityHidden(true)

                Text(filledLabel ?? emptyLabel)
                    .font(.system(size: 13, weight: isFilled ? .semibold : .regular))
                    .foregroundColor(
                        isFilled
                            ? AmenTheme.Colors.textPrimary
                            : AmenTheme.Colors.textSecondary
                    )
                    .lineLimit(1)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            )
                    )

                if let remove = onRemove {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AmenTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            )
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        // Liquid glass capsule surface
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isFilled ? 0.20 : 0.10))
                }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isFilled ? 0.40 : 0.25),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.3, dampingFraction: 0.7),
            value: isPressed
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
    }
}

// MARK: - Private: _ToolbarIcon

private struct _ToolbarIcon: View {

    let systemName: String
    let label: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isPressed = false }
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)

                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(
                        isPressed
                            ? AmenTheme.Colors.amenGold
                            : AmenTheme.Colors.textSecondary
                    )
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .frame(maxWidth: .infinity)
        .frame(height: 44)  // minimum tap target
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel ?? label)
    }
}
