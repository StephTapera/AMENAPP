// SelahKJVJSONLoaderTests.swift
// AMENAPPTests
//
// Tests the JSON decode path of the KJV loader against a synthetic
// payload, so the loader contract is pinned independent of the real
// kjv.json resource (which is owned by the app team and may not be
// checked into the repo).

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("SelahKJVJSONLoader")
struct SelahKJVJSONLoaderTests {

    @Test("Decodes a minimal valid payload into a chapter index")
    func decodesValidPayload() {
        let json = """
        {
          "translation": "kjv",
          "books": {
            "romans": {
              "5": [
                {"n": 1, "t": "Therefore being justified by faith..."},
                {"n": 2, "t": "By whom also we have access..."}
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let index = SelahKJVJSONLoader.decode(data: json)
        let chapter = index?.chapter(bookId: "romans", chapter: 5)
        #expect(chapter != nil)
        #expect(chapter?.verses.count == 2)
        #expect(chapter?.translationId == "kjv")
    }

    @Test("Verses are sorted by ascending verse number even if input is shuffled")
    func versesAreSorted() {
        let json = """
        {
          "translation": "kjv",
          "books": {
            "psalms": {
              "23": [
                {"n": 3, "t": "He restoreth my soul."},
                {"n": 1, "t": "The LORD is my shepherd."},
                {"n": 2, "t": "He maketh me to lie down."}
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let index = SelahKJVJSONLoader.decode(data: json)
        let nums = index?.chapter(bookId: "psalms", chapter: 23)?.verses.map { $0.number }
        #expect(nums == [1, 2, 3])
    }

    @Test("Invalid payload returns nil rather than empty chapter")
    func invalidPayloadReturnsNil() {
        let badJSON = "{\"not\": \"valid\"}".data(using: .utf8)!
        #expect(SelahKJVJSONLoader.decode(data: badJSON) == nil)
    }

    @Test("Empty books map yields an empty index, not nil")
    func emptyBooksYieldsEmptyIndex() {
        let json = """
        {"translation": "kjv", "books": {}}
        """.data(using: .utf8)!
        let index = SelahKJVJSONLoader.decode(data: json)
        #expect(index != nil)
        #expect(index?.isEmpty == true)
    }
}

#endif
