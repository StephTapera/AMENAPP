//
//  ONERelayConsentTests.swift
//  AMENAPPTests
//
//  H-1 regression: a forward-prohibited Moment must be denied relay on the
//  client, fail-closed, BEFORE any network call. Server-side rejection in the
//  one_relayMoment callable remains P5-deferred and mandatory before the ONE
//  flag flips — client enforcement alone is advisory.
//

import Testing
import Foundation
@testable import AMENAPP

@MainActor
struct ONERelayConsentTests {

    private func forwardProhibitedItem(id: String = "m1") -> ONEFeedItemViewModel {
        ONEFeedItemViewModel(
            id: id,
            authorDisplayName: "Author",
            textBody: "body",
            provenance: .unknown,
            reachBudget: ONEReachBudget(
                momentID: id, originalAuthorUID: "a",
                sharesRemaining: 3, totalRelays: 0,
                chainDepth: 1, maxChainDepth: 5
            ),
            permissions: ONEMomentPermissions(forwardAllowed: false),
            momentType: .post,
            createdAt: Date(timeIntervalSince1970: 0),
            hasVideo: false
        )
    }

    /// The sticky-consent primitive reflects the forward flag exactly.
    @Test func isPermittedReflectsForwardFlag() {
        let denied  = ONEMomentPermissions(forwardAllowed: false)
        let allowed = ONEMomentPermissions(forwardAllowed: true)
        #expect(ONEStickyConsentService.shared.isPermitted(.forward, in: denied)  == false)
        #expect(ONEStickyConsentService.shared.isPermitted(.forward, in: allowed) == true)
    }

    /// forward-prohibited Moment → relay denied client-side, before any network,
    /// and the weekly relay budget is left untouched (proves fail-closed).
    @Test func forwardProhibitedMomentRelayDeniedClientSide() async {
        let service = ONEFeedModeService()
        let budgetBefore = service.userRelayBudget
        service.items = [forwardProhibitedItem()]

        await #expect(throws: ONEConsentError.forwardNotPermitted) {
            _ = try await service.relay(itemID: "m1")
        }
        #expect(service.userRelayBudget == budgetBefore)
    }
}
