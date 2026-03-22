//
//  BereanOnboardingView.swift
//  AMENAPP
//
//  First-time onboarding for Berean AI Assistant.
//  Apple Music album detail pattern — full bleed blurred blobs + bottom glass sheet.
//  Black and white liquid glass design with smooth page transitions.
//

import SwiftUI

struct BereanOnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage: Int = 0
    @State private var isPressed = false
    @State private var iconPulse: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -1.2

    // Feature row animation states
    @State private var showRow0 = false
    @State private var showRow1 = false
    @State private var showRow2 = false

    private let totalPages = 4

    var body: some View {
        ZStack {
            // Background blurred blobs
            backgroundBlobs

            VStack(spacing: 0) {
                // Skip button (top-right)
                if currentPage < totalPages - 1 {
                    HStack {
                        Spacer()
                        Button {
                            completeOnboarding()
                        } label: {
                            Text("Skip")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .background(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                                .cornerRadius(20)
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 60)
                    .transition(.opacity)
                }

                Spacer()

                // Hero icon zone (upper 56%)
                liquidGlassIcon
                    .padding(.bottom, 40)

                Spacer()

                // Bottom glass sheet (44% height)
                bottomSheet
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarStyle(.lightContent)
        .onAppear {
            startIconPulse()
            startShimmer()
            animateFeatureRows()
        }
    }

    // MARK: - Background Blobs

    private var backgroundBlobs: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 4 blurred circular blobs
            blobCircle(color: blobColor(index: 0), position: .topLeading)
            blobCircle(color: blobColor(index: 1), position: .topTrailing)
            blobCircle(color: blobColor(index: 2), position: .bottomLeading)
            blobCircle(color: blobColor(index: 3), position: .bottomTrailing)
        }
        .animation(.easeInOut(duration: 0.6), value: currentPage)
    }

    private func blobCircle(color: Color, position: Alignment) -> some View {
        Circle()
            .fill(color)
            .frame(width: 260, height: 260)
            .blur(radius: 45)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position)
            .offset(x: offsetForPosition(position).x, y: offsetForPosition(position).y)
    }

    private func offsetForPosition(_ position: Alignment) -> (x: CGFloat, y: CGFloat) {
        switch position {
        case .topLeading: return (-60, -80)
        case .topTrailing: return (60, -80)
        case .bottomLeading: return (-60, 80)
        case .bottomTrailing: return (60, 80)
        default: return (0, 0)
        }
    }

    private func blobColor(index: Int) -> Color {
        let colors: [[Color]] = [
            // Page 0: pure dark
            [Color(hex: "1a1a1a"), Color(hex: "222222"), Color(hex: "2a2a2a"), Color(hex: "111111")],
            // Page 1: deep navy
            [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460"), Color(hex: "1a1a2e")],
            // Page 2: dark forest
            [Color(hex: "1a2a1a"), Color(hex: "0d1f0d"), Color(hex: "1f2d1f"), Color(hex: "162016")],
            // Page 3: warm amber-dark
            [Color(hex: "2a1a0a"), Color(hex: "1f1408"), Color(hex: "332210"), Color(hex: "251a08")]
        ]
        return colors[currentPage][index]
    }

    // MARK: - Liquid Glass Icon

    private var liquidGlassIcon: some View {
        ZStack {
            // Base glass container
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.white.opacity(0.1))
                .frame(width: 100, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

            // Top sheen overlay
            Ellipse()
                .fill(Color.white.opacity(0.18))
                .blur(radius: 12)
                .scaleEffect(x: 0.7, y: 0.5)
                .offset(x: -8, y: -12)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 32))

            // Icon
            Image(systemName: currentPageIcon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white)

            // Shimmer sweep
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 40)
                .offset(x: shimmerOffset * 150)
                .clipShape(RoundedRectangle(cornerRadius: 32))
        }
        .frame(width: 100, height: 100)
        .scaleEffect(iconPulse)
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 16)
    }

    private var currentPageIcon: String {
        switch currentPage {
        case 0: return "shield.fill"
        case 1: return "text.book.closed.fill"
        case 2: return "chart.line.uptrend.xyaxis"
        case 3: return "exclamationmark.shield"
        default: return "shield.fill"
        }
    }

    // MARK: - Bottom Sheet

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // Top inner glow
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            Divider()
                .opacity(0.12)

            VStack(spacing: 24) {
                // Page content with transition
                ZStack {
                    pageContent(for: currentPage)
                        .id(currentPage)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .animation(.easeInOut(duration: 0.4), value: currentPage)

                // Progress dots
                progressDots
                    .padding(.bottom, 14)

                // Control row
                controlRow
                    .padding(.bottom, 34)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.44)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.06))
    }

    // MARK: - Page Content

    @ViewBuilder
    private func pageContent(for page: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(pageTitle(for: page))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            // Subtitle
            Text(pageSubtitle(for: page))
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 8)

            // Feature rows
            VStack(spacing: 0) {
                featureRow(
                    icon: pageFeatures(for: page)[0].icon,
                    title: pageFeatures(for: page)[0].title,
                    subtitle: pageFeatures(for: page)[0].subtitle,
                    show: showRow0
                )

                Divider()
                    .background(Color.white.opacity(0.07))
                    .padding(.leading, 50)

                featureRow(
                    icon: pageFeatures(for: page)[1].icon,
                    title: pageFeatures(for: page)[1].title,
                    subtitle: pageFeatures(for: page)[1].subtitle,
                    show: showRow1
                )

                Divider()
                    .background(Color.white.opacity(0.07))
                    .padding(.leading, 50)

                featureRow(
                    icon: pageFeatures(for: page)[2].icon,
                    title: pageFeatures(for: page)[2].title,
                    subtitle: pageFeatures(for: page)[2].subtitle,
                    show: showRow2
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Feature Row

    private func featureRow(icon: String, title: String, subtitle: String, show: Bool) -> some View {
        HStack(spacing: 14) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                // Top glow
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(.vertical, 11)
        .opacity(show ? 1 : 0)
        .offset(x: show ? 0 : 12)
    }

    // MARK: - Control Row

    private var controlRow: some View {
        HStack(spacing: 10) {
            // Back button
            if currentPage > 0 {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .clipShape(Circle())
                }
                .transition(.opacity)
            }

            // Primary button
            Button {
                if currentPage == totalPages - 1 {
                    completeOnboarding()
                } else {
                    goForward()
                }
            } label: {
                Text(currentPage == totalPages - 1 ? "Start with Berean" : "Continue")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        ZStack {
                            Color.white

                            // Top sheen
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 22)
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    )
                    .cornerRadius(22)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.25))
                    .frame(width: index == currentPage ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentPage)
            }
        }
    }

    // MARK: - Navigation

    private func goForward() {
        withAnimation(.easeOut(duration: 0.42)) {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
        resetFeatureRowAnimations()
        animateFeatureRows()
    }

    private func goBack() {
        withAnimation(.easeIn(duration: 0.38)) {
            currentPage = max(currentPage - 1, 0)
        }
        resetFeatureRowAnimations()
        animateFeatureRows()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "bereanOnboardingComplete")
        withAnimation(.easeIn(duration: 0.45)) {
            onComplete()
        }
    }

    // MARK: - Animations

    private func startIconPulse() {
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            iconPulse = 1.04
        }
    }

    private func startShimmer() {
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.2
        }
    }

    private func resetFeatureRowAnimations() {
        showRow0 = false
        showRow1 = false
        showRow2 = false
    }

    private func animateFeatureRows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.32)) {
                showRow0 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.easeOut(duration: 0.32)) {
                showRow1 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeOut(duration: 0.32)) {
                showRow2 = true
            }
        }
    }

    // MARK: - Page Data

    private func pageTitle(for page: Int) -> String {
        switch page {
        case 0: return "Meet Berean"
        case 1: return "Ask anything about faith"
        case 2: return "Knows your journey"
        case 3: return "What Berean won't do"
        default: return ""
        }
    }

    private func pageSubtitle(for page: Int) -> String {
        switch page {
        case 0: return "Your AI companion rooted in Scripture. Built for believers. Always Acts 17:11."
        case 1: return "Theology, Scripture, prayer, doubt — Berean handles it all with grace and depth."
        case 2: return "Berean reads your Church Notes and prayer history to give answers that are actually about you."
        case 3: return "Honest about limits. Berean is a tool, not a pastor. It points to Scripture, not itself."
        default: return ""
        }
    }

    private func pageFeatures(for page: Int) -> [(icon: String, title: String, subtitle: String)] {
        switch page {
        case 0:
            return [
                ("lock.shield", "Doctrine checked, always", "Every answer examined against Scripture"),
                ("bubble.left.and.bubble.right", "Conversational and personal", "Not a search engine — a companion"),
                ("lock.fill", "Private and secure", "Your conversations stay with you")
            ]
        case 1:
            return [
                ("quote.bubble", "\"Explain this verse to me\"", "Deep exposition with historical context"),
                ("hands.sparkles", "\"Pray with me about this\"", "Scripture-anchored prayers for your moment"),
                ("magnifyingglass", "\"Is this teaching biblical?\"", "The Acts 17 check — kind, not harsh")
            ]
        case 2:
            return [
                ("person.3.fill", "Connected to your church", "Knows your sermon series and notes"),
                ("heart.fill", "Remembers your prayers", "Surfaces what you prayed — and what was answered"),
                ("waveform.path.ecg", "Tracks your spiritual arc", "Sees your growth, not just your questions")
            ]
        case 3:
            return [
                ("xmark.circle", "Won't replace your pastor", "Always points back to community and leadership"),
                ("xmark.circle", "Won't claim to be infallible", "Flags uncertainty — always verify with Scripture"),
                ("xmark.circle", "Won't sell your data", "Conversations are never used to train AI models")
            ]
        default:
            return []
        }
    }
}

// MARK: - Status Bar Style

extension View {
    func statusBarStyle(_ style: UIStatusBarStyle) -> some View {
        self.modifier(StatusBarStyleModifier(style: style))
    }
}

private struct StatusBarStyleModifier: ViewModifier {
    let style: UIStatusBarStyle

    func body(content: Content) -> some View {
        content
            .onAppear {
                UIApplication.shared.setStatusBarStyle(style, animated: false)
            }
    }
}

extension UIApplication {
    func setStatusBarStyle(_ style: UIStatusBarStyle, animated: Bool) {
        if let statusBar = self.windows.first?.windowScene?.statusBarManager {
            // Status bar style is controlled by the view controller
        }
    }
}
