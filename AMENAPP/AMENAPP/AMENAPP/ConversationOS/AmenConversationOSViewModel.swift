// AmenConversationOSViewModel.swift
// AMEN Conversation OS — ViewModel
//
// Manages all Conversation OS state for a given space/thread.
// Feature-flag-gated. Sensitive spaces block AI by default.
// Non-blocking errors for background intelligence (clusters, actions).

import Foundation
import SwiftUI

@MainActor
final class AmenConversationOSViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var loadState: ConversationOSLoadState = .idle
    @Published private(set) var summary: ConversationSummary?
    @Published private(set) var topicClusters: [ConversationTopicCluster] = []
    @Published private(set) var actionItems: [ConversationActionItem] = []
    @Published private(set) var unresolvedQuestions: [ConversationUnresolvedQuestion] = []
    @Published private(set) var decisions: [ConversationDecision] = []
    @Published private(set) var blockers: [ConversationBlocker] = []
    @Published private(set) var organizationalMemory: ConversationOrganizationalMemory?
    @Published var showingCatchUp = false
    @Published var showingOrgMemory = false
    @Published var selectedCluster: ConversationTopicCluster?
    @Published var errorMessage: String?

    // MARK: - Context

    let spaceId: String
    let surface: ConversationOSSurface
    let userRole: ConversationOSUserRole
    let orgType: ConversationOSOrgType
    let orgId: String?

    // MARK: - Dependencies

    private let service = AmenConversationOSService.shared
    private let flags = AMENFeatureFlags.shared

    // MARK: - Init

    init(
        spaceId: String,
        surface: ConversationOSSurface,
        userRole: ConversationOSUserRole = .groupMember,
        orgType: ConversationOSOrgType = .church,
        orgId: String? = nil
    ) {
        self.spaceId = spaceId
        self.surface = surface
        self.userRole = userRole
        self.orgType = orgType
        self.orgId = orgId
    }

    // MARK: - Sensitive Space Guard

    private var isBlockedBySensitivePolicy: Bool {
        surface.isSensitive && flags.conversationOSSensitiveSpaceRestrictionsEnabled
    }

    // MARK: - Catch-Up Recap

    func loadCatchUpRecap(unreadCount: Int, lastVisitedAt: Date?) async {
        guard flags.conversationOSEnabled, flags.catchUpRecapsEnabled else { return }
        if isBlockedBySensitivePolicy {
            loadState = .sensitiveSpaceBlocked
            return
        }
        loadState = .loading
        do {
            let result = try await service.generateCatchUpRecap(
                spaceId: spaceId, surface: surface,
                unreadCount: unreadCount, lastVisitedAt: lastVisitedAt
            )
            apply(summary: result)
            loadState = .loaded
        } catch ConversationOSError.featureDisabled {
            loadState = .idle
        } catch ConversationOSError.sensitiveSpaceBlocked {
            loadState = .sensitiveSpaceBlocked
        } catch {
            errorMessage = error.localizedDescription
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Topic Clustering (non-blocking)

    func loadTopicClusters(threadId: String? = nil) async {
        guard flags.conversationOSEnabled, flags.topicClusteringEnabled else { return }
        guard !isBlockedBySensitivePolicy else { return }
        do {
            topicClusters = try await service.generateTopicClusters(
                spaceId: spaceId, threadId: threadId, surface: surface
            )
        } catch {
            // Non-blocking — topic clustering is ambient intelligence
        }
    }

    // MARK: - Action Extraction (non-blocking)

    func loadActionItems(threadId: String) async {
        guard flags.conversationOSEnabled, flags.actionExtractionEnabled else { return }
        guard !isBlockedBySensitivePolicy else { return }
        do {
            let extracted = try await service.extractActionItems(threadId: threadId, spaceId: spaceId)
            actionItems = extracted
        } catch {
            // Non-blocking
        }
    }

    // MARK: - Personalized Summary

    func loadPersonalizedSummary(
        unreadCount: Int,
        lastVisitedAt: Date?,
        followedTopics: [String]
    ) async {
        guard flags.conversationOSEnabled, flags.personalizedInsightsEnabled else { return }
        if isBlockedBySensitivePolicy {
            loadState = .sensitiveSpaceBlocked
            return
        }
        loadState = .loading
        let request = PersonalizedSummaryRequest(
            spaceId: spaceId,
            surface: surface,
            userRole: userRole,
            orgType: orgType,
            unreadCount: unreadCount,
            lastVisitedAt: lastVisitedAt,
            followedTopics: followedTopics,
            preferredLength: .balanced
        )
        do {
            let result = try await service.getPersonalizedSummary(request: request)
            apply(summary: result)
            loadState = .loaded
        } catch {
            errorMessage = error.localizedDescription
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Organizational Memory (non-blocking)

    func loadOrgMemory(query: String = "What changed this week?") async {
        guard flags.conversationOSEnabled, flags.organizationalMemoryEnabled else { return }
        guard let orgId else { return }
        do {
            organizationalMemory = try await service.queryOrganizationalMemory(orgId: orgId, query: query)
        } catch {
            // Non-blocking
        }
    }

    // MARK: - Action Mutations

    func markActionResolved(_ action: ConversationActionItem) async {
        updateAction(action, status: .resolved)
        try? await service.updateActionStatus(actionId: action.id, status: .resolved, spaceId: spaceId)
    }

    func dismissAction(_ action: ConversationActionItem) async {
        actionItems.removeAll { $0.id == action.id }
        try? await service.updateActionStatus(actionId: action.id, status: .dismissed, spaceId: spaceId)
    }

    func confirmDecision(_ decision: ConversationDecision) async {
        updateDecision(decision, status: .confirmed)
        try? await service.confirmDecision(decisionId: decision.id, spaceId: spaceId)
    }

    func challengeDecision(_ decision: ConversationDecision) async {
        updateDecision(decision, status: .challenged)
        try? await service.challengeDecision(decisionId: decision.id, spaceId: spaceId)
    }

    func dismissSummary() async {
        guard let summaryId = summary?.id else { return }
        summary = nil
        loadState = .idle
        try? await service.dismissSummary(summaryId: summaryId, spaceId: spaceId)
    }

    func dismissQuestion(_ question: ConversationUnresolvedQuestion) {
        unresolvedQuestions.removeAll { $0.id == question.id }
    }

    func selectCluster(_ cluster: ConversationTopicCluster) {
        selectedCluster = cluster
    }

    // MARK: - Computed Helpers

    var hasAnyIntelligence: Bool {
        summary != nil || !topicClusters.isEmpty || !actionItems.isEmpty
    }

    var pendingActionCount: Int {
        actionItems.filter { $0.status == .pending }.count
    }

    var pendingDecisionCount: Int {
        decisions.filter { $0.status == .proposed }.count
    }

    var unresolvedCount: Int { unresolvedQuestions.filter { !$0.dismissed }.count }

    // MARK: - Private Helpers

    private func apply(summary: ConversationSummary) {
        self.summary = summary
        unresolvedQuestions = summary.unresolvedQuestions
        decisions = summary.decisions
        actionItems = summary.actionItems
        blockers = summary.blockers
    }

    private func updateAction(_ action: ConversationActionItem, status: ConversationActionStatus) {
        guard let idx = actionItems.firstIndex(where: { $0.id == action.id }) else { return }
        actionItems[idx] = ConversationActionItem(
            id: action.id, title: action.title, description: action.description,
            assigneeId: action.assigneeId, assigneeDisplayName: action.assigneeDisplayName,
            dueDate: action.dueDate, sourceMessageId: action.sourceMessageId,
            threadId: action.threadId, status: status,
            createdAt: action.createdAt, confidence: action.confidence
        )
    }

    private func updateDecision(_ decision: ConversationDecision, status: ConversationDecisionStatus) {
        guard let idx = decisions.firstIndex(where: { $0.id == decision.id }) else { return }
        decisions[idx] = ConversationDecision(
            id: decision.id, summary: decision.summary, sourceSnippet: decision.sourceSnippet,
            participants: decision.participants, confirmedBy: decision.confirmedBy,
            status: status, threadId: decision.threadId,
            createdAt: decision.createdAt, confidence: decision.confidence
        )
    }
}
