//
//  GroupLinkViewModel.swift
//  AMENAPP
//
//  Dedicated view model for group link flows.
//  Keeps logic out of MessagesView and service layer clean.
//

import Foundation
import SwiftUI

@MainActor
final class GroupLinkViewModel: ObservableObject {
    private let service = GroupLinkService.shared

    // MARK: - Creation Flow State

    @Published var config = CreateGroupLinkConfig()
    @Published var isCreating = false
    @Published var createdLink: GroupLink?
    @Published var createError: String?

    // MARK: - Join Flow State

    @Published var joinToken: String = ""
    @Published var preview: GroupLinkPreview?
    @Published var isLoadingPreview = false
    @Published var previewError: String?

    @Published var joinEvaluation: JoinEvaluationResult?
    @Published var isEvaluating = false
    @Published var isJoining = false
    @Published var isRequesting = false
    @Published var joinedConversationId: String?
    @Published var joinError: String?
    @Published var requestSubmitted = false

    // MARK: - Management State

    @Published var activeLink: GroupLink?
    @Published var pendingRequests: [GroupJoinRequest] = []
    @Published var isLoadingManagement = false
    @Published var managementError: String?
    @Published var isRegenerating = false

    // MARK: - Creation Flow

    func createGroupWithLink() async {
        guard !isCreating else { return }
        isCreating = true
        createError = nil

        // Apply smart defaults based on purpose
        config.applyPurposeDefaults()

        do {
            let link = try await service.createGroupWithLink(config: config)
            createdLink = link
            HapticManager.notification(type: .success)
        } catch {
            createError = error.localizedDescription
            HapticManager.notification(type: .error)
        }

        isCreating = false
    }

    // MARK: - Join Flow

    func loadPreview(token: String) async {
        joinToken = token
        isLoadingPreview = true
        previewError = nil

        do {
            preview = try await service.fetchLinkPreview(token: token)
        } catch {
            previewError = error.localizedDescription
        }

        isLoadingPreview = false
    }

    func evaluateJoin() async {
        guard !joinToken.isEmpty else { return }
        isEvaluating = true
        joinError = nil

        do {
            joinEvaluation = try await service.evaluateJoin(token: joinToken)
        } catch {
            joinError = error.localizedDescription
        }

        isEvaluating = false
    }

    func joinGroup() async {
        guard !joinToken.isEmpty else { return }
        isJoining = true
        joinError = nil

        do {
            let conversationId = try await service.joinGroup(token: joinToken)
            joinedConversationId = conversationId
            HapticManager.notification(type: .success)
        } catch {
            joinError = error.localizedDescription
            HapticManager.notification(type: .error)
        }

        isJoining = false
    }

    func requestToJoin() async {
        guard !joinToken.isEmpty else { return }
        isRequesting = true
        joinError = nil

        do {
            try await service.requestJoin(token: joinToken)
            requestSubmitted = true
            HapticManager.notification(type: .success)
        } catch {
            joinError = error.localizedDescription
            HapticManager.notification(type: .error)
        }

        isRequesting = false
    }

    // MARK: - Management Flow

    func loadManagementData(conversationId: String) async {
        isLoadingManagement = true
        managementError = nil

        do {
            async let linkResult = service.fetchActiveLink(conversationId: conversationId)
            async let requestsResult = service.fetchPendingRequests(conversationId: conversationId)
            activeLink = try await linkResult
            pendingRequests = try await requestsResult
        } catch {
            managementError = error.localizedDescription
        }

        isLoadingManagement = false
    }

    func pauseLink(conversationId: String) async {
        guard let linkId = activeLink?.id else { return }
        do {
            try await service.pauseLink(conversationId: conversationId, linkId: linkId)
            activeLink?.status = .paused
        } catch {
            managementError = error.localizedDescription
        }
    }

    func resumeLink(conversationId: String) async {
        guard let linkId = activeLink?.id else { return }
        do {
            try await service.resumeLink(conversationId: conversationId, linkId: linkId)
            activeLink?.status = .active
        } catch {
            managementError = error.localizedDescription
        }
    }

    func disableLink(conversationId: String) async {
        guard let linkId = activeLink?.id else { return }
        do {
            try await service.disableLink(conversationId: conversationId, linkId: linkId)
            activeLink?.status = .disabled
        } catch {
            managementError = error.localizedDescription
        }
    }

    func regenerateLink(conversationId: String) async {
        guard let oldLinkId = activeLink?.id else { return }
        isRegenerating = true
        do {
            let newLink = try await service.regenerateLink(conversationId: conversationId, oldLinkId: oldLinkId)
            activeLink = newLink
            HapticManager.notification(type: .success)
        } catch {
            managementError = error.localizedDescription
            HapticManager.notification(type: .error)
        }
        isRegenerating = false
    }

    func respondToRequest(conversationId: String, requestId: String, approve: Bool) async {
        do {
            try await service.respondToJoinRequest(
                conversationId: conversationId,
                requestId: requestId,
                approve: approve
            )
            pendingRequests.removeAll { $0.id == requestId }
            HapticManager.notification(type: .success)
        } catch {
            managementError = error.localizedDescription
        }
    }

    // MARK: - Reset

    func resetCreateFlow() {
        config = CreateGroupLinkConfig()
        isCreating = false
        createdLink = nil
        createError = nil
    }

    func resetJoinFlow() {
        joinToken = ""
        preview = nil
        isLoadingPreview = false
        previewError = nil
        joinEvaluation = nil
        isEvaluating = false
        isJoining = false
        isRequesting = false
        joinedConversationId = nil
        joinError = nil
        requestSubmitted = false
    }
}
