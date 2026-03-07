//
//  WelcomeToAMENView.swift
//  AMENAPP
//
//  Premium "Welcome Package" screen shown after onboarding completes.
//  Hero: user's profile photo (full-height feel, edge-feathered).
//  Layout mirrors the reference composition:
//    • Left label "Welcome Package" / right label "Ready"
//    • Two glassmorphic side cards (verse + what you get)
//    • Typewriter animation on verse text only
//    • Specular highlight sweep across hero (once on appear)
//    • Glass cards breathe (subtle opacity/blur pulse)
//    • "Enter AMEN" transitions to main app; "Review Privacy" opens sheet
//

import SwiftUI
import FirebaseAuth

// MARK: - Entry point (preserves existing wiring in ContentView)

struct WelcomeToAMENView: View {
    @Environment(\.dismiss) private var dismiss

    // Derived from the signed-in user at init time (fast, no async)
    private let firstName: String
    private let profilePhotoURL: String?

    init() {
        let user = Auth.auth().currentUser
        // Use displayName first word, fall back to email local part
        let raw = user?.displayName ?? user?.email ?? ""
        firstName = raw.components(separatedBy: CharacterSet(charactersIn: " @")).first
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Friend"
        profilePhotoURL = user?.photoURL?.absoluteString
    }

    var body: some View {
        WelcomePackageView(
            firstName: firstName,
            profilePhotoURL: profilePhotoURL,
            verseText: "The Lord is near to all who call on him, to all who call on him in truth.",
            verseReference: "Psalm 145:18",
            whatYouGet: [
                "A calm feed — no doom scroll",
                "Safer messaging with AI protection",
                "Church Notes that follow your week"
            ],
            onEnter: { dismiss() }
        )
    }
}

// MARK: - WelcomePackageView

struct WelcomePackageView: View {
    let firstName: String
    let profilePhotoURL: String?
    let verseText: String
    let verseReference: String
    let whatYouGet: [String]
    let onEnter: () -> Void

    init(
        firstName: String,
        profilePhotoURL: String?,
        verseText: String,
        verseReference: String,
        whatYouGet: [String],
        onEnter: @escaping () -> Void
    ) {
        self.firstName = firstName
        self.profilePhotoURL = profilePhotoURL
        self.verseText = verseText
        self.verseReference = verseReference
        self.whatYouGet = whatYouGet
        self.onEnter = onEnter
    }

    // Hero reveal
    @State private var heroOpacity: Double = 0
    @State private var heroScale: CGFloat = 1.02
    // Specular sweep position (0 = before left edge, 1 = past right edge)
    @State private var specularX: CGFloat = -0.3
    @State private var specularDidFire = false
    // Labels
    @State private var labelsOpacity: Double = 0
    @State private var labelsOffset: CGFloat = 14
    // Cards
    @State private var cardsOpacity: Double = 0
    @State private var cardsOffset: CGFloat = 20
    @State private var cardBreath: Double = 1.0   // breathing scale for glass cards
    // Header
    @State private var headerOpacity: Double = 0
    @State private var headerOffset: CGFloat = -16
    // CTA
    @State private var ctaOpacity: Double = 0
    @State private var ctaScale: CGFloat = 0.94
    // Exit transition
    @State private var isExiting = false
    // Privacy sheet
    @State private var showPrivacySheet = false
    // Loaded hero image
    @State private var heroImage: UIImage?
    // Typewriter state
    @State private var displayedVerse: String = ""
    @State private var verseComplete = false
    private var typewriterTask: Task<Void, Never>? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Background ──────────────────────────────────────────────
                backgroundLayer

