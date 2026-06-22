// SmartHeaderOrchestrator.swift
// Smart Header Orchestrator — Main orchestrating view
//
// Drop this into any screen that opts in. It has ZERO effect on screens that
// don't include it. It never modifies any existing view.
//
// Usage:
//   SmartHeaderOrchestrator(
//       screenType: .feed,
//       userName: profile.displayName,
//       intentMode: selectedIntentMode,
//       scrollOffset: scrollOffset,
//       hasVerseReady: verseService.todayVerse != nil
//   )

import SwiftUI

struct SmartHeaderOrchestrator: View {
    // Inputs from host screen
    let screenType:    ScreenType
    let userName:      String
    let intentMode:    FeedIntentMode?
    let scrollOffset:  CGFloat
    let hasVerseReady: Bool

    @StateObject private var provider = HeaderContextProvider()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if TopChromeFeatureFlags.smartHeaderEnabled {
                orchestratedContent
            }
            // Feature off → renders nothing; existing banners on the host screen
            // continue to work exactly as before.
        }
        .onAppear {
            provider.refresh(
                screenType: screenType,
                intentMode: intentMode,
                scrollOffset: scrollOffset,
                userName: userName,
                hasVerseReady: hasVerseReady
            )
        }
        .onChange(of: scrollOffset) { _, newOffset in
            provider.refresh(
                screenType: screenType,
                intentMode: intentMode,
                scrollOffset: newOffset,
                userName: userName,
                hasVerseReady: hasVerseReady
            )
        }
        .onChange(of: intentMode) { _, newMode in
            provider.refresh(
                screenType: screenType,
                intentMode: newMode,
                scrollOffset: scrollOffset,
                userName: userName,
                hasVerseReady: hasVerseReady
            )
        }
    }

    // MARK: - Orchestrated Rendering

    @ViewBuilder
    private var orchestratedContent: some View {
        let variant = TopChromeDecisionEngine.decide(context: provider.context)
        let verseStyle = DailyVersePresentationEngine.style(context: provider.context)

        switch variant {
        case .hidden:
            EmptyView()

        case .compact(let text):
            CompactTopChromeView(
                greeting: text,
                accentColor: DailyVersePresentationEngine.accentColor(context: provider.context)
            )
            .transition(TopChromeAnimator.fadeSlide)
            .animation(TopChromeAnimator.animation(reducedMotion: reduceMotion), value: variant.id)

        case .greetingOnly:
            TopChromeFlushContainer {
                GreetingHeaderView(context: provider.context)
            }
            .transition(TopChromeAnimator.expandTransition)
            .animation(TopChromeAnimator.animation(reducedMotion: reduceMotion), value: variant.id)

        case .verseOnly:
            // Pass-through — the existing AIDailyVerseCard on the host screen handles this
            EmptyView()

        case .greetingAndVerse:
            TopChromeFlushContainer {
                GreetingHeaderView(context: provider.context)

                if hasVerseReady {
                    Divider().padding(.horizontal, TopChromeMetrics.containerPadding)

                    SmartVerseBannerBridgeView(
                        context: provider.context,
                        style: verseStyle,
                        onShown: { provider.markVerseShown() }
                    )
                }
            }
            .transition(TopChromeAnimator.expandTransition)
            .animation(TopChromeAnimator.animation(reducedMotion: reduceMotion), value: variant.id)
        }
    }
}

// MARK: - TopChromeVariant Equatable id for animation

extension TopChromeVariant {
    var id: String {
        switch self {
        case .greetingOnly:       return "greetingOnly"
        case .verseOnly:          return "verseOnly"
        case .greetingAndVerse:   return "greetingAndVerse"
        case .compact(let t):     return "compact_\(t)"
        case .hidden:             return "hidden"
        }
    }
}

// MARK: - Screen Policy (opt-in per screen)

struct ScreenTopChromePolicy {
    /// True = this screen participates in orchestration
    static func isEnabled(for screen: ScreenType) -> Bool {
        switch screen {
        case .feed, .church, .resources: return TopChromeFeatureFlags.smartHeaderEnabled
        default: return false
        }
    }
}
