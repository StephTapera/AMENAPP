import Foundation
import Testing
@testable import AMENAPP

struct LivingEntryModelTests {
    @Test("Living entry decodes with safe defaults when AI fields are absent")
    func decodeWithDefaults() throws {
        let json = """
        {
          "userId": "user-1",
          "type": "note",
          "intent": "unknown",
          "state": "active",
          "title": "Remember this",
          "body": "Body",
          "createdAt": 0,
          "updatedAt": 0,
          "scriptureRefs": [],
          "tags": [],
          "triggerRules": [],
          "contextSnapshot": {
            "localHour": 9,
            "dayOfWeek": 1,
            "isSunday": true,
            "isAtChurch": false,
            "quietModeActive": false,
            "focusModeActive": false,
            "sourceSurface": "home"
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entry = try decoder.decode(LivingEntry.self, from: Data(json.utf8))
        #expect(entry.priorityScore == 0)
        #expect(entry.gravityScore == 0)
        #expect(entry.evolutionVersion == 1)
    }
}
