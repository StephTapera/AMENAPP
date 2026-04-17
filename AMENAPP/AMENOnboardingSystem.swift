//
//  AMENOnboardingSystem.swift
//  AMENAPP
//
//  Shared design tokens, reusable components, and transition engine
//  for the AMEN onboarding experience.
//
//  Visual language: white / pearl Liquid Glass surfaces · black typography ·
//  premium whitespace · strong hierarchy · spiritual calm
//

import SwiftUI

// MARK: - Design Tokens

enum ONB {
    // Canvas
    static let canvas        = Color(red: 0.974, green: 0.971, blue: 0.966)
    static let canvasDark    = Color(red: 0.068, green: 0.068, blue: 0.072)

    // Ink — black/charcoal on white
    static let inkPrimary    = Color(red: 0.085, green: 0.085, blue: 0.090)
    static let inkSecondary  = Color(red: 0.44,  green: 0.44,  blue: 0.46)
    static let inkTertiary   = Color(red: 0.62,  green: 0.62,  blue: 0.64)
    static let inkRule       = Color(red: 0.85,  green: 0.85,  blue: 0.86)

    // Brand accent — deep spiritual indigo/violet
    static let accent        = Color(red: 0.30,  green: 0.20,  blue: 0.76)
    static let accentSoft    = Color(red: 0.30,  green: 0.20,  blue: 0.76).opacity(0.10)
    static let accentGold    = Color(red: 0.82,  green: 0.64,  blue: 0.22)

    // White Liquid Glass surface tokens
    static let glassFill      = Color.white.opacity(0.80)
    static let glassBorder    = Color.black.opacity(0.07)
    static let glassShadow    = Color.black.opacity(0.05)
    static let glassHighlight = Color.white.opacity(0.90)

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

// MARK: - White Liquid Glass Card

/// Single-material white pearl card. Single `.thinMaterial` pass + white overlay + hairline border.
struct ONBGlassCard<Content: View>: View {
    var padding: EdgeInsets = .init(top: 20, leading: 22, bottom: 20, trailing: 22)
    var cornerRadius: CGFloat = ONB.cardRadius
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(ONB.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ONB.glassBorder, lineWidth: 1)
                    )
            )
            .shadow(color: ONB.glassShadow, radius: 12, y: 3)
            .shadow(color: ONB.glassShadow.opacity(0.5), radius: 3, y: 1)
    }
}

// MARK: - Hero Icon Container

/// Premium glass orb for modal hero icons.
struct AmenOnboardingHeroIcon: View {
    let systemName: String
    var size: CGFloat = 72
    var iconScale: CGFloat = 0.52
    var accent: Color = ONB.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .overlay(Circle().fill(Color.white.opacity(0.85)))
                .overlay(
                    // Top-edge highlight
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.60), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
                .overlay(Circle().strokeBorder(ONB.glassBorder, lineWidth: 1))
                .shadow(color: ONB.glassShadow, radius: 16, y: 4)
                .shadow(color: ONB.glassShadow.opacity(0.4), radius: 4, y: 2)
            Image(systemName: systemName)
                .font(.systemScaled(size * iconScale, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Info Row Card

/// Glass secondary card row — icon well + title + optional subtext.
struct AmenOnboardingInfoRow: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var accent: Color = ONB.accent

    var body: some View {
        HStack(alignment: subtitle.isEmpty ? .center : .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.75)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ONB.glassBorder, lineWidth: 0.75))
                    .shadow(color: ONB.glassShadow, radius: 4, y: 1)
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: subtitle.isEmpty ? 0 : 3) {
                Text(title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(ONB.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.systemScaled(13, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.72)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ONB.glassBorder, lineWidth: 0.75))
        )
        .shadow(color: ONB.glassShadow, radius: 6, y: 2)
    }
}

// MARK: - Primary CTA Button

struct ONBPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var trailingIcon: String = "arrow.right"
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
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(ONB.ctaFont())
                        if !trailingIcon.isEmpty {
                            Image(systemName: trailingIcon)
                                .font(.systemScaled(13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            // HIGH FIX: minHeight so button grows with Dynamic Type at AX sizes
            .frame(minHeight: 56)
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
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(ONB.inkSecondary)
                .frame(maxWidth: .infinity)
                // HIGH FIX: minHeight so secondary button grows with Dynamic Type
                .frame(minHeight: 48)
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
                .font(.systemScaled(34, weight: .bold))
                .foregroundStyle(ONB.inkPrimary)
                .tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

            Text(subheadline)
                .font(.systemScaled(17, weight: .regular))
                .foregroundStyle(ONB.inkSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.55, dampingFraction: 0.78)).delay(0.05)) {
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
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: size * 0.28).fill(Color.white.opacity(0.80)))
                .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(ONB.glassBorder, lineWidth: 0.75))
                .frame(width: size, height: size)
                .shadow(color: ONB.glassShadow, radius: 4, y: 1)
            Image(systemName: systemName)
                .font(.systemScaled(size * 0.42, weight: .semibold))
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
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(ONB.inkPrimary)
                Text(description)
                    .font(.systemScaled(14, weight: .regular))
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
                withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.75))) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(ONB.accent)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(category)
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(ONB.inkPrimary)
                        Text(detail)
                            .font(.systemScaled(12, weight: .regular))
                            .foregroundStyle(ONB.inkSecondary)
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(ONB.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(why)
                    .font(.systemScaled(12, weight: .regular))
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

// MARK: - AMEN Logo Mark

struct ONBAMENLogo: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(ONB.inkPrimary)
                .frame(width: size, height: size)
            Image(systemName: "cross.fill")
                .font(.systemScaled(size * 0.42, weight: .regular))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Onboarding Step Transition

struct ONBStepTransition<Content: View>: View {
    let step: Int
    @ViewBuilder var content: () -> Content

    @State private var appeared = false

    var body: some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 22)
            .id(step)
            .onAppear {
                appeared = false
                withAnimation(Motion.adaptive(.spring(response: 0.50, dampingFraction: 0.82))) {
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
                .font(.systemScaled(10, weight: .semibold))
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
                .font(.systemScaled(16, weight: .regular))
                .foregroundStyle(ONB.inkPrimary)
                .focused($focused)

                if showPasswordToggle {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.systemScaled(15))
                            .foregroundStyle(ONB.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.72)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                focused ? ONB.accent.opacity(0.4) : ONB.glassBorder,
                                lineWidth: focused ? 1.5 : 1
                            )
                    )
            )
            .shadow(color: ONB.glassShadow, radius: 4, y: 1)
            .animation(.easeInOut(duration: 0.18), value: focused)
        }
    }
}

// MARK: - Toggle Row

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
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(ONB.inkPrimary)
                Text(description)
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(ONB.inkSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ONB.accent)
        }
    }
}
