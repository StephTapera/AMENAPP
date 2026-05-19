import Foundation
import Testing
@testable import AMENAPP

struct FindChurchLivingEntryBridgeTests {
    @Test("Next Sunday morning resolves to 8 AM on the next Sunday")
    @MainActor
    func nextSundayMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2025-05-05T12:00:00Z")!
        let result = FindChurchLivingEntryBridge.nextSundayMorning(from: now, calendar: calendar)
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: result)
        #expect(components.weekday == 1)
        #expect(components.hour == 8)
        #expect(components.minute == 0)
    }
}
