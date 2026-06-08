import SwiftUI

struct AmenObjectHubActionDock: View {
    let canonicalObject: AmenCanonicalObject
    let membership: AmenObjectHubMembership?
    let onListen: () -> Void
    let onSaveToSelah: () -> Void
    let onDiscuss: () -> Void
    let onUseInPost: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glass: AmenObjectHubLiquidGlassStyle {
        AmenObjectHubLiquidGlassStyle(reduceTransparency: reduceTransparency, increasedContrast: accessibilityContrast == .increased)
    }

    var body: some View {
        HStack(spacing: 10) {
            dockButton(icon: primaryPlayIcon, label: primaryPlayLabel, hint: primaryPlayAccessibilityHint, onTap: onListen)
            dockButton(icon: "bookmark", label: "Save", hint: "Save to your collection", onTap: onSaveToSelah)
            dockButton(icon: "bubble.left.and.bubble.right", label: "Discuss", hint: "Start a discussion", onTap: onDiscuss)
            dockButton(icon: "plus.square.on.square", label: "Use in Post", hint: "Attach this object to a new post", onTap: onUseInPost)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(glass.materialSurface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(glass.glassBorder, lineWidth: 1))
        .overlay(glass.specularHighlight().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)))
        .shadow(color: glass.shadow, radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hub actions")
    }

    private func dockButton(icon: String, label: String, hint: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(glass.primaryText)
                    .frame(height: 20)
                Text(label)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(glass.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(AmenHubGlassButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    private var primaryPlayIcon: String {
        switch canonicalObject.objectType {
        case .mediaTrack, .album, .playlist: return "play.fill"
        case .video: return "play.rectangle.fill"
        case .podcast: return "mic.fill"
        case .article, .scripture: return "book.fill"
        default: return "arrow.up.right.square"
        }
    }

    private var primaryPlayLabel: String {
        switch canonicalObject.objectType {
        case .mediaTrack, .album, .playlist: return "Listen"
        case .video: return "Watch"
        case .podcast: return "Play"
        case .article, .scripture: return "Read"
        default: return "Open"
        }
    }

    private var primaryPlayAccessibilityHint: String {
        switch canonicalObject.objectType {
        case .mediaTrack, .album, .playlist: return "Listen on provider"
        case .video: return "Watch on provider"
        case .podcast: return "Open podcast"
        case .article, .scripture: return "Read source"
        default: return "Open link"
        }
    }
}
