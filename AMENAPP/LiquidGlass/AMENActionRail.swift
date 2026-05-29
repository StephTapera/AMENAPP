// AMENActionRail.swift
// AMEN App — Vertical right-edge action rail for immersive media screens.
//
// Each button is a frosted white glass circle (amenGold tint for active states).
// Used exclusively inside AMENMediaViewer — not wired into the main feed.
// iOS 26+: native glassEffect.  iOS 17-25: ultraThinMaterial fallback.

import SwiftUI

// MARK: - AMENActionRail

struct AMENActionRail: View {
    var likeCount:    Int  = 0
    var commentCount: Int  = 0
    var shareCount:   Int  = 0
    var isLiked:  Bool = false
    var isSaved:  Bool = false

    var onLike:    (() -> Void)? = nil
    var onComment: (() -> Void)? = nil
    var onShare:   (() -> Void)? = nil
    var onSave:    (() -> Void)? = nil
    var onMore:    (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: AMENGlassMediaTokens.railSpacing) {
            railItem(
                icon:   isLiked ? "heart.fill" : "heart",
                tint:   isLiked ? Color.amenGold : Color.primary,
                count:  likeCount,
                label:  isLiked ? "Unlike" : "Like",
                action: onLike
            )
            railItem(
                icon:   "bubble.left",
                count:  commentCount,
                label:  "Comment",
                action: onComment
            )
            railItem(
                icon:   "arrowshape.turn.up.right",
                label:  "Share",
                action: onShare
            )
            railItem(
                icon:  isSaved ? "bookmark.fill" : "bookmark",
                tint:  isSaved ? Color.amenGold : Color.primary,
                label: isSaved ? "Saved" : "Save",
                action: onSave
            )
            railItem(
                icon:   "ellipsis",
                label:  "More options",
                action: onMore
            )
        }
        .padding(.vertical, 12)
    }

    // MARK: - Single Rail Item

    @ViewBuilder
    private func railItem(
        icon:   String,
        tint:   Color = .primary,
        count:  Int?  = nil,
        label:  String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action?()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    glassCircle
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                .frame(
                    width:  AMENGlassMediaTokens.railButtonSize,
                    height: AMENGlassMediaTokens.railButtonSize
                )

                if let c = count, c > 0 {
                    Text(c >= 10_000 ? "\(c / 1000)k" : "\(c)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.80))
                }
            }
        }
        .buttonStyle(AMENRailButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
    }

    // MARK: - Glass Circle Surface

    @ViewBuilder
    private var glassCircle: some View {
        if reduceTransparency {
            Circle()
                .fill(Color(.systemBackground).opacity(0.90))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8))
        } else if #available(iOS 26.0, *) {
            Circle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Circle())
                .overlay(Circle().fill(Color.white.opacity(AMENGlassMediaTokens.idleFrostOpacity)))
                .overlay(Circle().strokeBorder(Color.white.opacity(AMENGlassMediaTokens.strokeOpacity), lineWidth: 0.8))
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color.white.opacity(AMENGlassMediaTokens.idleFrostOpacity)))
                .overlay(Circle().strokeBorder(Color.white.opacity(AMENGlassMediaTokens.strokeOpacity), lineWidth: 0.8))
        }
    }
}

// MARK: - Button Style

private struct AMENRailButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? AmenGlassBehavior.pressedScale : 1.0)
            .animation(reduceMotion ? nil : Motion.liquidSpring, value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var liked = false

    ZStack {
        LinearGradient(
            colors: [Color(red: 0.85, green: 0.80, blue: 0.70), .white],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()

        HStack {
            Spacer()
            AMENActionRail(
                likeCount: 570,
                commentCount: 10,
                isLiked: liked,
                onLike: { liked.toggle() }
            )
            .padding(.trailing, AMENGlassMediaTokens.railTrailingInset)
        }
    }
}
