// BereanOnboardingViewModel.swift
// AMENAPP — Berean Onboarding V3
// Business logic for step state, resume, analytics, persistence, and chat handoff.

import SwiftUI

@MainActor
final class BereanOnboardingViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentStep: BereanOnboardingStep = .introduction
    @Published private(set) var selectedFocuses: Set<BereanFocus> = []
    @Published private(set) var isCompleting = false

    // MARK: - Dependencies

    private let persistence: BereanOnboardingPersisting
    private let analytics: BereanOnboardingAnalyticsTracking
    private let source: String
    let content: BereanOnboardingContent
    let onComplete: (Set<BereanFocus>, BereanStarterContext) -> Void

    // MARK: - Lifecycle

    init(
        persistence: BereanOnboardingPersisting,
        analytics: BereanOnboardingAnalyticsTracking,
        contentProvider: BereanOnboardingContentProviding,
        source: String,
        onComplete: @escaping (Set<BereanFocus>, BereanStarterContext) -> Void
    ) {
        self.persistence = persistence
        self.analytics = analytics
        self.content = contentProvider.content
        self.source = source
        self.onComplete = onComplete
        restoreState()
        analytics.trackViewed(source: source)
        analytics.trackStepViewed(currentStep, selectedFocuses: selectedFocuses, source: source)
    }

    convenience init(onComplete: @escaping (Set<BereanFocus>, BereanStarterContext) -> Void) {
        self.init(
            persistence: BereanOnboardingUserDefaultsPersistence(),
            analytics: BereanOnboardingDefaultAnalytics(),
            contentProvider: BereanDefaultOnboardingContentProvider(),
            source: "berean_onboarding",
            onComplete: onComplete
        )
    }

    // MARK: - Computed

    var canGoBack: Bool { !currentStep.isFirst && !isCompleting }
    var isOnLastStep: Bool { currentStep.isLast }
    var ctaTitle: String { currentStep.isLast ? content.ctaStartChat : content.ctaContinue }
    var starterContext: BereanStarterContext { BereanStarterContext.derive(from: selectedFocuses) }

    // MARK: - Navigation

    func continueTapped() {
        guard !isCompleting else { return }
        analytics.trackContinueTapped(from: currentStep, selectedFocuses: selectedFocuses, source: source)

        if currentStep.isLast {
            complete(mode: .completed)
        } else if let nextStep = currentStep.next {
            transition(to: nextStep)
        }
    }

    func backTapped() {
        guard let previousStep = currentStep.previous, canGoBack else { return }
        analytics.trackBackTapped(from: currentStep, selectedFocuses: selectedFocuses, source: source)
        transition(to: previousStep)
    }

    func skipTapped() {
        guard !currentStep.isLast, !isCompleting else { return }
        analytics.trackSkipTapped(from: currentStep, selectedFocuses: selectedFocuses, source: source)
        transition(to: .ready)
    }

    func toggleFocus(_ focus: BereanFocus) {
        guard !isCompleting else { return }

        if selectedFocuses.contains(focus) {
            selectedFocuses.remove(focus)
            analytics.trackFocusDeselected(focus, selectedFocuses: selectedFocuses, step: currentStep, source: source)
        } else {
            selectedFocuses.insert(focus)
            analytics.trackFocusSelected(focus, selectedFocuses: selectedFocuses, step: currentStep, source: source)
        }

        persistence.saveSelectedFocuses(selectedFocuses)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Testing

    func resetForTesting() {
        persistence.reset()
        currentStep = .introduction
        selectedFocuses = []
        isCompleting = false
    }

    // MARK: - Private

    private func restoreState() {
        let state = persistence.loadState()
        selectedFocuses = state.selectedFocuses
        currentStep = state.hasCompletedBereanOnboarding ? .introduction : state.lastViewedStep
    }

    private func transition(to step: BereanOnboardingStep) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            currentStep = step
        }

        persistence.saveLastViewedStep(step)
        analytics.trackStepViewed(step, selectedFocuses: selectedFocuses, source: source)
    }

    private func complete(mode: BereanOnboardingCompletionMode) {
        guard !isCompleting else { return }
        isCompleting = true

        persistence.markCompleted(mode: mode, focuses: selectedFocuses)
        analytics.trackCompleted(mode: mode, focuses: selectedFocuses, source: source)
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let context = starterContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [selectedFocuses, onComplete] in
            onComplete(selectedFocuses, context)
        }
    }
}
