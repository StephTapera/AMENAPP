import XCTest

final class PaymentsUITests: XCTestCase {
    func testPaymentsPurchaseRestoreManageAndEntitlementRefresh() {
        let app = launchReleaseHarness()

        XCTAssertTrue(app.staticTexts["$9.99 per month"].exists)
        tap("Open Paywall", in: app)
        tap("Start Purchase", in: app)
        tap("Cancel Purchase", in: app)
        tap("Complete Sandbox Purchase", in: app)
        XCTAssertTrue(app.staticTexts["Premium entitlement active"].waitForExistence(timeout: 2))
        tap("Restore Purchases", in: app)
        tap("Manage Subscription", in: app)

        assertEvent("paywallShown", in: app)
        assertEvent("purchaseStarted", in: app)
        assertEvent("purchaseCanceled", in: app)
        assertEvent("purchaseSucceeded", in: app)
        assertEvent("restoreStarted", in: app)
        assertEvent("restoreSucceeded", in: app)
        assertEvent("entitlementRefreshed", in: app)
        assertEvent("manageSubscriptionOpened", in: app)
    }
}
