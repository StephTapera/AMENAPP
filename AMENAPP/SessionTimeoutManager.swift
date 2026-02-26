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

    /// Timeout duration in seconds (30 minutes = 1800 seconds)
    private let timeoutDuration: TimeInterval = 30 * 60

    /// Warning duration before logout (5 minutes = 300 seconds)
    private let warningDuration: TimeInterval = 5 * 60

    // MARK: - Published State

    @Published var showTimeoutWarning = false
    @Published var secondsUntilLogout: Int = 0
    @Published var isSessionActive = false

    // MARK: - Private Properties

    private var lastActivityTime: Date = Date()
    private var timeoutTimer: Timer?
    private var warningTimer: Timer?
    private var activityObservers: [NSObjectProtocol] = []
    private var isEnabled = true
    private var rememberMeEnabled = false

    // MARK: - Initialization

    private init() {
        setupActivityMonitoring()
        checkAuthState()
    }

    deinit {
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Start session timeout monitoring
    func startMonitoring(rememberMe: Bool = false) {
        guard Auth.auth().currentUser != nil else { return }

        rememberMeEnabled = rememberMe
        isEnabled = !rememberMe // Disable timeout if "Remember Me" is enabled

        guard isEnabled else {
            print("⏱️ Session timeout disabled (Remember Me enabled)")
            return
        }

        isSessionActive = true
        lastActivityTime = Date()
        resetTimers()

        print("⏱️ Session timeout monitoring started (30 min timeout)")
    }

    /// Stop session timeout monitoring
    func stopMonitoring() {
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()
        timeoutTimer = nil
        warningTimer = nil
        isSessionActive = false
        showTimeoutWarning = false

        print("⏱️ Session timeout monitoring stopped")
    }

    /// Record user activity to reset timeout
    func recordActivity() {
        guard isEnabled, isSessionActive else { return }

        lastActivityTime = Date()

        // Reset warning if user is active
        if showTimeoutWarning {
            showTimeoutWarning = false
            resetTimers()
        }
    }

    /// Extend session when user dismisses warning
    func extendSession() {
        showTimeoutWarning = false
        lastActivityTime = Date()
        resetTimers()

        print("⏱️ Session extended by user")
    }

    /// Force logout (called when timeout expires)
    func forceLogout() {
        Task {
            showTimeoutWarning = false
            stopMonitoring()

            do {
                try Auth.auth().signOut()
                print("🔐 User logged out due to session timeout")

                // Post notification for UI to handle logout
                NotificationCenter.default.post(name: .sessionTimeout, object: nil)
            } catch {
                print("❌ Error during force logout: \(error.localizedDescription)")
            }
        }
    }

    /// Enable or disable "Remember Me" mode
    func setRememberMe(_ enabled: Bool) {
        rememberMeEnabled = enabled
        isEnabled = !enabled

        if enabled {
            stopMonitoring()
        } else if Auth.auth().currentUser != nil {
            startMonitoring(rememberMe: false)
        }

        // Save preference
        UserDefaults.standard.set(enabled, forKey: "rememberMe")
    }

    /// Check if "Remember Me" is enabled
    func isRememberMeEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "rememberMe")
    }

    // MARK: - Private Methods

    private func setupActivityMonitoring() {
        // Monitor touch events
        let touchObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordActivity()
        }
        activityObservers.append(touchObserver)

        // Monitor app becoming active
        let activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordActivity()
        }
        activityObservers.append(activeObserver)

        // Monitor app entering background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppBackground()
        }
        activityObservers.append(backgroundObserver)
    }

    private func checkAuthState() {
        // Start monitoring if user is already signed in
        if Auth.auth().currentUser != nil {
            let rememberMe = isRememberMeEnabled()
            startMonitoring(rememberMe: rememberMe)
        }
    }

    private func resetTimers() {
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()

        // Set warning timer (25 minutes - shows warning 5 min before logout)
        let warningDelay = timeoutDuration - warningDuration
        warningTimer = Timer.scheduledTimer(
            withTimeInterval: warningDelay,
            repeats: false
        ) { [weak self] _ in
            self?.showWarning()
        }

        // Set logout timer (30 minutes)
        timeoutTimer = Timer.scheduledTimer(
            withTimeInterval: timeoutDuration,
            repeats: false
        ) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    private func showWarning() {
        guard isEnabled, isSessionActive else { return }

        showTimeoutWarning = true
        secondsUntilLogout = Int(warningDuration)

        // Start countdown timer
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if self.secondsUntilLogout > 0 {
                self.secondsUntilLogout -= 1
            } else {
                timer.invalidate()
            }
        }

        print("⚠️ Session timeout warning shown (5 minutes remaining)")
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
        // Stop timers in background to save battery
        // Will check timeout when app returns to foreground
        timeoutTimer?.invalidate()
        warningTimer?.invalidate()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sessionTimeout = Notification.Name("sessionTimeout")
}

// MARK: - Session Timeout Warning View

import SwiftUI

struct SessionTimeoutWarningView: View {
    @ObservedObject var sessionManager = SessionTimeoutManager.shared
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    // Extend session if user taps background
                    sessionManager.extendSession()
                }
            
            // Dialog card
            VStack(spacing: 0) {
                // Icon and Header
                VStack(spacing: 20) {
                    // Animated clock icon with pulse effect
                    ZStack {
                        // Pulsing outer ring
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.orange.opacity(0.3),
                                        Color.orange.opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 30,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 140, height: 140)
                            .blur(radius: 10)
                            .scaleEffect(animate ? 1.1 : 1.0)
                        
                        // Glass circle background
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        // Clock icon
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 10, y: 5)
                            .symbolEffect(.pulse)
                    }
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0)
                    
                    VStack(spacing: 12) {
                        Text("Session Expiring Soon")
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.primary)
                            .opacity(animate ? 1.0 : 0)
                        
                        // Countdown timer
                        Text(formatTime(sessionManager.secondsUntilLogout))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: sessionManager.secondsUntilLogout < 60 ? [.red, .orange] : [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .monospacedDigit()
                            .opacity(animate ? 1.0 : 0)
                        
                        Text("You'll be automatically signed out for your security")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .offset(y: animate ? 0 : 20)
                            .opacity(animate ? 1.0 : 0)
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 24)
                
                // Info card
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                    
                    Text("Tap 'Stay Signed In' to continue using AMEN")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.blue.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                // Buttons
                VStack(spacing: 12) {
                    // Primary: Stay Signed In
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            sessionManager.extendSession()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            Text("Stay Signed In")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
                        )
                    }
                    
                    // Secondary: Sign Out
                    Button {
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            sessionManager.forceLogout()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16))
                            Text("Sign Out Now")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 32)
                .offset(y: animate ? 0 : 30)
                .opacity(animate ? 1.0 : 0)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 15)
            )
            .padding(.horizontal, 32)
            .scaleEffect(animate ? 1.0 : 0.9)
            .opacity(animate ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                animate = true
            }
            
            // Start pulsing animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
