#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - WorshipDetector Tests

@Suite("WorshipDetector")
struct WorshipDetectorTests {

    @Test("Detects worship by tag keyword — exact match")
    func tagExactMatch() {
        #expect(WorshipDetector.isWorship(tags: ["worship"]))
        #expect(WorshipDetector.isWorship(tags: ["praise"]))
        #expect(WorshipDetector.isWorship(tags: ["hymn"]))
    }

    @Test("Detects worship by tag keyword — case insensitive")
    func tagCaseInsensitive() {
        #expect(WorshipDetector.isWorship(tags: ["WORSHIP"]))
        #expect(WorshipDetector.isWorship(tags: ["Hillsong"]))
        #expect(WorshipDetector.isWorship(tags: ["Contemporary Worship"]))
    }

    @Test("Detects worship by tag keyword — partial substring")
    func tagSubstringMatch() {
        #expect(WorshipDetector.isWorship(tags: ["gospel music 2024"]))
        #expect(WorshipDetector.isWorship(tags: ["elevation worship live"]))
    }

    @Test("Does not flag non-worship tags")
    func tagNoFalsePositive() {
        #expect(!WorshipDetector.isWorship(tags: ["sports", "cooking", "tech"]))
        #expect(!WorshipDetector.isWorship(tags: ["sermon"]))
        #expect(!WorshipDetector.isWorship(tags: []))
    }

    @Test("Detects worship by contentType — exact match")
    func contentTypeExactMatch() {
        #expect(WorshipDetector.isWorship(contentType: "worship"))
        #expect(WorshipDetector.isWorship(contentType: "gospel music"))
        #expect(WorshipDetector.isWorship(contentType: "hymnal"))
    }

    @Test("Detects worship by contentType — case insensitive")
    func contentTypeCaseInsensitive() {
        #expect(WorshipDetector.isWorship(contentType: "WORSHIP"))
        #expect(WorshipDetector.isWorship(contentType: "Gospel Music"))
        #expect(WorshipDetector.isWorship(contentType: "Praise"))
    }

    @Test("Does not flag non-worship contentType")
    func contentTypeNoFalsePositive() {
        #expect(!WorshipDetector.isWorship(contentType: "sermon"))
        #expect(!WorshipDetector.isWorship(contentType: "podcast"))
        #expect(!WorshipDetector.isWorship(contentType: ""))
    }
}

// MARK: - ScriptureRefDetector Tests

@Suite("ScriptureRefDetector")
struct ScriptureRefDetectorTests {

    @Test("Detects single chapter:verse reference")
    func singleVerseRef() {
        let refs = ScriptureRefDetector.detect(in: "For God so loved the world John 3:16")
        #expect(refs.count == 1)
        #expect(refs[0].reference == "John 3:16")
    }

    @Test("Detects verse range reference")
    func verseRangeRef() {
        let refs = ScriptureRefDetector.detect(in: "Blessed are the poor Matthew 5:3-12")
        #expect(refs.count == 1)
        #expect(refs[0].reference == "Matthew 5:3-12")
    }

    @Test("Detects common book abbreviations")
    func abbreviations() {
        let ps = ScriptureRefDetector.detect(in: "Ps 23:1")
        #expect(!ps.isEmpty)

        let rom = ScriptureRefDetector.detect(in: "Rom 8:28")
        #expect(!rom.isEmpty)

        let gen = ScriptureRefDetector.detect(in: "Gen 1:1")
        #expect(!gen.isEmpty)
    }

    @Test("Detects numbered book references")
    func numberedBooks() {
        let firstCor = ScriptureRefDetector.detect(in: "1 Cor 13:4")
        #expect(!firstCor.isEmpty)

        let secondTim = ScriptureRefDetector.detect(in: "2 Tim 3:16")
        #expect(!secondTim.isEmpty)

        let firstJohn = ScriptureRefDetector.detect(in: "1 John 4:8")
        #expect(!firstJohn.isEmpty)
    }

    @Test("Detects multiple references in one string")
    func multipleRefs() {
        let text = "John 3:16 and Romans 8:28 are my favorite verses."
        let refs = ScriptureRefDetector.detect(in: text)
        #expect(refs.count == 2)
    }

    @Test("Returns references in document order")
    func documentOrder() {
        let text = "Read Romans 12:2 before John 14:6"
        let refs = ScriptureRefDetector.detect(in: text)
        #expect(refs.count == 2)
        #expect(refs[0].reference.hasPrefix("Rom"))
        #expect(refs[1].reference.hasPrefix("John"))
    }

    @Test("Returns empty array for text with no references")
    func noReferences() {
        let refs = ScriptureRefDetector.detect(in: "No bible references here, just some text.")
        #expect(refs.isEmpty)
    }

    @Test("Returns empty array for empty string")
    func emptyString() {
        let refs = ScriptureRefDetector.detect(in: "")
        #expect(refs.isEmpty)
    }

    @Test("Does not false-positive on partial matches like 'John Smith 3:16'")
    func noPartialBookNameFalsePositive() {
        // 'John' at word boundary in 'John Smith 3:16' — the regex requires
        // Chapter:Verse immediately after optional whitespace after the book name,
        // so 'John Smith 3:16' should NOT match John 3:16.
        let refs = ScriptureRefDetector.detect(in: "John Smith 3:16 meeting room")
        // If matched, it should not produce a reference containing 'Smith'
        for ref in refs {
            #expect(!ref.reference.contains("Smith"))
        }
    }

    @Test("Range is valid within the source string")
    func rangeIsValid() {
        let text = "Check out Philippians 4:13 today"
        let refs = ScriptureRefDetector.detect(in: text)
        #expect(!refs.isEmpty)
        let ref = refs[0]
        let extracted = String(text[ref.range])
        #expect(extracted == ref.reference)
    }
}

#endif
