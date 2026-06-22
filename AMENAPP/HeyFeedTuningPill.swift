//
//  HeyFeedTuningPill.swift
//  AMENAPP
//
//  Subtle floating pill that appears in the feed to invite feed tuning.
//  Contextually appears after scroll pauses, repeated skips, or saturation.
//  Separate from HeyFeedPostCardBadge (which is per-post resonance).
//

import SwiftUI

struct HeyFeedTuningPill: View {
    @StateObject private var sessionSvc = HeyFeedSessionModeService.shared
    @StateObject private var nlService  = HeyFeedNLPreferencesService.shared
    @Binding var isVisible: Bool
    @State private var showSheet = false
    @State private var label: String = "Tune feed"
    @State private var hasAppeared = false

    var body: some View {
        Group {
            if isVisible {
                pill
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .onAppear {
                        if !hasAppeared {
                            hasAppeared = true
                            label = computeLabel()
                        }
                    }
            }
        }
        .animation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.72)), value: isVisible)
        .sheet(isPresented: $showSheet) {
            HeyFeedNLInputView()
        }
    }

    private var pill: some View {
        Button {
            showSheet = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                // Active mode indicator
                if sessionSvc.isActive {
                    Image(systemName: sessionSvc.activeMode.icon)
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(sessionSvc.isActive ? sessionSvc.activeMode.label : label)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.primary)

                // Active preference count badge
                if !nlService.activePreferences.filter({ !$0.isExpired }).isEmpty {
                    Text("\(nlService.activePreferences.filter { !$0.isExpired }.count)")
                        .font(AMENFont.bold(10))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(Color.primary))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.thinMaterial)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: Color.primary.opacity(0.06), radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private func computeLabel() -> String {
        let count = nlService.activePreferences.filter { !$0.isExpired }.count
        if count > 0 { return "Feed tuned · \(count)" }
        return "Tune feed"
    }
}

// MARK: - Trigger Logic

/// ViewModel that controls when the tuning pill should appear.
@MainActor
final class HeyFeedTuningPillController: ObservableObject {

    @Published var pillVisible = false

    private var consecutiveSkips = 0
    private var lastSkipTopics: [String] = []
    private var hideTimer: Task<Void, Never>?

    /// Call when user quickly skips/scrolls past a post.
    func recordSkip(topicHints: [String] = []) {
        consecutiveSkips += 1
        lastSkipTopics.append(contentsOf: topicHints)

        // Show pill after 3+ consecutive skips
        if consecutiveSkips >= 3 {
            showPill()
        }
    }

    /// Call when user engages meaningfully (stops scrolling, taps, saves).
    func recordEngagement() {
        consecutiveSkips = 0
        lastSkipTopics = []
        hidePill()
    }

    func showPill() {
        hideTimer?.cancel()
        withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.72))) {
            pillVisible = true
        }
        // Auto-hide after 8 seconds
        hideTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hidePill()
        }
    }

    func hidePill() {
        withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78))) {
            pillVisible = false
        }
    }
}
