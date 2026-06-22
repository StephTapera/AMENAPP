import Testing
@testable import AMENAPP

@Suite("Safety Wave 3 age-tier contract")
struct SafetyWave3AgeTierTests {

    @Test("AgeCategory raw values match canonical CF vocabulary")
    func ageCategoryRawValuesMatchCanonicalVocabulary() {
        #expect(AgeCategory.canonicalRawValues == ["blocked", "tierB", "tierC", "tierD"])
        #expect(AgeCategory.allCases.map(\.rawValue) == AgeCategory.canonicalRawValues)
    }

    @Test("unknown AgeCategory raw value fails closed to blocked")
    func unknownAgeCategoryFailsClosed() {
        #expect(AgeCategory.resolving(nil) == .blocked)
        #expect(AgeCategory.resolving("adult") == .blocked)
        #expect(AgeCategory.resolving("teen") == .blocked)
        #expect(AgeCategory.resolving("under_minimum") == .blocked)
    }

    @Test("minor tiers exclude tierD only")
    func minorTiersExcludeTierDOnly() {
        #expect(AgeCategory.resolving("blocked").isMinor == true)
        #expect(AgeCategory.resolving("tierB").isMinor == true)
        #expect(AgeCategory.resolving("tierC").isMinor == true)
        #expect(AgeCategory.resolving("tierD").isMinor == false)
    }

    @Test("Algolia people index excludes minor and unknown profiles")
    func algoliaPeopleIndexExcludesMinorProfiles() {
        #expect(AlgoliaSyncService.shouldExcludeFromPeopleIndex(["ageTier": "blocked"]) == true)
        #expect(AlgoliaSyncService.shouldExcludeFromPeopleIndex(["ageTier": "tierB"]) == true)
        #expect(AlgoliaSyncService.shouldExcludeFromPeopleIndex(["ageTier": "tierC"]) == true)
        #expect(AlgoliaSyncService.shouldExcludeFromPeopleIndex(["ageTier": "tierD"]) == false)
        #expect(AlgoliaSyncService.shouldExcludeFromPeopleIndex([:]) == true)
        #expect(AlgoliaSyncService.shouldExcludeFromPeopleIndex(["ageTier": "tierD", "minorScoped": true]) == true)
        #expect(AlgoliaSyncService.shouldExcludeFromPeopleIndex(["ageTier": "tierD", "isMinor": true]) == true)
    }
}
