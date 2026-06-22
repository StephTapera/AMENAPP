import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("AMEN Settings System")
@MainActor
struct AmenSettingsSystemTests {
    @Test("Search finds expected settings by common keywords")
    func searchFindsExpectedSettings() {
        let service = SettingsSearchService()

        service.search("private")
        #expect(service.results.contains { $0.section == .privacy })

        service.search("AI")
        #expect(service.results.contains { $0.section == .bereanAI })

        service.search("cache")
        #expect(service.results.contains { $0.section == .storageData })

        service.search("teen")
        #expect(service.results.contains { $0.section == .familySafety })

        service.search("push")
        #expect(service.results.contains { $0.section == .notifications })
    }

    @Test("Snapshot restores booleans, integers, and strings")
    func snapshotApplyRestoresTypedValues() {
        let suiteName = "AmenSettingsSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshot = AmenSettingsSnapshot(values: [
            "amen_private_account": "true",
            "amen_notif_quiet_start_hour": "22",
            "amen_notif_digest": "Daily"
        ])

        snapshot.apply(to: defaults)

        #expect(defaults.bool(forKey: "amen_private_account") == true)
        #expect(defaults.integer(forKey: "amen_notif_quiet_start_hour") == 22)
        #expect(defaults.string(forKey: "amen_notif_digest") == "Daily")
    }
}
#endif
