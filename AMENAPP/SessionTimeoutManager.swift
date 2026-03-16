//
//  SessionTimeoutManager.swift
//  AMENAPP
//
//  Session timeout and auto-logout management
//  Tracks user activity and signs out after inactivity period
//

import Foundation
import FirebaseAuth
import UIKit
import Combine

@MainActor
class SessionTimeoutManager: ObservableObject {
    static let shared = SessionTimeoutManager()

    // MARK: - Configuration

    /// Inactivity timeout (30 minutes) — applies when Remember Me is OFF.
    private let timeoutDuration: TimeInterval = 30 * 60

    /// Warning window before inactivity logout (5 minutes).
    private let warningDuration: TimeInterval = 5 * 60

    /// Hard session age cap even for Remember Me sessions (30 days).
    private let maxSessionAgeDays: Int = 30

    // MARK: - Published State

    @Published var showTimeoutWarning = false
    @Published var secondsUntilLogout: Int = 0
    @Published var isSessionActive = false

    // MARK: - Private Properties

    private var lastActivityTime: Date = Date()
    private var backgroundEntryTime: Date?
    private var timeoutTimer: Timer?
    private var warningTimer: Timer?
    private var maxAgeTimer: Timer?
    private var countdownTimer: Timer?
    private var activityObservers: [NSObjectProtocol] = []
    private var isEnabled = true
    private var rememberMeEnabled = false

    private let udSessionStartKey = "session_start_date"

    // MARK: - Initialization

    private init() {
        setupActivityMonitoring()
        checkAuthState()
    }

    deinit {
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()
        maxAgeTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Returns the persisted Remember Me preference.
    /// P2-6 FIX: Defaults to `false` (require re-auth after inactivity) rather than `true`.
    /// Defaulting to `true` meant every new install silently opted into indefinite sessions,
    /// which is unexpected for a faith app handling personal/spiritual content.
    /// Users who want to stay signed in can explicitly enable Remember Me in settings.
    /// Nonisolated so it can be used as a default parameter value.
    nonisolated static func _storedRememberMe() -> Bool {
        guard UserDefaults.standard.object(forKey: "rememberMe") != nil else { return false }
        return UserDefaults.standard.bool(forKey: "rememberMe")
    }

    /// Start session timeout monitoring.
    /// - Parameter rememberMe: When true, inactivity timeout is disabled but the 30-day hard cap still applies.
    ///   Defaults to the stored Remember Me preference (which itself defaults to `false` when never set).
    func startMonitoring(rememberMe: Bool = SessionTimeoutManager._storedRememberMe()) {
        guard Auth.auth().currentUser != nil else { return }

        // Avoid duplicate start — already active with same rememberMe setting
        if isSessionActive && rememberMeEnabled == rememberMe { return }

        rememberMeEnabled = rememberMe
        isEnabled = !rememberMe

        isSessionActive = true
        lastActivityTime = Date()

        // Record session start date (only on first start, not on every app launch)
        if UserDefaults.standard.object(forKey: udSessionStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: udSessionStartKey)
        }

        if rememberMe {
            // No inactivity timers, but schedule the hard max-age cap.
            scheduleMaxAgeTimer()
            dlog("⏱️ Session timeout disabled (Remember Me). Hard cap: \(maxSessionAgeDays) days.")
        } else {
            resetTimers()
            dlog("⏱️ Session timeout monitoring started (30 min inactivity timeout).")
        }
    }

    /// Stop session timeout monitoring.
    func stopMonitoring() {
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()
        maxAgeTimer?.invalidate()
        countdownTimer?.invalidate()   // P1 FIX: Also invalidate countdown timer to stop
                                       // secondsUntilLogout from decrementing on a stopped session
        timeoutTimer = nil
        warningTimer = nil
        maxAgeTimer = nil
        countdownTimer = nil
        isSessionActive = false
        showTimeoutWarning = false

        dlog("⏱️ Session timeout monitoring stopped.")
    }

