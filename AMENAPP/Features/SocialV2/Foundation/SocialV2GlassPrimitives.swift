import SwiftUI

enum SocialV2GlassTintContext {
    case neutral
    case interactive
    case state
    case alert

    var tint: Color {
        switch self {
        case .neutral:
            return Color(.sRGB, red: 0.91, green: 0.94, blue: 0.97, opacity: 0.46)
        case .interactive:
            return Color.blue.opacity(0.18)
        case .state:
            return Color.green.opacity(0.18)
        case .alert:
            return Color.blue.opacity(0.16)
        }
    }

    var stroke: Color {
        switch self {
        case .neutral:
            return Color.black.opacity(0.08)
        case .interactive:
            return Color.blue.opacity(0.32)
        case .state:
            return Color.green.opacity(0.32)
        case .alert:
            return Color.blue.opacity(0.42)
        }
    }
}

struct SocialV2GlassCard<Content: View>: View {
    let tintContext: SocialV2GlassTintContext
    let isActive: Bool
    @ViewBuilder let content: Content

    init(
        tintContext: SocialV2GlassTintContext = .neutral,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tintContext = tintContext
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tintContext.tint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintContext.stroke, lineWidth: isActive ? 1.4 : 1)
            }
            .shadow(color: .black.opacity(isActive ? 0.10 : 0.06), radius: isActive ? 14 : 8, y: isActive ? 6 : 3)
            .modifier(SocialV2NativeGlassModifier(tintContext: tintContext))
    }
}

struct SocialV2GlassPill<Label: View>: View {
    let tintContext: SocialV2GlassTintContext
    let isSelected: Bool
    @ViewBuilder let label: Label

    init(
        tintContext: SocialV2GlassTintContext = .interactive,
        isSelected: Bool = false,
        @ViewBuilder label: () -> Label
    ) {
        self.tintContext = tintContext
        self.isSelected = isSelected
        self.label = label()
    }

    var body: some View {
        label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.82 : 0.62))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(isSelected ? tintContext.tint : .clear)
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isSelected ? tintContext.stroke : Color.black.opacity(0.08), lineWidth: 1)
            }
            .modifier(SocialV2NativeGlassModifier(tintContext: tintContext))
    }
}

private struct SocialV2NativeGlassModifier: ViewModifier {
    let tintContext: SocialV2GlassTintContext

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tintContext.tint), in: .rect(cornerRadius: 8))
        } else {
            content
        }
    }
}
