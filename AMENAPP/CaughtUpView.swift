// CaughtUpView.swift
// AMENAPP
//
// "You're All Caught Up" feed-stopper card and companion nudge banners.
//
// Components:
//   CaughtUpCard            — main caught-up card (inline in feed LazyVStack)
//   RapidRefreshNudgeBanner — "Nothing new right now" toast (overlay)
//   DeepScrollNudgeBanner   — "You've been scrolling a while" toast (overlay)
//   AnimatedCheckRing       — spring-drawn gradient ring + checkmark

import SwiftUI

// MARK: - Notification names for CaughtUpCard redirect actions

extension Notification.Name {
    /// Posted when the user taps "Pray" on the CaughtUpCard.
    /// HomeView observes this to switch the feed category to Prayer.
    static let caughtUpOpenPrayer = Notification.Name("caughtUpOpenPrayer")
    /// Posted when the user taps "Ask Berean" on the CaughtUpCard.
    /// HomeView observes this to open the Berean assistant sheet.
    static let caughtUpOpenBerean = Notification.Name("caughtUpOpenBerean")
}

// MARK: - Reflection prompts (shown 30% of the time)

private let reflectionPrompts: [String] = [
    "What encouraged you today?",
    "Consider spending a few minutes in prayer or scripture.",
    "Take a moment to pause and give thanks.",
    "Is there someone you could encourage today?",
    "What is God speaking to your heart right now?",
    "Take a breath. Stillness is a gift.",
]

private func shouldShowReflection() -> Bool {
    Double.random(in: 0..<1) < 0.30
}

// MARK: - CaughtUpCard

struct CaughtUpCard: View {
    var onViewOlder: () -> Void

    @State private var appeared = false
    @State private var reflectionPrompt: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            // Animated ring + check
            AnimatedCheckRing(appeared: appeared)

            // Main text
            VStack(spacing: 8) {
                MaskedSlideUpText(
                    "You're All Caught Up",
                    font: .systemScaled(20, weight: .bold),
                    color: Color(.label),
                    delay: 0.12
                )
                .multilineTextAlignment(.center)

                Text("You've seen all new posts from the past 3 days.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Optional reflection prompt (30% chance)
            if let prompt = reflectionPrompt {
                reflectionCard(prompt)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Redirect action buttons — post NotificationCenter events observed by HomeView
            HStack(spacing: 10) {
                Button {
                    NotificationCenter.default.post(name: .caughtUpOpenPrayer, object: nil)
                } label: {
                    Label("Pray", systemImage: "hands.sparkles.fill")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.50, blue: 0.95))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.35, green: 0.50, blue: 0.95).opacity(0.10))
                                .overlay(Capsule().strokeBorder(Color(red: 0.35, green: 0.50, blue: 0.95).opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(CaughtUpPressStyle())

                Button {
                    NotificationCenter.default.post(name: .caughtUpOpenBerean, object: nil)
                } label: {
                    Label("Ask Berean", systemImage: "sparkles")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.55, green: 0.30, blue: 0.90))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.10))
                                .overlay(Capsule().strokeBorder(Color(red: 0.55, green: 0.30, blue: 0.90).opacity(0.25), lineWidth: 1))
                        )
                }
                .buttonStyle(CaughtUpPressStyle())
            }

            // CTA
            Button(action: onViewOlder) {
                Text("View older posts")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1))
                    )
            }
            .buttonStyle(CaughtUpPressStyle())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .blur(radius: appeared ? 0 : 6)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.48, dampingFraction: 0.78)).delay(0.08)) {
                appeared = true
            }
            if shouldShowReflection() {
                reflectionPrompt = reflectionPrompts.randomElement()
            }
        }
    }

    private func reflectionCard(_ prompt: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.systemScaled(14))
                .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 0.42))

            Text(prompt)
                .font(.systemScaled(14))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.22, green: 0.62, blue: 0.42).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.22, green: 0.62, blue: 0.42).opacity(0.22), lineWidth: 1)
                )
        )
    }
}

// MARK: - AnimatedCheckRing

struct AnimatedCheckRing: View {
    var appeared: Bool

    @State private var ringProgress: CGFloat = 0
    @State private var checkOpacity: Double = 0
    @State private var checkScale: CGFloat = 0.5

