import Testing
@testable import AMENAPP

@Suite("Amen Connect")
struct AmenConnectTests {
    @Test("Amen Connect rooms are internal and do not model a global tab bar")
    func roomSwitcherIsInternalOnly() {
        let rooms = AmenConnectRoom.allCases.map(\.rawValue)

        #expect(rooms.contains("Lobby"))
        #expect(rooms.contains("Marketplace"))
        #expect(!rooms.contains("Home"))
        #expect(!rooms.contains("Resources"))
    }

    @Test("AI cannot use excluded content")
    func aiExclusionBoundary() {
        let service = AmenConnectService()

        let allowed = service.canAIUseContent(
            userRole: .owner,
            visibility: .publicToSpace,
            isAIExcluded: true,
            requiredTierId: nil,
            userTierIds: []
        )

        #expect(allowed == false)
    }

    @Test("AI does not summarize paid content for unpaid users")
    func aiPaidContentBoundary() {
        let service = AmenConnectService()

        let allowed = service.canAIUseContent(
            userRole: .member,
            visibility: .paidTier,
            isAIExcluded: false,
            requiredTierId: "mentor-circle",
            userTierIds: []
        )

        #expect(allowed == false)
    }

    @Test("Paid tier grants access only when server-authoritative tier id is present")
    func paidTierAccess() {
        let service = AmenConnectService()

        #expect(service.canAccessPaidContent(userTierIds: [], requiredTierId: "mentor-circle") == false)
        #expect(service.canAccessPaidContent(userTierIds: ["mentor-circle"], requiredTierId: "mentor-circle") == true)
    }

    @Test("Private and confidential AI access requires elevated role")
    func confidentialAIRequiresElevatedRole() {
        let service = AmenConnectService()

        #expect(service.canAIUseContent(userRole: .member, visibility: .confidential, isAIExcluded: false, requiredTierId: nil, userTierIds: []) == false)
        #expect(service.canAIUseContent(userRole: .admin, visibility: .confidential, isAIExcluded: false, requiredTierId: nil, userTierIds: []) == true)
    }

    @Test("Backend contracts include marketplace, creator economy, and monetization safety")
    func backendContractsCoverRequestedAreas() {
        let names = Set(AmenConnectService.contracts.map(\.functionName))

        #expect(names.contains("createConnectSpace"))
        #expect(names.contains("createMarketplaceListing"))
        #expect(names.contains("createConnectCreatorProfile"))
        #expect(names.contains("subscribeToConnectTier"))
        #expect(names.contains("moderateConnectMonetizedOffer"))
    }
}
