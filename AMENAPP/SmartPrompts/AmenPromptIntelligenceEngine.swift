import Foundation
import UserNotifications

// MARK: - Prompt Intelligence Engine
//
// Single source of truth for all contextual prompt decisions.
// Callers fire consider(_:metadata:) at trigger points; the engine
// enforces cooldowns, suppression rules, and stacking prevention.
//
// Usage:
//   AmenPromptIntelligenceEngine.shared.consider(.prayerReplyNotifications)
//   AmenPromptIntelligenceEngine.shared.isInLivePrayer = true   // suppress during prayer
//
// Wire into the view hierarchy via:
//   someView.amenContextualPrompts()

@MainActor
final class AmenPromptIntelligenceEngine: ObservableObject {

    nonisolated(unsafe) static let shared = AmenPromptIntelligenceEngine()

    @Published private(set) var activePrompt: AmenContextualPrompt?
    @Published var isPresented = false

    // MARK: - Suppression Context
    // Callers set these before calling consider() to suppress in sacred moments.
    var isInLivePrayer = false
    var isInWorship    = false

    private let defaults = UserDefaults.standard

    // MARK: - Public API

    /// Call at a trigger point. The engine decides silently whether to show.
    func consider(_ type: AmenPromptType, metadata: [String: Any] = [:]) {
        guard AMENFeatureFlags.shared.smartContextualPromptsEnabled else { return }
        guard !isPresented else { return }               // never stack
        guard !isInLivePrayer, !isInWorship else { return }
        guard !isPermanentlyDismissed(type) else { return }
        guard !isOnCooldown(type) else { return }

        if type.isNotificationPermissionPrompt {
            Task { await considerNotificationPrompt(type, metadata: metadata) }
        } else {
            show(type, metadata: metadata)
        }
    }

    /// Call when the user completes the primary action.
    func confirmPrimary() {
        guard let prompt = activePrompt else { return }
        recordShown(prompt.id)
        dismissAnimated()
    }

    /// Call when the user taps "Not now" — starts cooldown.
    func dismissNotNow() {
        guard let prompt = activePrompt else { return }
        recordShown(prompt.id)
        dismissAnimated()
    }

    /// Permanently opt out — prompt will never show again.
    func dismissPermanently() {
        guard let prompt = activePrompt else { return }
        defaults.set(true, forKey: permanentKey(prompt.id))
        dismissAnimated()
    }

    // MARK: - Private

    private func considerNotificationPrompt(_ type: AmenPromptType, metadata: [String: Any]) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        show(type, metadata: metadata)
    }

    private func show(_ type: AmenPromptType, metadata: [String: Any]) {
        activePrompt = AmenContextualPrompt.make(type, metadata: metadata)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isPresented = true
        }
    }

    private func dismissAnimated() {
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            activePrompt = nil
        }
    }

    // MARK: - Cooldown & Persistence

    private func isOnCooldown(_ type: AmenPromptType) -> Bool {
        guard let last = defaults.object(forKey: lastShownKey(type)) as? Date else { return false }
        return Date().timeIntervalSince(last) < TimeInterval(type.cooldownHours * 3_600)
    }

    private func isPermanentlyDismissed(_ type: AmenPromptType) -> Bool {
        defaults.bool(forKey: permanentKey(type))
    }

    private func recordShown(_ type: AmenPromptType) {
        defaults.set(Date(), forKey: lastShownKey(type))
        let count = defaults.integer(forKey: showCountKey(type)) + 1
        defaults.set(count, forKey: showCountKey(type))
        if count >= type.maxShows {
            defaults.set(true, forKey: permanentKey(type))
        }
    }

    private func lastShownKey(_ t: AmenPromptType) -> String { "amenPrompt.lastShown.\(t.rawValue)" }
    private func permanentKey(_ t: AmenPromptType)  -> String { "amenPrompt.permanent.\(t.rawValue)" }
    private func showCountKey(_ t: AmenPromptType)  -> String { "amenPrompt.count.\(t.rawValue)" }
}