    private let ringSize: CGFloat = 64
    private let lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            // Track ring (background)
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)

            // Animated gradient ring
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.28, green: 0.72, blue: 0.50),
                            Color(red: 0.20, green: 0.55, blue: 0.90),
                            Color(red: 0.28, green: 0.72, blue: 0.50),
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))

            // Checkmark
            Image(systemName: "checkmark")
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.28, green: 0.72, blue: 0.50),
                                 Color(red: 0.20, green: 0.55, blue: 0.90)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .opacity(checkOpacity)
                .scaleEffect(checkScale)
        }
        .onChange(of: appeared) { _, isAppeared in
            guard isAppeared else { return }
            // Draw ring first
            withAnimation(.easeOut(duration: 0.55)) {
                ringProgress = 1.0
            }
            // Then pop the check
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.6)).delay(0.50)) {
                checkOpacity = 1.0
                checkScale = 1.0
            }
        }
    }
}

// MARK: - RapidRefreshNudgeBanner

/// "Nothing new right now" — shown as a floating glass capsule when user
/// refreshes the feed 5+ times in 60 seconds.
struct RapidRefreshNudgeBanner: View {
    @Binding var isVisible: Bool

    var body: some View {
        nudgeBanner(
            icon: "arrow.clockwise",
            title: "Nothing new right now",
            subtitle: "Check back in a bit."
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -20)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isVisible)
    }
}

// MARK: - DeepScrollNudgeBanner

/// "You've been scrolling for a while" — shown after 120 posts in a session.
struct DeepScrollNudgeBanner: View {
    @Binding var isVisible: Bool
    var onDismiss: () -> Void

    var body: some View {
        nudgeBanner(
            icon: "hand.raised.fill",
            title: "You've been scrolling for a while",
            subtitle: "Take a moment to pause.",
            onDismiss: onDismiss
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -20)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isVisible)
    }
}

// MARK: - Shared nudge banner builder

private func nudgeBanner(
    icon: String,
    title: String,
    subtitle: String,
    onDismiss: (() -> Void)? = nil
) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.systemScaled(14, weight: .semibold))
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)

        if let dismiss = onDismiss {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
        Capsule()
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    )
    .overlay(
        Capsule()
            .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1)
    )
    .padding(.horizontal, 20)
}

// MARK: - Post visibility tracker modifier

/// Attach to each PostCard. Fires `onSeen` once when the view has been
/// continuously visible for ≥1.5 seconds.
struct PostVisibilityTracker: ViewModifier {
    let postId: String
    var onSeen: (String) -> Void

    @State private var visibilityTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                visibilityTask?.cancel()
                visibilityTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { onSeen(postId) }
                }
            }
            .onDisappear {
                visibilityTask?.cancel()
                visibilityTask = nil
            }
    }
}

extension View {
    /// Mark a post as seen after it has been continuously visible for 1.5 seconds.
    func trackPostVisibility(postId: String, onSeen: @escaping (String) -> Void) -> some View {
        modifier(PostVisibilityTracker(postId: postId, onSeen: onSeen))
    }
    
    /// Track post visibility continuously for intelligent caught-up banner
    func trackPostVisibilityForBanner(postId: String, onChange: @escaping (String, CGFloat, TimeInterval) -> Void) -> some View {
        modifier(PostVisibilityTrackerForBanner(postId: postId, onChange: onChange))
    }
}

// MARK: - Intelligent Banner Visibility Tracker

/// Continuously tracks visibility percentage and dwell time for intelligent banner eligibility
struct PostVisibilityTrackerForBanner: ViewModifier {
    let postId: String
    var onChange: (String, CGFloat, TimeInterval) -> Void
    
    @State private var visibilityRatio: CGFloat = 0
    @State private var visibilityStartTime: Date?
    @State private var updateTimer: Timer?
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: VisibilityPreferenceKey.self, value: geometry.frame(in: .global))
                }
            )
            .onPreferenceChange(VisibilityPreferenceKey.self) { frame in
                updateVisibility(frame: frame)
            }
            .onAppear {
                visibilityStartTime = Date()
                startUpdateTimer()
            }
            .onDisappear {
                stopUpdateTimer()
                visibilityStartTime = nil
            }
    }
    
    private func updateVisibility(frame: CGRect) {
        let screenHeight = ScreenMetrics.bounds.height
        let visibleHeight = min(frame.maxY, screenHeight) - max(frame.minY, 0)
        let totalHeight = frame.height
        
        guard totalHeight > 0 else {
            visibilityRatio = 0
            return
        }
        
        visibilityRatio = max(0, min(1, visibleHeight / totalHeight))
        
        // Notify about visibility change with current dwell time
        if let startTime = visibilityStartTime {
            let dwell = Date().timeIntervalSince(startTime)
            onChange(postId, visibilityRatio, dwell)
        }
    }
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Periodically update dwell time even if visibility hasn't changed
            if let startTime = visibilityStartTime, visibilityRatio > 0 {
                let dwell = Date().timeIntervalSince(startTime)
                onChange(postId, visibilityRatio, dwell)
            }
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

private struct VisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Button style

private struct CaughtUpPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
