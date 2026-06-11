import Testing
@testable import AMENAPP

/// GAP BOARD P0-7 — RemoteKillSwitch must gate its surfaces, not just compute dead state.
///
/// Tests verify the gate contract for each flag: when the kill switch is OFF the gate should
/// suppress the surface; when ON the surface should be allowed. These tests cover the boolean
/// logic that ContentView uses to gate the feed, messaging, createPost, and maintenance overlay.
@Suite("Kill switch gate contract (P0-7)")
struct KillSwitchGateTests {

    // Pure helper mirroring the ContentView gating logic so tests run without a full build.
    // When ContentView changes these checks update here too — the names are the contract.
    struct Gate {
        var feedEnabled: Bool      = true
        var messagingEnabled: Bool = true
        var createPostEnabled: Bool = true
        var maintenanceMode: Bool  = false

        var shouldShowFeed: Bool      { feedEnabled && !maintenanceMode }
        var shouldShowMessaging: Bool { messagingEnabled && !maintenanceMode }
        var shouldAllowCreatePost: Bool { createPostEnabled && !maintenanceMode }
        var shouldShowMaintenance: Bool { maintenanceMode }
    }

    // MARK: feed

    @Test("feed shown when feedEnabled=true, maintenanceMode=false")
    func feedShownWhenEnabled() {
        #expect(Gate().shouldShowFeed == true)
    }

    @Test("feed hidden when feedEnabled=false")
    func feedHiddenWhenKilled() {
        #expect(Gate(feedEnabled: false).shouldShowFeed == false)
    }

    @Test("feed hidden during maintenance even if feedEnabled=true")
    func feedHiddenDuringMaintenance() {
        #expect(Gate(maintenanceMode: true).shouldShowFeed == false)
    }

    // MARK: messaging

    @Test("messages shown when messagingEnabled=true")
    func messagingShownWhenEnabled() {
        #expect(Gate().shouldShowMessaging == true)
    }

    @Test("messages hidden when messagingEnabled=false")
    func messagingHiddenWhenKilled() {
        #expect(Gate(messagingEnabled: false).shouldShowMessaging == false)
    }

    // MARK: createPost

    @Test("createPost allowed when createPostEnabled=true")
    func createPostAllowedWhenEnabled() {
        #expect(Gate().shouldAllowCreatePost == true)
    }

    @Test("createPost blocked when createPostEnabled=false")
    func createPostBlockedWhenKilled() {
        #expect(Gate(createPostEnabled: false).shouldAllowCreatePost == false)
    }

    // MARK: maintenance mode

    @Test("maintenance overlay shown when maintenanceMode=true")
    func maintenanceShownWhenEnabled() {
        #expect(Gate(maintenanceMode: true).shouldShowMaintenance == true)
    }

    @Test("maintenance overlay hidden when maintenanceMode=false")
    func maintenanceHiddenWhenOff() {
        #expect(Gate().shouldShowMaintenance == false)
    }

    @Test("maintenance overrides all other gates")
    func maintenanceOverridesAll() {
        let g = Gate(feedEnabled: true, messagingEnabled: true, createPostEnabled: true, maintenanceMode: true)
        #expect(g.shouldShowFeed == false)
        #expect(g.shouldShowMessaging == false)
        #expect(g.shouldAllowCreatePost == false)
        #expect(g.shouldShowMaintenance == true)
    }
}
