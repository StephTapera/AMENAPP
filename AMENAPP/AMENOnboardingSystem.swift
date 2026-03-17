//
//  AMENOnboardingSystem.swift
//  AMENAPP
//
//  Shared design tokens, reusable components, and transition engine
//  for the redesigned AMEN onboarding experience.
//
//  Visual language: bold editorial typography · liquid-glass surfaces ·
//  premium whitespace · strong hierarchy · spiritual calm
//

import SwiftUI

// MARK: - Design Tokens

enum ONB {
    // Canvas
    static let canvas        = Color(red: 0.974, green: 0.971, blue: 0.966)
    static let canvasDark    = Color(red: 0.068, green: 0.068, blue: 0.072)

    // Ink
    static let inkPrimary    = Color(red: 0.085, green: 0.085, blue: 0.090)
    static let inkSecondary  = Color(red: 0.44,  green: 0.44,  blue: 0.46)
    static let inkTertiary   = Color(red: 0.62,  green: 0.62,  blue: 0.64)
    static let inkRule       = Color(red: 0.85,  green: 0.85,  blue: 0.86)

    // Brand accent — deep spiritual indigo/violet
    static let accent        = Color(red: 0.30,  green: 0.20,  blue: 0.76)
    static let accentSoft    = Color(red: 0.30,  green: 0.20,  blue: 0.76).opacity(0.10)
    static let accentGold    = Color(red: 0.82,  green: 0.64,  blue: 0.22)

    // Glass surface
    static let glassFill     = Color.white.opacity(0.72)
    static let glassBorder   = Color.white.opacity(0.55)
    static let glassShadow   = Color.black.opacity(0.06)

    // Typography scale
    static func heroFont(size: CGFloat = 48) -> Font {
        .system(size: size, weight: .black, design: .default)
    }
    static func titleFont(size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
    static func bodyFont(size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func labelFont(size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    static func ctaFont() -> Font {
        .system(size: 16, weight: .semibold, design: .default)
    }

    // Spacing
    static let pagePadding: CGFloat  = 28
    static let cardRadius: CGFloat   = 20
    static let ctaRadius: CGFloat    = 16
    static let cardSpacing: CGFloat  = 12
}

// MARK: - Page Indicator

struct ONBPageDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? ONB.inkPrimary : ONB.inkRule)
                    .frame(width: i == current ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: current)
            }
        }
    }
}

// MARK: - Liquid Glass Card

struct ONBGlassCard<Content: View>: View {
    var padding: EdgeInsets = .init(top: 20, leading: 22, bottom: 20, trailing: 22)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: ONB.cardRadius, style: .continuous)
                        .fill(ONB.glassFill)
                        .background(
                            RoundedRectangle(cornerRadius: ONB.cardRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    RoundedRectangle(cornerRadius: ONB.cardRadius, style: .continuous)
                        .strokeBorder(ONB.glassBorder, lineWidth: 1)
                }
            )
            .shadow(color: ONB.glassShadow, radius: 16, y: 4)
    }
}

// MARK: - Primary CTA Button

struct ONBPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            guard isEnabled && !isLoading else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack {
                if isLoading {
                    AMENLoadingIndicator(color: .white, dotSize: 8, bounceHeight: 6)
                } else {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(ONB.ctaFont())
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: ONB.ctaRadius, style: .continuous)
                    .fill(isEnabled ? ONB.inkPrimary : ONB.inkTertiary)
                    .animation(.easeInOut(duration: 0.2), value: isEnabled)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - Secondary / Ghost Button

struct ONBSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ONB.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: ONB.ctaRadius, style: .continuous)
                        .strokeBorder(ONB.inkRule, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hero Text Block

struct ONBHeroText: View {
    let headline: String
    let subheadline: String
    var alignment: HorizontalAlignment = .leading

    @State private var appeared = false

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            Text(headline)
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(ONB.inkPrimary)
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

            Text(subheadline)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(ONB.inkSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) {
                appeared = true
            }
        }
    }
}

// MARK: - Accent Icon Badge

struct ONBIconBadge: View {
    let systemName: String
    var size: CGFloat = 48
    var color: Color = ONB.accent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Feature Row

struct ONBFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    var iconColor: Color = ONB.accent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ONBIconBadge(systemName: icon, size: 42, color: iconColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ONB.inkPrimary)
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ONB.inkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Privacy Data Row

struct ONBPrivacyRow: View {
    let icon: String
    let category: String
    let detail: String
    let why: String

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ONB.accent)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(category)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ONB.inkPrimary)
                        Text(detail)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(ONB.inkSecondary)
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ONB.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(why)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ONB.inkSecondary)
                    .lineSpacing(2)
                    .padding(.top, 8)
                    .padding(.leading, 36)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - AMEN Logo Mark (cross in circle)

struct ONBAMENLogo: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(ONB.inkPrimary)
                .frame(width: size, height: size)
            Image(systemName: "cross.fill")
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Onboarding Step Transition

/// Wraps content in a coordinated enter/exit animation keyed on `step`.
/// Used only for onboarding progression — no other views use this.
struct ONBStepTransition<Content: View>: View {
    let step: Int
    @ViewBuilder var content: () -> Content

    @State private var appeared = false

    var body: some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 22)
            .id(step) // force re-render on step change
            .onAppear {
                appeared = false
                withAnimation(.spring(response: 0.50, dampingFraction: 0.82)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Onboarding Input Field

struct ONBInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    var showPasswordToggle: Bool = false
    @Binding var showPassword: Bool
    @FocusState.Binding var focused: Bool

    init(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        isSecure: Bool = false,
        showPasswordToggle: Bool = false,
        showPassword: Binding<Bool>,
        focused: FocusState<Bool>.Binding
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.isSecure = isSecure
        self.showPasswordToggle = showPasswordToggle
        self._showPassword = showPassword
        self._focused = focused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(ONB.inkTertiary)

            HStack {
                Group {
                    if isSecure && !showPassword {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                            .autocorrectionDisabled(keyboardType == .emailAddress)
                    }
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(ONB.inkPrimary)
                .focused($focused)

                if showPasswordToggle {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(ONB.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                focused ? ONB.accent.opacity(0.5) : ONB.inkRule,
                                lineWidth: focused ? 1.5 : 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.18), value: focused)
        }
    }
}

// MARK: - Toggle Row (preference / permission)

struct ONBToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ONBIconBadge(systemName: icon, size: 38, color: ONB.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ONB.inkPrimary)
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ONB.inkSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ONB.accent)
        }
    }
}
