import Testing
import Foundation
@testable import AMENAPP

@MainActor
struct AmenContextualExperienceResolverTests {
    @Test func draftPayloadContainsServerRequiredFields() async throws {
        var draft = AmenExperienceDraft()
        draft.title = "21-Day Fast"
        draft.description = "A church-wide prayer and fasting campaign."
        draft.organizationId = "org_123"
        draft.organizationType = .church
        draft.experienceType = .fastingCampaign
        draft.visibility = .members

        let payload = draft.payload

        #expect(payload["title"] as? String == "21-Day Fast")
        #expect(payload["organizationId"] as? String == "org_123")
        #expect(payload["organizationType"] as? String == "church")
        #expect(payload["experienceType"] as? String == "fastingCampaign")
        #expect(payload["visibility"] as? String == "members")
        #expect(payload["theme"] != nil)
        #expect(payload["notificationRules"] != nil)
        #expect(payload["safetyRules"] != nil)
    }

    @Test func rawExperienceParsesVisibilityAndSafety() async throws {
        let raw: [String: Any] = [
            "id": "exp_1",
            "title": "Graduation Blessing Week",
            "description": "A school celebration with prayer prompts.",
            "organizationId": "school_1",
            "organizationType": "school",
            "region": "US-AZ",
            "sourceLayer": "organization",
            "experienceType": "graduation",
            "visibility": "members",
            "status": "published",
            "startAt": Date().timeIntervalSince1970 * 1000,
            "endAt": Date().addingTimeInterval(86400).timeIntervalSince1970 * 1000,
            "safetyRules": [
                "griefSensitive": false,
                "youthProtected": true,
                "privatePrayerDefault": true,
                "requireModeration": true,
                "killSwitch": false
            ]
        ]

        let experience = try #require(AmenContextualExperience.from(raw, canManage: true))

        #expect(experience.organizationType == .school)
        #expect(experience.experienceType == .graduation)
        #expect(experience.visibility == .members)
        #expect(experience.safetyRules.youthProtected)
        #expect(experience.canManage)
    }
}
