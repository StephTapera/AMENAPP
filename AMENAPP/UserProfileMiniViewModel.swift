//
//  UserProfileMiniViewModel.swift
//  AMENAPP
//
//  ObservableObject view model for UserProfileViewMini.
//  Manages follow state, expansion, action availability,
//  optimistic updates, rollback, toast feedback, and analytics.
//

import Foundation
import SwiftUI

@MainActor
final class UserProfileMiniViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var model: UserProfileMiniModel
    @Published private(set) var isFollowLoading = false
    @Published private(set) var isMessageLoading = false
    @Published private(set) var isExpanded = false
    @Published private(set) var isHidden = false
    @Published private(set) var toastMessage: String?

    // Derived context (computed once, stable)
    let primaryAction: UserMiniPrimaryAction
    let secondaryAction: UserMiniSecondaryAction
    let reasons: [UserMiniReason]
    let explanation: String
    let priorityExplanation: String
    let smartActions: [UserMiniOverflowAction]

    // MARK: - Private

    private let handler: UserProfileMiniActionHandler
    private let context: UserProfileMiniContextEngine
    private let position: Int?

    // MARK: - Init

    init(
        model: UserProfileMiniModel,
        handler: UserProfileMiniActionHandler,
        position: Int? = nil
    ) {
        self.model = model
        self.handler = handler
        self.position = position
        self.context = UserProfileMiniContextEngine()

        let snapshot = context.resolve(for: model)
        self.primaryAction = snapshot.primaryAction
        self.secondaryAction = snapshot.secondaryAction
        self.reasons = snapshot.reasons
        self.explanation = snapshot.explanation
        self.priorityExplanation = snapshot.priorityExplanation
        self.smartActions = snapshot.smartActions
    }

    // MARK: - Computed Helpers

    var isFollowed: Bool { model.isFollowed }
    var isSaved: Bool    { model.isSavedSuggestion }
    var canMessage: Bool {
        model.canMessage && !model.isBlocked && !model.isProfileUnavailable &&
        handler.messagingService.canMessage(userId: model.id)
    }

    var followButtonLabel: String {
        if isFollowLoading { return "" }
        return model.isFollowed ? "Following" : primaryAction.label
    }

    // MARK: - Actions

    func onTapFollow() {
        guard !isFollowLoading else { return }

        if model.isFollowed {
            // Optimistic unfollow
            model.isFollowed = false
            Task { await performUnfollow() }
        } else {
            // Optimistic follow
            model.isFollowed = true
            track(.followTap)
            Task { await performFollow() }
        }
    }

    func onTapMessage() {
        guard !isMessageLoading else { return }
        guard canMessage else {
            let message = model.isBlocked || model.isProfileUnavailable
                ? "This profile can’t be messaged right now."
                : "Messaging isn’t available for this suggestion right now."
            handler.routing.showMessagingUnavailable(reason: message)
            showToast(message)
            return
        }
        track(.messageTap)
        Task { await performMessage() }
    }

    func onTapProfile() {
        track(.profileOpen)
        handler.routing.openProfile(userId: model.id)
    }

    func onTapPrimaryAction() {
        track(.primaryCTATap)
        switch primaryAction {
        case .follow:
            onTapFollow()
        case .joinConversation:
            onTapProfile()
        case .prayTogether:
            onTapMessage()
        case .viewTestimony(let postId):
            if let postId {
                handler.routing.openPost(postId: postId)
            } else {
                onTapProfile()
            }
        }
    }

    func onTapSecondaryAction() {
        track(.secondaryCTATap)
        switch secondaryAction {
        case .message:      onTapMessage()
        case .viewProfile:  onTapProfile()
        case .saveForLater: onTapSaveForLater()
        }
    }

    func onTapOverflow() {
        track(.overflowTapped)
    }

    func onTapExpand() {
        track(.showMoreTapped)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isExpanded.toggle()
        }
    }

    func onTapSaveForLater() {
        track(.saveSuggestion)
        model.isSavedSuggestion = true
        showToast("Saved for later.")
    }

    func onTapHideSuggestion() {
        track(.hideSuggestion)
        withAnimation(.easeOut(duration: 0.25)) {
            isHidden = true
        }
        handler.onHide?(model.id)
    }

    func undoHide() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isHidden = false
        }
    }

    func onAppear() {
        track(.impression)
    }

    // MARK: - Private Async Work

    private func performFollow() async {
        isFollowLoading = true
        defer { isFollowLoading = false }
        do {
            try await handler.followService.follow(userId: model.id)
            track(.followSuccess)
        } catch {
            // Rollback on failure
            model.isFollowed = false
            track(.followFailure)
            showToast("Couldn't follow right now. Try again.")
            dlog("UserProfileMiniViewModel: follow failed for \(model.id): \(error)")
        }
    }

    private func performUnfollow() async {
        do {
            try await handler.followService.unfollow(userId: model.id)
        } catch {
            // Rollback
            model.isFollowed = true
            showToast("Couldn't unfollow. Try again.")
            dlog("UserProfileMiniViewModel: unfollow failed for \(model.id): \(error)")
        }
    }

    private func performMessage() async {
        isMessageLoading = true
        defer { isMessageLoading = false }
        do {
            try await handler.messagingService.openConversation(
                userId: model.id,
                displayName: model.displayName
            )
        } catch {
            showToast("Couldn't open a conversation right now.")
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            toastMessage = nil
        }
    }

    // MARK: - Analytics

    private func track(_ kind: UserMiniAnalyticsEvent.Kind, ctaType: String? = nil) {
        handler.analytics.track(UserMiniAnalyticsEvent(
            kind: kind,
            userId: model.id,
            source: model.suggestionSource,
            ctaType: ctaType,
            position: position,
            suggestionScore: model.suggestionScore
        ))
    }
}
