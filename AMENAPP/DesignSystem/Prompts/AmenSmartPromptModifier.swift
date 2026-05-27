// AmenSmartPromptModifier.swift
// AMEN App — Smart Prompt Surface Integration Modifier
//
// Thin view modifier that connects any AMEN surface to the prompt engine.
// Surface views call .amenSmartPrompt(surface:trigger:context:) and the
// modifier handles eligibility, presentation, permission requests, and
// dismissal with zero additional logic in the host view.
//
// Usage (e.g. in PrayerView.swift):
//
//   @State private var promptTrigger = false
//
//   Button("Post Prayer") {
//       postPrayer()
//       promptTrigger = true
//   }
//   .amenSmartPrompt(surface: .prayerRequests, trigger: $promptTrigger) {
//       var ctx = AmenSmartPromptContext()
//       ctx.notificationPermissionStatus = await UNUserNotificationCenter
//           .current().notificationSettings().authorizationStatus
//       return ctx
//   }
//
// Rules enforced here:
//   - Native permission dialog fires ONLY after user taps primary CTA
//   - No stacked prompts (modifier guards activePrompt == nil)
//   - Banner auto-dismisses after 6 seconds
//   - Permission result is recorded to analytics

import SwiftUI
import UserNotifications

// MARK: - View Extension

extension View {

    /// Attaches smart contextual prompt behaviour to this view.
    ///
    /// - Parameters:
    ///   - surface: The AMEN surface this view represents.
    ///   - trigger: A Bool binding. When it becomes `true`, the engine
    ///              checks eligibility and shows a prompt if appropriate.
    ///              The modifier resets it to `false` automatically.
    ///   - context: Async closure that produces the current app state.
    ///              Called once at trigger time, before the eligibility check.
    func amenSmartPrompt(
        surface: AmenSmartPromptSurface,
        trigger: Binding<Bool>,
        context: @escaping @Sendable () async -> AmenSmartPromptContext = { AmenSmartPromptContext() }
    ) -> some View {
        modifier(AmenSmartPromptModifier(
            surface: surface,
            trigger: trigger,
            contextProvider: context
        ))
    }
}

// MARK: - Modifier

private struct AmenSmartPromptModifier: ViewModifier {

    let surface: AmenSmartPromptSurface
    @Binding var trigger: Bool
    let contextProvider: @Sendable () async -> AmenSmartPromptContext

    @State private var activePrompt: AmenSmartPrompt?
    @State private var showSheet = false
    @State private var autoDismissTask: Task<Void, Never>?

    private let engine = AmenSmartPromptEngine.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, fired in
                guard fired else { return }
                trigger = false
                Task { await considerPrompt() }
            }
            .overlay(alignment: .bottom) { cardOverlay }
            .overlay(alignment: .top)    { bannerOverlay }
            .sheet(isPresented: $showSheet, onDismiss: handleSheetDismiss) {
                if let prompt = activePrompt {
                    AmenSmartPromptSheet(
                        prompt: prompt,
                        onPrimaryAction:   { action in handlePrimary(action, prompt: prompt) },
                        onSecondaryAction: { action in handleSecondary(action, prompt: prompt) },
                        onDismiss:         { reason in dismiss(prompt: prompt, reason: reason) }
                    )
                }
            }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var cardOverlay: some View {
        if let prompt = activePrompt, prompt.presentation == .card {
            AmenSmartPromptCard(
                prompt: prompt,
                onPrimaryAction:   { action in handlePrimary(action, prompt: prompt) },
                onSecondaryAction: { action in handleSecondary(action, prompt: prompt) },
                onDismiss:         { reason in dismiss(prompt: prompt, reason: reason) }
            )
            .padding(.bottom, 24)
            .zIndex(900)
        }
    }

    @ViewBuilder
    private var bannerOverlay: some View {
        if let prompt = activePrompt, prompt.presentation == .banner {
            AmenSmartPromptBanner(
                prompt: prompt,
                onPrimaryAction: { action in handlePrimary(action, prompt: prompt) },
                onDismiss:       { reason in dismiss(prompt: prompt, reason: reason) }
            )
            .padding(.top, safeAreaTop + 8)
            .zIndex(900)
        }
    }

    // MARK: - Eligibility

    private func considerPrompt() async {
        guard activePrompt == nil else { return }
        let context = await contextProvider()
        guard let prompt = await engine.eligiblePrompt(surface: surface, context: context) else { return }
        await MainActor.run {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                activePrompt = prompt
                if prompt.presentation == .sheet { showSheet = true }
            }
            engine.recordImpression(prompt)
            scheduleAutoDismiss(for: prompt)
        }
    }

    // MARK: - Actions

    private func handlePrimary(_ action: AmenSmartPromptAction, prompt: AmenSmartPrompt) {
        engine.recordAction(action, for: prompt)
        switch action.route {
        case .requestNotificationPermission:
            requestNotifications(for: prompt)
        case .openAppSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            dismiss(prompt: prompt, reason: .userTappedSecondaryAction)
        case .requestLocationPermission, .requestCalendarPermission,
             .openSelah, .openQuietMode, .openBereanStudy,
             .openChurchDetail, .dismiss:
            dismiss(prompt: prompt, reason: .userTappedSecondaryAction)
        }
    }

    private func handleSecondary(_ action: AmenSmartPromptAction, prompt: AmenSmartPrompt) {
        engine.recordAction(action, for: prompt)
        dismiss(prompt: prompt, reason: .userTappedSecondaryAction)
    }

    private func dismiss(prompt: AmenSmartPrompt, reason: AmenSmartPromptDismissalReason) {
        autoDismissTask?.cancel()
        engine.recordDismissal(reason, for: prompt)
        withAnimation(.easeInOut(duration: 0.22)) {
            activePrompt = nil
            showSheet = false
        }
    }

    private func handleSheetDismiss() {
        if let prompt = activePrompt {
            engine.recordDismissal(.userSwipedAway, for: prompt)
            activePrompt = nil
        }
    }

    // MARK: - Permission

    private func requestNotifications(for prompt: AmenSmartPrompt) {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                await MainActor.run {
                    engine.recordPermissionResult(granted: granted, for: prompt)
                    dismiss(prompt: prompt, reason: .userTappedSecondaryAction)
                }
            } catch {
                await MainActor.run {
                    dismiss(prompt: prompt, reason: .userTappedSecondaryAction)
                }
            }
        }
    }

    // MARK: - Auto-dismiss

    private func scheduleAutoDismiss(for prompt: AmenSmartPrompt) {
        let delay: Double = prompt.presentation == .banner ? 6 : 0
        guard delay > 0 else { return }
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { dismiss(prompt: prompt, reason: .timedOut) }
        }
    }

    // MARK: - Helpers

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 0
    }
}
