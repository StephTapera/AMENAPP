import XCTest
@testable import AMENAPP

final class NotificationContractTests: XCTestCase {

    func testCanonicalNotificationDecodesWithRecipientIdAndCanonicalType() throws {
        let json = """
        {
            "recipientId": "user_123",
            "type": "prayer_supported",
            "category": "prayer",
            "priorityBucket": "P1",
            "priorityScore": 87,
            "groupKey": "prayer:prayer_123:engagement",
            "title": "Sarah supported your prayer request.",
            "subtitle": "2 prayed",
            "previewText": "Your prayer request received support.",
            "privacyLevel": "protected",
            "prayerId": "prayer_123",
            "createdAt": { "seconds": 1735689600, "nanoseconds": 0 },
            "lastEventAt": { "seconds": 1735689600, "nanoseconds": 0 },
            "routePayload": { "prayerId": "prayer_123" },
            "targetRouteType": "prayer",
            "sourceEventIds": ["event_1"]
        }
        """

        let notification = try decodeNotification(json)

        XCTAssertEqual(notification.userId, "user_123")
        XCTAssertEqual(notification.type, .prayerSupported)
        XCTAssertEqual(notification.category, .prayer)
        XCTAssertEqual(notification.priorityBucket, .p1)
        XCTAssertEqual(notification.groupKey, "prayer:prayer_123:engagement")
        XCTAssertEqual(notification.targetRouteType, "prayer")
        XCTAssertEqual(notification.routePayload?["prayerId"], "prayer_123")
    }

    func testUnknownTypeFallsBackSafelyWithoutLosingRawValue() throws {
        let json = """
        {
            "recipientId": "user_123",
            "type": "brand_new_type",
            "createdAt": { "seconds": 1735689600, "nanoseconds": 0 }
        }
        """

        let notification = try decodeNotification(json)

        XCTAssertEqual(notification.type, .unknown)
        XCTAssertEqual(notification.rawTypeValue, "brand_new_type")
        XCTAssertEqual(NotificationRouteResolver.resolve(notification), .fallback)
    }

    func testLegacySnakeCaseOpenBehaviorDecodes() {
        let userInfo: [AnyHashable: Any] = [
            "schemaVersion": "3",
            "notificationId": "notif_1",
            "type": "comment_on_post",
            "targetRouteType": "post_comment",
            "routePayload": "{\"postId\":\"post_1\",\"commentId\":\"comment_1\"}",
            "openBehavior": "guarded_open"
        ]

        let intent = NotificationIntentDecoder.decode(userInfo: userInfo, source: .pushTap)

        XCTAssertEqual(intent?.behavior, .guardedOpen)
    }

    func testServerRouteResolvesChurchPage() {
        let route = NotificationRouteResolver.resolveFromServerRoute(
            type: "church_page",
            payload: ["churchId": "church_1"]
        )

        XCTAssertEqual(route, .churchPage(churchID: "church_1"))
    }

    func testNotificationStateSeparatesSeenFromRead() throws {
        var notification = try decodeNotification("""
        {
            "recipientId": "user_123",
            "type": "comment_on_post",
            "createdAt": { "seconds": 1735689600, "nanoseconds": 0 }
        }
        """)

        notification.seenAt = Timestamp(date: .now)

        XCTAssertEqual(notification.notificationState, .seen)
        XCTAssertFalse(notification.read)
        XCTAssertNil(notification.readAt)
    }

    private func decodeNotification(_ json: String) throws -> AppNotification {
        try JSONDecoder().decode(AppNotification.self, from: Data(json.utf8))
    }
}
