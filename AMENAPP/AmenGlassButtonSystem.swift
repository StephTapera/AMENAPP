//
//  AmenGlassButtonSystem.swift
//  AMENAPP
//
//  Universal AMEN Liquid Glass button system
//

import SwiftUI


enum AmenGlassShape: Equatable {
    case capsule
    case circle
    case rounded(CGFloat)

    var shape: AnyShape {
        switch self {
        case .capsule:
            return AnyShape(Capsule())
        case .circle:
            return AnyShape(Circle())
        case .rounded(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

enum AmenGlassBackground: Equatable {
    case quiet
    case balanced
    case busy
}

enum AmenGlassPlacement: Equatable {
    case inline
    case overlay
    case floating
}

enum AmenGlassRole: Equatable {
    case primary
    case neutral
    case dismiss
    case filter
    case segmented
    case utility
}

struct AmenGlassSize: Equatable {
    let height: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minWidth: CGFloat?
    let font: Font

    static let compact = AmenGlassSize(
        height: 32,
        horizontalPadding: 12,
        verticalPadding: 7,
        minWidth: nil,
        font: AMENFont.semiBold(13)
    )

    static let regular = AmenGlassSize(
        height: 38,
        horizontalPadding: 16,
        verticalPadding: 9,
        minWidth: nil,
        font: AMENFont.semiBold(14)
    )

    static let icon = AmenGlassSize(
        height: 32,
        horizontalPadding: 10,
        verticalPadding: 10,
        minWidth: 32,
        font: AMENFont.semiBold(13)
    )

    static let iconLarge = AmenGlassSize(
        height: 40,
        horizontalPadding: 12,
        verticalPadding: 12,
        minWidth: 40,
        font: AMENFont.semiBold(15)
    )
}

private struct AmenGlassResolvedTokens {
    let baseOpacity: Double
    let highlightOpacity: Double
    let borderOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    let material: Material?
}

private struct AmenGlassTokens {
    static func resolve(
        background: AmenGlassBackground,
        placement: AmenGlassPlacement,
        role: AmenGlassRole,
        isSelected: Bool,
        isPressed: Bool,
        isEnabled: Bool
    ) -> AmenGlassResolvedTokens {
        let material: Material?
        let baseOpacity: Double
        let highlightOpacity: Double
        let borderOpacity: Double

        switch background {
        case .quiet:
            material = nil
            baseOpacity = 0.03
            highlightOpacity = 0.18
            borderOpacity = 0.08
        case .balanced:
            material = .ultraThinMaterial
            baseOpacity = 0.05
            highlightOpacity = 0.22
            borderOpacity = 0.10
        case .busy:
            material = .thinMaterial
            baseOpacity = 0.07
            highlightOpacity = 0.26
            borderOpacity = 0.12
        }

        let roleBoost: Double
        switch role {
        case .primary:
            roleBoost = 0.01
        case .segmented:
            roleBoost = 0.005
        case .filter:
            roleBoost = 0.0
        case .dismiss:
            roleBoost = -0.005
        case .utility:
            roleBoost = 0.0
        case .neutral:
            roleBoost = 0.0
        }

        let selectedBoost = isSelected ? 0.02 : 0.0
        let pressedBoost = isPressed ? 0.015 : 0.0
        let enabledScale = isEnabled ? 1.0 : 0.6

        let shadow: (Double, CGFloat, CGFloat)
        switch placement {
        case .inline:
            shadow = (0.02, 6, 1)
        case .overlay:
            shadow = (0.035, 8, 2)
        case .floating:
            shadow = (0.05, 12, 4)
        }

        return AmenGlassResolvedTokens(
            baseOpacity: (baseOpacity + roleBoost + selectedBoost + pressedBoost) * enabledScale,
            highlightOpacity: highlightOpacity * (isPressed ? 1.15 : 1.0) * enabledScale,
            borderOpacity: (borderOpacity + selectedBoost + (isPressed ? 0.02 : 0.0)) * enabledScale,
            shadowOpacity: shadow.0 * enabledScale,
            shadowRadius: shadow.1,
            shadowYOffset: shadow.2,
            material: material
        )
    }
}

private struct AmenGlassSurfaceLayer: View {
    let shape: AnyShape
    let tokens: AmenGlassResolvedTokens

    var body: some View {
        ZStack {
            if let material = tokens.material {
                shape.fill(material)
            }

            shape.fill(Color.white.opacity(tokens.baseOpacity))

            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(tokens.highlightOpacity),
                        Color.white.opacity(tokens.highlightOpacity * 0.35),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )

            shape.stroke(Color.black.opacity(tokens.borderOpacity), lineWidth: 0.5)
        }
        .shadow(
            color: Color.black.opacity(tokens.shadowOpacity),
            radius: tokens.shadowRadius,
            y: tokens.shadowYOffset
        )
    }
}

struct AmenGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let role: AmenGlassRole
    let size: AmenGlassSize
    let shape: AmenGlassShape
    let background: AmenGlassBackground
    let placement: AmenGlassPlacement
    let isSelected: Bool
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        let tokens = AmenGlassTokens.resolve(
            background: background,
            placement: placement,
            role: role,
            isSelected: isSelected,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled
        )

        return configuration.label
            .font(size.font)
            .foregroundStyle(isEnabled ? foreground : foreground.opacity(0.35))
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(minWidth: size.minWidth, minHeight: size.height)
            .contentShape(shape.shape)
            .background(
                AmenGlassSurfaceLayer(shape: shape.shape, tokens: tokens)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AmenGlassButtonStyle {
    static func amenGlass(
        role: AmenGlassRole = .neutral,
        size: AmenGlassSize = .compact,
        shape: AmenGlassShape = .capsule,
        background: AmenGlassBackground = .balanced,
        placement: AmenGlassPlacement = .inline,
        isSelected: Bool = false,
        foreground: Color = .black
    ) -> AmenGlassButtonStyle {
        AmenGlassButtonStyle(
            role: role,
            size: size,
            shape: shape,
            background: background,
            placement: placement,
            isSelected: isSelected,
            foreground: foreground
        )
    }
}

private struct AmenGlassSurfaceModifier: ViewModifier {
    let role: AmenGlassRole
    let shape: AmenGlassShape
    let background: AmenGlassBackground
    let placement: AmenGlassPlacement
    let isSelected: Bool
    let isPressed: Bool
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let tokens = AmenGlassTokens.resolve(
            background: background,
            placement: placement,
            role: role,
            isSelected: isSelected,
            isPressed: isPressed,
            isEnabled: isEnabled
        )

        content
            .contentShape(shape.shape)
            .background(
                AmenGlassSurfaceLayer(shape: shape.shape, tokens: tokens)
            )
    }
}

extension View {
    func amenGlassSurface(
        role: AmenGlassRole = .neutral,
        shape: AmenGlassShape = .capsule,
        background: AmenGlassBackground = .balanced,
        placement: AmenGlassPlacement = .inline,
        isSelected: Bool = false,
        isPressed: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            AmenGlassSurfaceModifier(
                role: role,
                shape: shape,
                background: background,
                placement: placement,
                isSelected: isSelected,
                isPressed: isPressed,
                isEnabled: isEnabled
            )
        )
    }

    func amenGlassRail(
        background: AmenGlassBackground = .quiet,
        placement: AmenGlassPlacement = .inline
    ) -> some View {
        amenGlassSurface(
            role: .neutral,
            shape: .capsule,
            background: background,
            placement: placement,
            isSelected: false,
            isPressed: false,
            isEnabled: true
        )
    }
}

// =====================================================================
// MARK: - Phase B reusable components (from the §13 interaction audit)
// =====================================================================
//
// Toasts intentionally NOT re-implemented here — the app's canonical toast
// system is `ToastManager` (+ `ToastManagerExtensions`), already mounted
// app-wide. Use `ToastManager.shared.failure(_:retry:)` / `.success(_:)`.

/// Primary async button with a built-in loading/disabled lifecycle driven by
/// `AmenInteractionStateMachine`. Rapid re-taps are ignored while loading (the
/// machine rejects an illegal idle→loading repeat), giving free double-submit
/// protection. Enforces the 44pt minimum target and a VoiceOver label.
public struct AmenLoadingButton: View {
    private let title: String
    private let systemImage: String?
    private let role: ButtonRole?
    private let action: () async -> Void

    @StateObject private var machine = AmenInteractionStateMachine()
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    private var isLoading: Bool { machine.state == .loading }

    public var body: some View {
        Button(role: role) {
            run()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(isLoading ? "" : title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(isLoading || !isEnabled)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }

    private func run() {
        guard machine.transition(to: .loading) else { return }   // ignore rapid re-taps
        Task { @MainActor in
            await action()
            machine.transition(to: .success)
            machine.reset()
        }
    }
}
