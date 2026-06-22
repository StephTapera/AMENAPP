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

            Circle()
                .fill(gold.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 140, y: 280)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                // ── Glassmorphic avatar ring ──────────────────────────────
                ZStack {
                    // Gold shimmer ring (rotating conic gradient)
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

                    // Frosted glass backing ring
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 112, height: 112)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)

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
                }
                .opacity(statusOpacity)

                Spacer()

                // ── AMEN watermark ────────────────────────────────────────
                Text("AMEN")
                    .font(.systemScaled(13, weight: .semibold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(ink.opacity(0.12))
                    .padding(.bottom, 44)
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
        withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
            shimmerAngle = 360
        }
    }

    // MARK: - Auth Check

    private func scheduleAuthCheck() {
        authTask = Task {
            // Wait 1 second for animations to settle before checking
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // 4-second timeout
            let didResolve = await withTimeout(seconds: 4) {
                await resolveAuth()
            }

            await MainActor.run {
                if didResolve == true {
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

    private func resolveAuth() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        do {
            try await user.reload()
            return true
        } catch {
            return false
        }
    }

    /// Runs `operation` with a timeout. Returns nil if timed out.
    private func withTimeout<T>(seconds: Double, operation: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }
}
