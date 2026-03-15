//
//  SundayChurchFocusGateView.swift
//  AMENAPP
//
//  Shabbat Mode — editorial gate screen shown when restricted features are
//  accessed on Sunday. Designed to feel intentional and faith-centered,
//  matching AMEN's Liquid Glass editorial design language.
//

import SwiftUI

// MARK: - Gate View

struct SundayChurchFocusGateView: View {
    @ObservedObject private var focusManager = SundayChurchFocusManager.shared
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTab: Int

    @State private var glowPulse = false
    @State private var appeared = false

    // Warm amber from AMENInboxTokens
    private let amber = Color(red: 0.85, green: 0.55, blue: 0.15)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // ── Background ────────────────────────────────────────────────
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Exit pill (top-right) ─────────────────────────────
                    HStack {
                        Spacer()
                        LiquidGlassToggleButton {
                            focusManager.setOptOut(true)
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    // ── Editorial header ──────────────────────────────────
                    //   "02  rest"  — matches "01  messages" pattern in AMENInbox
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("02")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .kerning(1)
                            .padding(.trailing, 10)

                        Text("rest")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color(.label))
                            .kerning(-1.5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                    // ── Scripture verse ───────────────────────────────────
                    Text("Remember the Sabbath day, to keep it holy.")
                        .font(.system(size: 13, weight: .regular))
                        .italic()
                        .foregroundStyle(amber)
                        .kerning(0.2)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 2)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)

                    Text("Exodus 20:8")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .kerning(0.5)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .opacity(appeared ? 1 : 0)

                    // ── Glassmorphic icon ─────────────────────────────────
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            amber.opacity(glowPulse ? 0.18 : 0.08),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 75
                                    )
                                )
                                .frame(width: 150, height: 150)

                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 96, height: 96)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.45),
                                                    Color.white.opacity(0.08)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)

                            // Shimmer overlay
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.28), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .center
                                    )
                                )
                                .frame(width: 96, height: 96)
                                .opacity(glowPulse ? 0.35 : 0.55)

                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [amber, amber.opacity(0.65)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .scaleEffect(glowPulse ? 1.04 : 1.0)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 28)

                    // ── Description block ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shabbat Mode")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(.label))

                        Text("A dedicated space for worship and spiritual growth. The feed is paused so you can be fully present.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineSpacing(3)

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(.tertiaryLabel))
                            Text("Active \(focusManager.windowDescription)")
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)

                    // ── Available features card ───────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        // Section label (matches InboxSectionLabel pattern)
                        Text("AVAILABLE NOW")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .kerning(0.8)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        VStack(spacing: 0) {
                            FeatureButton(
                                icon: "note.text",
                                iconGradient: [amber, amber.opacity(0.6)],
                                title: "Church Notes",
                                subtitle: "Take notes during service"
                            ) {
                                selectedTab = 3
                                dismiss()
                            }

                            Divider()
                                .padding(.leading, 68)
                                .opacity(0.5)

                            FeatureButton(
                                icon: "building.columns",
                                iconGradient: [amber, amber.opacity(0.6)],
                                title: "Find a Church",
                                subtitle: "Discover churches near you"
                            ) {
                                selectedTab = 3
                                dismiss()
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.3),
                                                    Color.white.opacity(0.05)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0)

                    // ── Settings glass pill ───────────────────────────────
                    Button {
                        NotificationCenter.default.post(name: .navigateToAccountSettings, object: nil)
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 13, weight: .medium))
                            Text("Manage Shabbat Mode")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                Capsule().fill(.ultraThinMaterial)
                                Capsule().strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1 : 0)
                }
            }
        }
        .onAppear {
            // Glow pulse
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            // Staggered entrance
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.08)) {
                appeared = true
            }
        }
    }
}

// MARK: - Feature Button

struct FeatureButton: View {
    let icon: String
    var iconGradient: [Color] = [.blue, .blue.opacity(0.6)]
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: iconGradient.map { $0.opacity(0.15) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: iconGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(.label))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(.secondaryLabel))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.08)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.12)) { isPressed = false }
                }
        )
    }
}

// MARK: - Liquid Glass Toggle Button

struct LiquidGlassToggleButton: View {
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                Text("Exit")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
                }
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToChurchNotes = Notification.Name("navigateToChurchNotes")
    static let navigateToFindChurch = Notification.Name("navigateToFindChurch")
    static let navigateToSettings = Notification.Name("navigateToSettings")
    static let navigateToAccountSettings = Notification.Name("navigateToAccountSettings")
    static let showShabbatModeGate = Notification.Name("showShabbatModeGate")
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab = 0
        var body: some View {
            SundayChurchFocusGateView(selectedTab: $selectedTab)
        }
    }
    return PreviewWrapper()
}