                // ── Main flow layout ────────────────────────────────────────
                VStack(spacing: 0) {

                    // Top header
                    topHeader
                        .padding(.top, geo.safeAreaInsets.top + 20)
                        .padding(.bottom, 16)

                    // Hero + side labels together
                    ZStack {
                        heroLayer(geo: geo)
                        sideLabels(geo: geo)
                    }
                    .frame(height: min(geo.size.height * 0.42, 340))

                    // Glass cards
                    glassCards
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    Spacer(minLength: 12)

                    // CTA
                    bottomCTA
                        .padding(.horizontal, 32)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 24)
                }
                .ignoresSafeArea(edges: .top)

                // ── Vignette overlay ────────────────────────────────────────
                vignetteLayer
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPrivacySheet) { PrivacySummarySheet() }
        .onAppear { runEntrySequence() }
        .onDisappear { /* tasks auto-cancel when view disappears */ }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.11, blue: 0.18),
                Color(red: 0.04, green: 0.06, blue: 0.12),
                Color(red: 0.02, green: 0.03, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Hero

    @ViewBuilder
    private func heroLayer(geo: GeometryProxy) -> some View {
        let heroW = min(geo.size.width * 0.58, 260.0)
        let heroH = min(geo.size.height * 0.42, 340.0)

        ZStack {
            // Profile image
            if let img = heroImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: heroW, height: heroH)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black, .black, .black, .black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: heroW, height: heroH)
                    )
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.white.opacity(0.07))
                    .frame(width: heroW, height: heroH)
                    .overlay(
                        Image(systemName: "person.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: heroW * 0.45)
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }

            // Specular highlight sweep (runs once)
            specularSweep(heroW: heroW, heroH: heroH)
        }
        .frame(width: heroW, height: heroH)
        .opacity(isExiting ? 0.3 : heroOpacity)
        .scaleEffect(heroScale)
        .task { await loadHeroImage(size: CGSize(width: heroW * 3, height: heroH * 3)) }
    }

    @ViewBuilder
    private func specularSweep(heroW: CGFloat, heroH: CGFloat) -> some View {
        // Thin diagonal band of specular light — moves left-to-right once
        let bandW = heroW * 0.35
        LinearGradient(
            colors: [
                .clear,
                .white.opacity(0.10),
                .white.opacity(0.18),
                .white.opacity(0.10),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: bandW, height: heroH * 1.4)
        .rotationEffect(.degrees(15))
        .offset(x: specularX * heroW - bandW / 2)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }

    // MARK: - Vignette

    private var vignetteLayer: some View {
        RadialGradient(
            colors: [.clear, .clear, Color.black.opacity(0.55)],
            center: .center,
            startRadius: 100,
            endRadius: 420
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Top Header

    private var topHeader: some View {
        VStack(spacing: 4) {
            Text("Welcome, \(firstName)")
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Your AMEN welcome package is ready")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.3)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .opacity(headerOpacity)
        .offset(y: headerOffset)
    }

    // MARK: - Side Labels

    @ViewBuilder
    private func sideLabels(geo: GeometryProxy) -> some View {
        HStack(alignment: .center) {
            // Left label
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome\nPackage")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .accessibilityLabel("Welcome Package")

                Text("Verses · Guidance · Safety")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .frame(width: 72, alignment: .leading)
            .offset(x: isExiting ? -20 : 0, y: labelsOffset)
            .animation(isExiting ? .easeIn(duration: 0.22) : nil, value: isExiting)

            Spacer()

            // Right label
            VStack(alignment: .trailing, spacing: 3) {
                Text("Ready")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Ready")

                Text("Tap to Enter")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .frame(width: 72, alignment: .trailing)
            .offset(x: isExiting ? 20 : 0, y: labelsOffset)
            .animation(isExiting ? .easeIn(duration: 0.22) : nil, value: isExiting)
        }
        .padding(.horizontal, 16)
        .opacity(isExiting ? 0 : labelsOpacity)
    }

    // MARK: - Glass Cards

    private var glassCards: some View {
        VStack(spacing: 10) {
            // Card 1: Today's verse (typewriter)
            WPGlassCard(breath: cardBreath) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("A word for you", systemImage: "text.quote")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.8)
                        .textCase(.uppercase)

                    Text(displayedVerse.isEmpty ? " " : displayedVerse)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(verseText)

                    if verseComplete {
                        Text("— \(verseReference)")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Card 2: What you get
            WPGlassCard(breath: cardBreath) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("What you get", systemImage: "sparkles")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.8)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(whatYouGet.prefix(3), id: \.self) { bullet in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 5, height: 5)
                                Text(bullet)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(isExiting ? 0 : cardsOpacity)
        .offset(y: isExiting ? 28 : cardsOffset)
        .animation(isExiting ? .easeIn(duration: 0.2) : nil, value: isExiting)
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 14) {
            // Primary: Enter AMEN
            Button {
                triggerExit()
            } label: {
                HStack(spacing: 10) {
                    Text("Enter AMEN")
                        .font(.custom("OpenSans-Bold", size: 16))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color(red: 0.25, green: 0.45, blue: 1.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.45), radius: 16, y: 6)
                )
            }
            .buttonStyle(MinimalScaleButtonStyle())
            .accessibilityLabel("Enter AMEN — start using the app")

            // Secondary: Review Privacy
            Button {
                showPrivacySheet = true
            } label: {
                Text("Review Privacy")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .underline(true, color: .white.opacity(0.25))
            }
            .accessibilityLabel("Review privacy settings")
        }
        .opacity(ctaOpacity)
        .scaleEffect(ctaScale)
    }

    // MARK: - Entry Sequence

    private func runEntrySequence() {
        // Hero: fade in + scale settle (300ms)
        withAnimation(.easeOut(duration: 0.30)) {
            heroOpacity = 1.0
        }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            heroScale = 1.0
        }

        // Specular sweep (fires once, ~500ms after appear)
        Task { @MainActor in
            guard !specularDidFire else { return }
            specularDidFire = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeInOut(duration: 0.65)) {
                specularX = 1.3
            }
        }

        // Header
        withAnimation(.spring(response: 0.40, dampingFraction: 0.80).delay(0.15)) {
            headerOpacity = 1.0
            headerOffset = 0
        }

        // Side labels
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78).delay(0.28)) {
            labelsOpacity = 1.0
            labelsOffset = 0
        }

        // Cards
        withAnimation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.42)) {
            cardsOpacity = 1.0
            cardsOffset = 0
        }

        // CTA
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78).delay(0.60)) {
            ctaOpacity = 1.0
            ctaScale = 1.0
        }

        // Typewriter — starts after cards appear (~700ms)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await runTypewriter()
        }

        // Card breathing loop (starts after cards visible)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            startCardBreathing()
        }
    }

    // MARK: - Typewriter

    @MainActor
    private func runTypewriter() async {
        displayedVerse = ""
        verseComplete = false
        let chars = Array(verseText)
        for char in chars {
            guard !Task.isCancelled else { return }
            displayedVerse.append(char)
            try? await Task.sleep(nanoseconds: 28_000_000) // ~28ms/char
        }
        withAnimation(.easeIn(duration: 0.25)) {
            verseComplete = true
        }
        // Single subtle haptic on completion
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Card Breathing

    private func startCardBreathing() {
        withAnimation(
            .easeInOut(duration: 4.8)
            .repeatForever(autoreverses: true)
        ) {
            cardBreath = 0.96
        }
    }

    // MARK: - Exit Transition

    private func triggerExit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.22)) {
            isExiting = true
        }
        // Hero dims slightly
        withAnimation(.easeIn(duration: 0.22)) {
            heroOpacity = 0.28
        }
        // CTA hides
        withAnimation(.easeIn(duration: 0.18)) {
            ctaOpacity = 0
            headerOpacity = 0
        }
        // Route after exit animation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            onEnter()
        }
    }

    // MARK: - Image Loading

    @MainActor
    private func loadHeroImage(size: CGSize) async {
        heroImage = await ImageCache.shared.loadImage(url: profilePhotoURL, size: size)
    }
}

