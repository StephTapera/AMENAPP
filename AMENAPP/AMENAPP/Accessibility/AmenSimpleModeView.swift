// AmenSimpleModeView.swift
// AMENAPP — Accessibility
//
// Full-screen Simple Mode home for elderly and low-tech-literacy users.
// Five large one-tap actions in a vertical glass-card stack; no feeds,
// no discovery rails, no navigation complexity.
//
// Glass surface: .ultraThinMaterial (or .ultraThickMaterial when high-contrast
// is on) + white border overlay + shadow — matches the pattern from
// LiquidGlassTokens and AmenGlassCardModifier. The iOS 26 .glassEffect API
// is NOT used here because these cards live on a solid colour background,
// not on top of a blurred image.
//
// Animations: .amenSpring for card reveal; .amenSnappy for the tap press.

import SwiftUI
import FirebaseAuth

// MARK: - AmenSimpleModeView

struct AmenSimpleModeView: View {

    // MARK: Dependencies

    @Environment(AmenSimpleModeService.self) private var simpleMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Private state

    @State private var appeared = false

    // MARK: First name helper

    private var firstName: String {
        guard let displayName = Auth.auth().currentUser?.displayName,
              !displayName.isEmpty else { return "Friend" }
        return displayName.components(separatedBy: " ").first ?? displayName
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // Background gradient — warm, non-white so glass cards pop.
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.94, blue: 0.88),
                    Color(red: 0.92, green: 0.90, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Welcome header
                welcomeHeader
                    .padding(.top, 48)
                    .padding(.bottom, 32)

                // Action buttons
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(SimpleModeAction.allCases) { action in
                            SimpleModeButton(
                                action: action,
                                highContrast: simpleMode.useHighContrast
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }

                // Switch to Full Mode link
                switchModeButton
                    .padding(.bottom, 32)
            }
        }
        .dynamicTypeSize(simpleMode.fontScale.dynamicTypeSize)
        .onAppear {
            withAnimation(reduceMotion ? .none : .amenSpring) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Simple Mode home screen")
    }

    // MARK: Welcome header

    private var welcomeHeader: some View {
        VStack(spacing: 6) {
            Text("Good to see you,")
                .font(.title3)
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            Text(firstName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .animation(reduceMotion ? .none : .amenSpring, value: appeared)
    }

    // MARK: Switch to Full Mode

    private var switchModeButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .amenSnappy) {
                simpleMode.isSimpleModeActive = false
            }
            HapticManager.impact(style: .light)
        } label: {
            Text("Switch to Full Mode")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .underline()
        }
        .accessibilityLabel("Switch to Full Mode")
        .accessibilityHint("Returns to the standard AMEN experience with the full feed and navigation.")
    }
}

// MARK: - SimpleModeAction

private enum SimpleModeAction: String, CaseIterable, Identifiable {
    case post       = "Post"
    case call       = "Call"
    case pray       = "Pray"
    case joinChurch = "Join Church"
    case message    = "Message Family"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .post:       return "square.and.pencil"
        case .call:       return "phone.fill"
        case .pray:       return "hands.sparkles"
        case .joinChurch: return "building.columns"
        case .message:    return "message.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .post:       return "Create a post"
        case .call:       return "Make a phone call"
        case .pray:       return "Open prayer"
        case .joinChurch: return "Find and join a church"
        case .message:    return "Message your family"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .post:
            return "Opens the post composer so you can share something with your community."
        case .call:
            return "Opens your phone dialer."
        case .pray:
            return "Opens the prayer feed so you can pray with others."
        case .joinChurch:
            return "Opens the church finder to help you find or join a local church."
        case .message:
            return "Opens your messages so you can send a message to family."
        }
    }

    /// Notification name to post when the button is tapped.
    /// Handlers in ContentView and elsewhere will route these.
    var notificationName: Notification.Name? {
        switch self {
        case .post:       return .openCreatePost
        case .call:       return nil    // routes via system phone dialer
        case .pray:       return Notification.Name("amen.openPrayerComposer")
        case .joinChurch: return .navigateToFindChurch
        case .message:    return Notification.Name("amen.openMessages")
        }
    }

    var accentColor: Color {
        switch self {
        case .post:       return Color.accentColor
        case .call:       return Color(red: 0.18, green: 0.70, blue: 0.38)
        case .pray:       return Color(red: 0.46, green: 0.28, blue: 0.95)
        case .joinChurch: return Color(red: 0.20, green: 0.42, blue: 0.98)
        case .message:    return Color(red: 0.20, green: 0.60, blue: 0.98)
        }
    }
}

// MARK: - SimpleModeButton

private struct SimpleModeButton: View {

    let action: SimpleModeAction
    let highContrast: Bool

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            routeAction()
        } label: {
            HStack(spacing: 20) {
                // Icon container
                ZStack {
                    Circle()
                        .fill(action.accentColor.opacity(highContrast ? 0.25 : 0.14))
                        .frame(width: 60, height: 60)

                    Image(systemName: action.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(highContrast ? .primary : action.accentColor)
                }
                .accessibilityHidden(true)

                // Label
                Text(action.rawValue)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(highContrast ? .primary : AmenTheme.Colors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(highContrast ? .primary : AmenTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 80)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        .animation(reduceMotion ? .none : .amenSnappy, value: isPressed)
        ._onButtonGesture(
            pressing: { pressing in isPressed = pressing },
            perform: {}
        )
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityHint(action.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Background

    @ViewBuilder
    private var buttonBackground: some View {
        if highContrast {
            // Solid, ultra-thick surface so text and icons have maximum contrast
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    // MARK: Action routing

    private func routeAction() {
        HapticManager.impact(style: .medium)

        switch action {
        case .call:
            // Open system phone dialer
            if let url = URL(string: "tel://") {
                UIApplication.shared.open(url)
            }
        default:
            guard let name = action.notificationName else { return }
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}

// MARK: - Animation extensions

private extension Animation {
    /// Reuse the token defined in LiquidGlassMaterial.swift / the AMEN kit.
    static var amenSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.78)
    }
    static var amenSnappy: Animation {
        .spring(response: 0.22, dampingFraction: 0.70)
    }
}

// MARK: - Preview

#Preview("Simple Mode — Standard") {
    AmenSimpleModeView()
        .environment(AmenSimpleModeService.shared)
}

#Preview("Simple Mode — High Contrast") {
    let svc = AmenSimpleModeService.shared
    svc.useHighContrast = true
    return AmenSimpleModeView()
        .environment(svc)
}