    /// Record user activity to reset inactivity timeout.
    func recordActivity() {
        guard isEnabled, isSessionActive else { return }

        let now = Date()

        // If coming back from background, check total inactive time
        if backgroundEntryTime != nil {
            backgroundEntryTime = nil
            let totalInactiveTime = now.timeIntervalSince(lastActivityTime)

            if totalInactiveTime >= timeoutDuration {
                // User was inactive for the full timeout period — force logout
                forceLogout()
                return
            }

            // Not timed out yet — reset the full countdown from now
            lastActivityTime = now
            showTimeoutWarning = false
            resetTimers()
            return
        }

        lastActivityTime = now

        if showTimeoutWarning {
            showTimeoutWarning = false
            resetTimers()
        }
    }

    /// Extend session when user dismisses the warning overlay.
    func extendSession() {
        showTimeoutWarning = false
        lastActivityTime = Date()
        resetTimers()

        dlog("⏱️ Session extended by user.")
    }

    /// Force logout — called by inactivity timeout, max-age cap, or manual sign-out.
    /// Disables the current device's FCM token before signing out.
    func forceLogout() {
        Task {
            showTimeoutWarning = false
            stopMonitoring()

            // P0 FIX: Use centralized cleanup so session-expiry has identical teardown
            // as a manual sign-out. Previously called Auth.auth().signOut() directly,
            // bypassing all listener cleanup and causing permission_denied floods after
            // the session timed out.
            AppLifecycleManager.shared.performFullSignOutCleanup()

            // Disable FCM token so the device stops receiving push notifications.
            if let uid = Auth.auth().currentUser?.uid {
                await PushNotificationHandler.shared.disableFCMToken(for: uid)
            }

            // Clear the stored session start date.
            UserDefaults.standard.removeObject(forKey: udSessionStartKey)

            do {
                try Auth.auth().signOut()
                dlog("🔐 User signed out (session expired or forced).")
                NotificationCenter.default.post(name: .sessionTimeout, object: nil)
            } catch {
                dlog("❌ Error during force logout: \(error.localizedDescription)")
            }
        }
    }

    /// Enable or disable "Remember Me" mode.
    func setRememberMe(_ enabled: Bool) {
        rememberMeEnabled = enabled
        isEnabled = !enabled

        if enabled {
            // Switch from inactivity timers to max-age-only mode.
            timeoutTimer?.invalidate()
            warningTimer?.invalidate()
            scheduleMaxAgeTimer()
        } else if Auth.auth().currentUser != nil {
            maxAgeTimer?.invalidate()
            startMonitoring(rememberMe: false)
        }

        UserDefaults.standard.set(enabled, forKey: "rememberMe")
    }

