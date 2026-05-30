// AutoLoginSplashView.swift
// AMEN App — Premium returning-user splash screen
// Displays cached profile while Firebase silently restores auth.
// Instagram pattern: show cached data instantly, confirm in background.

import SwiftUI
import FirebaseAuth

struct AutoLoginSplashView: View {
    let cachedUsername: String?
    let cachedPhotoURL: URL?
    let onSuccess: () -> Void       // Called when Firebase auth resolves successfully
    let onFailure: () -> Void       // Called on failure / 4s timeout → navigate to LoginView

    // MARK: - Animation State
    @State private var ringScale: CGFloat = 0.7
    @State private var ringOpacity: Double = 0
    @State private var photoScale: CGFloat = 0.5
    @State private var photoOpacity: Double = 0
    @State private var nameOffset: CGFloat = 12
    @State private var nameOpacity: Double = 0
    @State private var statusOpacity: Double = 0
    @State private var shimmerAngle: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Auth State
    @State private var authTask: Task<Void, Never>? = nil

    // MARK: - Colors
    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let ink = Color(red: 0.09, green: 0.09, blue: 0.11)
    private let mist = Color(red: 0.96, green: 0.94, blue: 0.91)

    var body: some View {
        ZStack {
            Color(red: 0.976, green: 0.973, blue: 0.969)
                .ignoresSafeArea()

            Circle()
                .fill(mist.opacity(0.9))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -120, y: -250)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Circle()
                .fill(gold.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 140, y: 280)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer()

                // ── Glassmorphic avatar ring ──────────────────────────────
                ZStack {
                    // Gold shimmer ring (rotating conic gradient) — decorative only
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    gold.opacity(0.0),
                                    gold.opacity(0.55),
                                    gold.opacity(0.0)
                                ],
                                center: .center,
                                startAngle: .degrees(shimmerAngle),
                                endAngle: .degrees(shimmerAngle + 360)
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 112, height: 112)
                        .accessibilityHidden(true)

                    // Frosted glass backing ring — decorative
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 112, height: 112)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
                        .accessibilityHidden(true)

                    // Profile photo
                    Group {
                        if let url = cachedPhotoURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure, .empty:
                                    fallbackAvatar
                                @unknown default:
                                    fallbackAvatar
                                }
                            }
                        } else {
                            fallbackAvatar
                        }
                    }
                    .frame(width: 90, height: 90)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 8)
                    .scaleEffect(photoScale)
                    .opacity(photoOpacity)
                }
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cachedUsername.map { "Profile photo for \($0)" } ?? "AMEN")

                Spacer().frame(height: 28)

                // ── Username ──────────────────────────────────────────────
                Text(cachedUsername ?? "Welcome back")
                    .font(.systemScaled(22, weight: .bold))
                    .foregroundStyle(ink)
                    .offset(y: nameOffset)
                    .opacity(nameOpacity)

                Spacer().frame(height: 14)

                // ── Status + dots ─────────────────────────────────────────
                HStack(spacing: 10) {
                    Text("Signing you in")
                        .font(.systemScaled(15, weight: .light))
                        .foregroundStyle(ink.opacity(0.55))

                    LiquidDotsProgressView(color: ink.opacity(0.75))
                        .accessibilityHidden(true)  // decorative dots; label on parent
                }
                .opacity(statusOpacity)
                .accessibilityLabel("Loading")

                Spacer()

                // ── AMEN watermark ────────────────────────────────────────
                Text("AMEN")
                    .font(.systemScaled(13, weight: .semibold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(ink.opacity(0.12))
                    .padding(.bottom, 44)
                    .accessibilityLabel("AMEN")
            }
        }
        .onAppear {
            runAppearAnimations()
            startShimmer()
            scheduleAuthCheck()
        }
        .onDisappear {
            authTask?.cancel()
        }
    }

    // MARK: - Fallback Avatar

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String((cachedUsername ?? "A").prefix(1)).uppercased())
                .font(.systemScaled(32, weight: .semibold))
                .foregroundStyle(ink.opacity(0.78))
        }
    }

    // MARK: - Animations

    private func runAppearAnimations() {
        // Ring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(Motion.adaptive(.spring(response: 0.55, dampingFraction: 0.72))) {
                ringScale = 1.0
                ringOpacity = 1.0
            }
        }
        // Photo bloom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.68))) {
                photoScale = 1.0
                photoOpacity = 1.0
            }
        }
        // Username slide up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.75))) {
                nameOffset = 0
                nameOpacity = 1.0
            }
        }
        // Status row
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.4)) {
                statusOpacity = 1.0
            }
        }
    }

    private func startShimmer() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
            shimmerAngle = 360
        }
    }

    // MARK: - Auth Check

    private func scheduleAuthCheck() {
        authTask = Task {
            // PERF FIX: resolveAuth() is now a synchronous cache read (no network).
            // We only need to wait long enough for the avatar + name animations to reach
            // a visually comfortable state (~0.8 s covers the ring + photo bloom).
            // The previous 1-second wait was sized for the async `user.reload()` call,
            // which no longer exists. Cutting it saves ~200 ms of splash screen time.
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 s minimum display

            let didResolve = resolveAuth()  // synchronous — no timeout needed

            await MainActor.run {
                if didResolve {
                    withAnimation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.8))) {
                        onSuccess()
                    }
                } else {
                    withAnimation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.8))) {
                        onFailure()
                    }
                }
            }
        }
    }

    private func resolveAuth() -> Bool {
        // PERF FIX: Firebase Auth caches the user session locally and restores it
        // synchronously on launch — no network call is needed to confirm the user is
        // "still logged in" here. The previous `user.reload()` was a full network round-trip
        // (GET /v1/accounts:lookup) that added 300–700 ms to every warm-start splash.
        //
        // The auth state listener in AuthenticationViewModel will independently verify
        // token validity and handle revoked/expired accounts after the first frame.
        // Using the cached user here is correct and matches the Instagram/Threads pattern.
        return Auth.auth().currentUser != nil
    }

}

