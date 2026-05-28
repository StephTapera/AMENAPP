// CrossCommunityViewModel.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// @MainActor ViewModel that drives all cross-community UI surfaces:
//   - LinkInviteSheet (manage linked communities, send/revoke)
//   - LinkInviteInboxView (accept/decline incoming invites)
//   - SpaceDetailView (sharedWith live stream → banner update + revoked banner)
//
// No Combine — async/await + AsyncStream only.

import SwiftUI
import FirebaseAuth

@MainActor
final class CrossCommunityViewModel: ObservableObject {

    // MARK: - Published state

    @Published var linkedCommunities: [LinkedCommunityRecord] = []
    @Published var incomingInvites: [CommunityLinkRecord] = []
    @Published var outgoingInvites: [CommunityLinkRecord] = []
    @Published var searchResults: [SpacesCommunity] = []
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var error: Error? = nil
    @Published var showRevokedBanner: Bool = false

    // MARK: - Private state

    private var streamTask: Task<Void, Never>? = nil
    private let service = CrossCommunityLinkService.shared

    // MARK: - Init / deinit

    init() {}

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Load initial data

    /// Loads linked communities, outgoing invites, and incoming invites for a Space.
    func loadForSpace(spaceId: String, communityId: String) async {
        isLoading = true
        error = nil
        do {
            async let linked  = service.fetchLinkedCommunities(spaceId: spaceId)
            async let outgoing = service.fetchOutgoingInvites(communityId: communityId)
            async let incoming = service.fetchIncomingInvites(communityId: communityId)
            let (l, o, i) = try await (linked, outgoing, incoming)
            linkedCommunities = l
            outgoingInvites   = o
            incomingInvites   = i
        } catch {
            self.error = error
        }
        isLoading = false
    }

    /// Loads only incoming invites for the community inbox screen.
    func loadIncomingInvites(communityId: String) async {
        isLoading = true
        error = nil
        do {
            incomingInvites = try await service.fetchIncomingInvites(communityId: communityId)
        } catch {
            self.error = error
        }
        isLoading = false
    }

    // MARK: - Send invite

    func sendInvite(
        toCommunityId: String,
        fromCommunityId: String,
        spaceId: String,
        scope: String
    ) async {
        isSending = true
        error = nil
        do {
            try await service.sendLinkInvite(
                fromCommunityId: fromCommunityId,
                toCommunityId: toCommunityId,
                spaceId: spaceId,
                scope: scope
            )
            // Refresh outgoing after sending.
            outgoingInvites = try await service.fetchOutgoingInvites(communityId: fromCommunityId)
        } catch {
            self.error = error
        }
        isSending = false
    }

    // MARK: - Accept invite

    func acceptInvite(link: CommunityLinkRecord, spaceId: String) async {
        error = nil
        do {
            try await service.acceptLink(
                linkId: link.id,
                inCommunityId: link.toCommunityId,
                spaceId: spaceId
            )
            withAnimation(Motion.liquidSpring) {
                incomingInvites.removeAll { $0.id == link.id }
            }
            // Refresh linked communities list.
            linkedCommunities = try await service.fetchLinkedCommunities(spaceId: spaceId)
        } catch {
            self.error = error
        }
    }

    // MARK: - Decline invite

    func declineInvite(link: CommunityLinkRecord) async {
        error = nil
        do {
            try await service.declineLink(
                linkId: link.id,
                inCommunityId: link.toCommunityId
            )
            withAnimation(Motion.liquidSpring) {
                incomingInvites.removeAll { $0.id == link.id }
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Revoke link

    func revokeLink(link: LinkedCommunityRecord, spaceId: String, communityId: String) async {
        error = nil
        do {
            try await service.revokeLink(
                linkId: link.linkId,
                inCommunityId: communityId,
                spaceId: spaceId
            )
            withAnimation(Motion.liquidSpring) {
                linkedCommunities.removeAll { $0.id == link.id }
                outgoingInvites.removeAll { $0.id == link.linkId }
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Community search

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try await service.searchCommunities(query: query)
        } catch {
            searchResults = []
        }
    }

    // MARK: - Real-time listener for sharedWith

    /// Starts a live stream that updates linkedCommunities whenever the Space's
    /// sharedWith array changes. Also triggers the revoked banner if a previously
    /// active community is removed while the user is mid-session.
    func startListening(spaceId: String) {
        streamTask?.cancel()
        streamTask = Task {
            for await records in service.streamLinkedCommunities(spaceId: spaceId) {
                guard !Task.isCancelled else { break }
                // If we previously had records and now have fewer, show revoked banner.
                let previousIds = Set(linkedCommunities.map(\.id))
                let currentIds  = Set(records.map(\.id))
                let wasRevoked  = !previousIds.isEmpty && previousIds != currentIds
                    && currentIds.isSubset(of: previousIds)
                withAnimation(Motion.liquidSpring) {
                    linkedCommunities = records
                    if wasRevoked { showRevokedBanner = true }
                }
            }
        }
    }

    func stopListening() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Dismiss revoked banner

    func dismissRevokedBanner() {
        withAnimation(Motion.liquidSpring) {
            showRevokedBanner = false
        }
    }
}