    /// Returns whether "Remember Me" is currently enabled.
    /// P1 FIX: Defaults to FALSE (require re-auth after inactivity) to match
    /// `_storedRememberMe()` and the security-conscious policy set at line 67.
    /// Previously defaulted to true, silently opting all new installs into
    /// indefinite sessions and defeating the inactivity timeout entirely.
    func isRememberMeEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: "rememberMe") != nil else {
            return false
        }
        return UserDefaults.standard.bool(forKey: "rememberMe")
    }

    /// Returns the session start date (nil if no active session recorded).
    func sessionStartDate() -> Date? {
        return UserDefaults.standard.object(forKey: udSessionStartKey) as? Date
    }

    // MARK: - Private Methods

    /// Schedules a timer that fires when the 30-day hard cap expires.
    private func scheduleMaxAgeTimer() {
        maxAgeTimer?.invalidate()

        guard let start = sessionStartDate() else {
            // No recorded start — treat as now.
            UserDefaults.standard.set(Date(), forKey: udSessionStartKey)
            scheduleMaxAgeTimer()
            return
        }

        let capDate = Calendar.current.date(byAdding: .day, value: maxSessionAgeDays, to: start) ?? Date()
        let interval = capDate.timeIntervalSinceNow

        guard interval > 0 else {
            // Cap already exceeded — logout immediately.
            forceLogout()
            return
        }

        maxAgeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in self?.forceLogout() }
        }

        dlog("⏱️ Max-age cap scheduled: logout in \(Int(interval / 86400)) days.")
    }

    private func setupActivityMonitoring() {
        // Monitor touch events
        let touchObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordActivity() }
        }
        activityObservers.append(touchObserver)

        // Monitor app becoming active
        let activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordActivity() }
        }
        activityObservers.append(activeObserver)

        // Monitor app entering background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleAppBackground() }
        }
        activityObservers.append(backgroundObserver)
    }

    private func checkAuthState() {
        guard Auth.auth().currentUser != nil else { return }

        let rememberMe = isRememberMeEnabled()

        // Enforce max session age cap on cold launch even for Remember Me sessions.
        if let start = sessionStartDate() {
            let ageInDays = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
            if ageInDays >= maxSessionAgeDays {
                dlog("⏱️ Session exceeded \(maxSessionAgeDays)-day cap — forcing logout.")
                forceLogout()
                return
            }
        }

        startMonitoring(rememberMe: rememberMe)
    }

    private func resetTimers() {
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()
        countdownTimer?.invalidate()
        countdownTimer = nil

        // Set warning timer (25 minutes - shows warning 5 min before logout)
        let warningDelay = timeoutDuration - warningDuration
        warningTimer = Timer.scheduledTimer(
            withTimeInterval: warningDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.showWarning() }
        }

        // Set logout timer (30 minutes)
        timeoutTimer = Timer.scheduledTimer(
            withTimeInterval: timeoutDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleTimeout() }
        }
    }

    private func showWarning() {
        // Do not show warning if:
        //   • inactivity timeout is disabled (rememberMe = true)
        //   • session is not active
        //   • user is not authenticated
        //   • user has been active within the warning window (timer fired but user was still tapping)
        guard isEnabled, isSessionActive, Auth.auth().currentUser != nil else { return }
        let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)
        guard timeSinceActivity >= (timeoutDuration - warningDuration) else {
            // User was active — reset timers silently instead of showing warning
            resetTimers()
            return
        }

        showTimeoutWarning = true
        secondsUntilLogout = Int(warningDuration)

        // Start countdown timer — stored so deinit can invalidate it.
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // Capture timer as nonisolated(unsafe) local to avoid Sendable warning
            nonisolated(unsafe) let t = timer
            Task { @MainActor [weak self] in
                guard let self else { t.invalidate(); return }
                if self.secondsUntilLogout > 0 {
                    self.secondsUntilLogout -= 1
                } else {
                    t.invalidate()
                    self.countdownTimer = nil
                }
            }
        }

        dlog("⚠️ Session timeout warning shown (5 minutes remaining)")
    }

    private func handleTimeout() {
        guard isEnabled, isSessionActive else { return }

        // Check if user was active since warning
        let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)

        if timeSinceActivity >= timeoutDuration {
            forceLogout()
        } else {
            // User was active, reset timers
            resetTimers()
        }
    }

    private func handleAppBackground() {
        // Record when we went to background, stop timers to save battery.
        // On foreground return we'll decide whether to reset or force-logout.
        backgroundEntryTime = Date()
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sessionTimeout = Notification.Name("sessionTimeout")
}

// MARK: - Activity Tracking Window
//
// Subclass UIWindow to intercept all touch events and reset the session inactivity
// timer. This catches touches on any view in the hierarchy — including text fields,
// scroll views, buttons — so that a user actively typing or scrolling is never
// incorrectly timed out.
//
// Usage: attach via ActivityTouchObserver.attach(to:) in AMENAPPApp.onAppear.
// Uses a cancelInHierarchy=false gesture recognizer so it never blocks delivery.