// MARK: - Button Style

struct MinimalScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - WPGlassCard

/// Reusable glassmorphic card with breathing animation support.
struct WPGlassCard<Content: View>: View {
    let breath: Double   // 0.96 … 1.0 from parent breathing loop
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .background(
                ZStack {
                    // Blurred material
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    // Tint overlay
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.07),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    // Gradient stroke
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
            .shadow(color: .blue.opacity(0.06), radius: 30, y: 10)
            // Breathing: subtle opacity pulse (no size change to avoid layout thrash)
            .opacity(breath)
    }
}

// MARK: - Privacy Summary Sheet

private struct PrivacySummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(String, String, String)] = [
        ("shield.fill",       "We collect",        "Account info, content you post, and basic interaction signals to personalize your feed."),
        ("xmark.shield.fill", "We don't",          "Sell your data, optimize for addiction, or amplify outrage."),
        ("slider.horizontal.3","You control",      "Reset feed, download data, delete account, toggle personalization, or turn off DMs — anytime in Settings.")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.08, blue: 0.14).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        Text("Privacy at a Glance")
                            .font(.custom("OpenSans-Bold", size: 22))
                            .foregroundStyle(.white)
                            .padding(.top, 8)

                        Text("Here's the short version of what matters.")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)

                        VStack(spacing: 14) {
                            ForEach(items, id: \.1) { icon, title, body in
                                WPGlassCard(breath: 1.0) {
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(.blue.opacity(0.85))
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(title)
                                                .font(.custom("OpenSans-SemiBold", size: 14))
                                                .foregroundStyle(.white)
                                            Text(body)
                                                .font(.custom("OpenSans-Regular", size: 13))
                                                .foregroundStyle(.white.opacity(0.65))
                                                .fixedSize(horizontal: false, vertical: true)
                                                .lineSpacing(3)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.blue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    WelcomePackageView(
        firstName: "Steph",
        profilePhotoURL: nil,
        verseText: "The Lord is near to all who call on him, to all who call on him in truth.",
        verseReference: "Psalm 145:18",
        whatYouGet: [
            "A calm feed — no doom scroll",
            "Safer messaging with AI protection",
            "Church Notes that follow your week"
        ],
        onEnter: {}
    )
}