import UIKit

/// Passively observes touches on the existing key window without owning it.
/// Attach once at app startup — does NOT replace or create a new UIWindow.
final class ActivityTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {

    private var lastRecordedActivity: Date = .distantPast

    static func attach(to window: UIWindow) {
        let observer = ActivityTouchObserver(target: nil, action: nil)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesEnded = false
        observer.delegate = observer
        window.addGestureRecognizer(observer)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let now = Date()
        if now.timeIntervalSince(lastRecordedActivity) > 1.0 {
            lastRecordedActivity = now
            SessionTimeoutManager.shared.recordActivity()
        }
        super.touchesBegan(touches, with: event)
        state = .failed  // immediately fail so we never consume the touch
    }

    // Allow simultaneous recognition with everything — we are purely observing
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
}

// MARK: - Session Timeout Warning View

import SwiftUI

struct SessionTimeoutWarningView: View {
    @ObservedObject var sessionManager = SessionTimeoutManager.shared
    @State private var animate = false
    @State private var pulse = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Blurred dark scrim
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .background(Color.black.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture { sessionManager.extendSession() }

            // Liquid Glass card
            VStack(spacing: 0) {

                // MARK: Icon
                ZStack {
                    // Soft glow halo
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)

                    // Glass circle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .white.opacity(0.08), radius: 12, y: 4)

                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse)
                }
                .scaleEffect(animate ? 1.0 : 0.7)
                .opacity(animate ? 1.0 : 0)
                .padding(.top, 36)

                // MARK: Title
                Text("Session Expiring")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .opacity(animate ? 1.0 : 0)

                // MARK: Countdown
                Text(formatTime(sessionManager.secondsUntilLogout))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        sessionManager.secondsUntilLogout < 60
                            ? AnyShapeStyle(Color.red)
                            : AnyShapeStyle(Color.white)
                    )
                    .padding(.top, 6)
                    .opacity(animate ? 1.0 : 0)

                Text("You'll be signed out for your security")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .opacity(animate ? 1.0 : 0)

                // MARK: Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .opacity(animate ? 1.0 : 0)

                // MARK: Buttons
                VStack(spacing: 10) {
                    // Primary — Stay Signed In
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            sessionManager.extendSession()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Stay Signed In")
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                                .shadow(color: .white.opacity(0.15), radius: 8, y: 3)
                        )
                    }

                    // Secondary — Sign Out
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            sessionManager.forceLogout()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .medium))
                            Text("Sign Out Now")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
            }
            // Liquid Glass card background
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.black.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            )
            .padding(.horizontal, 28)
            .scaleEffect(animate ? 1.0 : 0.88)
            .opacity(animate ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                animate = true
            }
            pulse = true
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview("Session Timeout Warning") {
    ZStack {
        LinearGradient(
            colors: [Color.black, Color(white: 0.08)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        SessionTimeoutWarningView()
    }
}

// MARK: - App Ready State Manager

/// Tracks whether the app has completed its post-sign-in load sequence.
/// Shows the cinematic loading screen until auth + initial feed data are both ready.
@MainActor
class AppReadyStateManager: ObservableObject {
    static let shared = AppReadyStateManager()

    /// True while the loading screen should be displayed.
    /// Pre-set to `true` on init if a Firebase user is already cached, so the overlay
    /// is visible from the very first ContentView render — eliminating the separate
    /// `isResolvingAuthState` Screen 1 and the white flash that followed its exit.
    @Published var isShowingLoadingScreen: Bool

    private init() {
        // If a user session is already cached, start with the overlay visible.
        // This means the overlay is already `true` before ContentView renders its body,
        // so there is only ever ONE loading state — no dual-screen flicker.
        isShowingLoadingScreen = Auth.auth().currentUser != nil
    }

    /// Called when a user signs in (fresh install, sign-out + sign-back-in, update).
    func signalSignIn() {
        dlog("🚦 [LAUNCH] signalSignIn() → isShowingLoadingScreen = true")
        isShowingLoadingScreen = true
    }

    /// Called from ContentView.mainContent.onAppear — ensures the screen is showing
    /// even on the path where signalSignIn() fires before the view tree is ready.
    func startIfNeeded() {
        if !isShowingLoadingScreen {
            isShowingLoadingScreen = true
        }
    }

    /// Call once posts have been loaded (or after a maximum wait) to dismiss the screen.
    func signalReady() {
        guard isShowingLoadingScreen else {
            dlog("🚦 [LAUNCH] signalReady() called but screen already hidden — no-op")
            return
        }
        dlog("🚦 [LAUNCH] signalReady() → isShowingLoadingScreen = false (animating out)")
        withAnimation(.easeInOut(duration: 0.6)) {
            isShowingLoadingScreen = false
        }
    }
}

// MARK: - App Loading Screen

// MARK: - Glass Disc Shape

/// A single lens-shaped glass disc drawn as a filled oval with a thin rim highlight.
private struct GlassDisc: View {
    var width: CGFloat
    var height: CGFloat
    // 0 = completely edge-on, 1 = fully face-on
    var faceFraction: CGFloat

    var body: some View {
        ZStack {
            // Disc body — subtle frosted white
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18 * faceFraction),
                            Color.white.opacity(0.04 * faceFraction)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width, height: height)

            // Inner specular highlight (top-left lozenge)
            Ellipse()
                .fill(Color.white.opacity(0.32 * faceFraction))
                .frame(width: width * 0.55, height: height * 0.35)
                .offset(x: -width * 0.12, y: -height * 0.14)
                .blur(radius: 4)

            // Thin rim
            Ellipse()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
                .frame(width: width, height: height)
        }
    }
}

// MARK: - Orbiting Disc View

private struct OrbitingDisc: View {
    let config: DiscConfig

    /// Drives the continuous orbit (0 → 1 full revolution).
    @State private var orbit: Double = 0
    /// Drives the disc's own axial spin (tilt oscillation).
    @State private var spin: Double = 0

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let r  = config.orbitRadius

            // Current angle in radians
            let angle = (orbit + config.orbitPhase) * 2 * .pi
            let x = cx + r * cos(angle) - config.discWidth / 2
            let y = cy + r * sin(angle) * config.orbitTilt - config.discHeight / 2

            // Depth cue: discs behind centre are smaller & more transparent
            let depthFactor = (sin(angle) * config.orbitTilt + 1) / 2   // 0…1
            let scale  = 0.62 + depthFactor * 0.38
            let alpha  = 0.45 + depthFactor * 0.55

            // Apparent face fraction from tilt + slow spin
            let tiltAngle = config.baseTilt + spin * config.spinAmplitude
            let face = abs(cos(tiltAngle * .pi / 180))

            GlassDisc(
                width: config.discWidth * scale,
                height: config.discHeight * scale,
                faceFraction: face
            )
            .rotationEffect(.degrees(tiltAngle + config.rotationOffset))
            .opacity(alpha)
            .position(x: x + config.discWidth / 2, y: y + config.discHeight / 2)
        }
        .onAppear {
            withAnimation(
                .linear(duration: config.orbitDuration)
                .repeatForever(autoreverses: false)
            ) { orbit = 1 }

            withAnimation(
                .easeInOut(duration: config.spinDuration)
                .repeatForever(autoreverses: true)
            ) { spin = 1 }
        }
    }
}

// MARK: - Disc Configuration

private struct DiscConfig {
    var orbitRadius: CGFloat
    var orbitPhase: Double       // 0…1 starting phase offset
    var orbitTilt: CGFloat       // y-axis compression (creates 3-D oval orbit)
    var orbitDuration: Double
    var discWidth: CGFloat
    var discHeight: CGFloat
    var baseTilt: Double         // starting tilt in degrees
    var rotationOffset: Double   // flat rotation offset in degrees
    var spinDuration: Double
    var spinAmplitude: Double    // how many degrees the tilt oscillates
}

private func makeDiscs(in size: CGSize) -> [DiscConfig] {
    let r: CGFloat = min(size.width, size.height) * 0.33
    return [
        DiscConfig(orbitRadius: r,       orbitPhase: 0.00, orbitTilt: 0.38, orbitDuration: 9.0,  discWidth: 80,  discHeight: 50,  baseTilt: -25,  rotationOffset: -30,  spinDuration: 3.8, spinAmplitude: 45),
        DiscConfig(orbitRadius: r * 0.9, orbitPhase: 0.14, orbitTilt: 0.42, orbitDuration: 11.5, discWidth: 62,  discHeight: 38,  baseTilt: 40,   rotationOffset: 20,   spinDuration: 4.2, spinAmplitude: 55),
        DiscConfig(orbitRadius: r * 1.1, orbitPhase: 0.28, orbitTilt: 0.35, orbitDuration: 8.2,  discWidth: 74,  discHeight: 44,  baseTilt: 10,   rotationOffset: -55,  spinDuration: 5.1, spinAmplitude: 40),
        DiscConfig(orbitRadius: r * 0.85,orbitPhase: 0.42, orbitTilt: 0.45, orbitDuration: 13.0, discWidth: 55,  discHeight: 34,  baseTilt: -55,  rotationOffset: 45,   spinDuration: 3.5, spinAmplitude: 60),
        DiscConfig(orbitRadius: r * 1.0, orbitPhase: 0.56, orbitTilt: 0.40, orbitDuration: 10.3, discWidth: 86,  discHeight: 52,  baseTilt: 20,   rotationOffset: 10,   spinDuration: 4.7, spinAmplitude: 35),
        DiscConfig(orbitRadius: r * 0.95,orbitPhase: 0.70, orbitTilt: 0.36, orbitDuration: 7.8,  discWidth: 60,  discHeight: 37,  baseTilt: -10,  rotationOffset: -70,  spinDuration: 6.0, spinAmplitude: 50),
        DiscConfig(orbitRadius: r * 1.05,orbitPhase: 0.84, orbitTilt: 0.43, orbitDuration: 12.1, discWidth: 70,  discHeight: 42,  baseTilt: 60,   rotationOffset: 35,   spinDuration: 4.4, spinAmplitude: 48),
    ]
}

// MARK: - App Loading Screen

/// Full-screen launch screen: AMEN logo + tagline centred on a black background,
/// with the 3-dot loading indicator appearing below after a short delay.
/// This is the only launch screen — there is no separate WelcomeScreenView overlay.
struct AppLoadingScreen: View {
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.85
    @State private var taglineOpacity: Double = 0
    @State private var dotsOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image("amen-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 90, height: 90)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                // Tagline
                Text("Social Media, Re-ordered")
                    .font(.system(size: 13, weight: .light))
                    .tracking(2)
                    .foregroundColor(.black.opacity(0.35))
                    .padding(.top, 16)
                    .opacity(taglineOpacity)

                Spacer()

                // Loading dots + status text
                VStack(spacing: 12) {
                    AMENLoadingIndicator(color: .black.opacity(0.3), dotSize: 8, spacing: 7, bounceHeight: 10)

                    Text("Loading your feed...")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.25))
                }
                .opacity(dotsOpacity)
                .padding(.bottom, 60)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Logo fades in immediately
            withAnimation(.easeOut(duration: 0.35)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }
            // Tagline fades in slightly after logo
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                taglineOpacity = 1.0
            }
            // Dots fade in quickly so user sees loading feedback immediately
            withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                dotsOpacity = 1.0
            }
        }
    }
}

#Preview("App Loading Screen") {
    AppLoadingScreen()
}
