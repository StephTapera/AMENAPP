//
//  SelahKJVJSONLoader.swift
//  AMENAPP
//
//  Loader that reads KJV chapters from a JSON resource bundled with the
//  app. The inline `SelahKJVBundledText.allChapters` set in
//  `SelahBibleTranslationProvider.swift` is the always-on safety net; this
//  loader is the production path once a full `kjv.json` is added to the
//  app target's resources.
//
//  Expected JSON shape (UTF-8):
//
//    {
//      "translation": "kjv",
//      "books": {
//        "john": {
//          "3": [
//            { "n": 1, "t": "There was a man of the Pharisees..." },
//            ...
//          ],
//          ...
//        },
//        ...
//      }
//    }
//
//  Status today: a tiny SAMPLE `kjv.sample.json` is bundled to demonstrate
//  the loader path works end-to-end. The real ~5MB `kjv.json` should be
//  added by the team once the canonical text is sourced. The loader will
//  pick up any resource named "kjv.json" or "kjv.sample.json" — production
//  wins by file-name precedence.
//

import Foundation

enum SelahKJVJSONLoader {

    private static let preferredFilename = "kjv.json"
    private static let sampleFilename = "kjv.sample.json"

    /// Loaded once at first access. Returns an empty index if no JSON
    /// resource is present — callers should fall back to the inline
    /// `SelahKJVBundledText.allChapters`.
    static let shared: SelahKJVChapterIndex = {
        if let loaded = loadIndex(named: preferredFilename) { return loaded }
        if let loaded = loadIndex(named: sampleFilename) { return loaded }
        return SelahKJVChapterIndex(chapters: [:])
    }()

    /// Test seam: load any named JSON file from the main bundle.
    static func loadIndex(named filename: String, bundle: Bundle = .main) -> SelahKJVChapterIndex? {
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        guard let url = bundle.url(forResource: stem, withExtension: ext.isEmpty ? "json" : ext),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decode(data: data)
    }

    /// Test seam: parse a JSON Data blob directly.
    static func decode(data: Data) -> SelahKJVChapterIndex? {
        guard let payload = try? JSONDecoder().decode(SelahKJVJSONPayload.self, from: data) else {
            return nil
        }
        var built: [String: SelahBibleChapter] = [:]
        for (bookId, chapters) in payload.books {
            for (chapterString, rawVerses) in chapters {
                guard let chapter = Int(chapterString) else { continue }
                let verses = rawVerses
                    .sorted { $0.n < $1.n }
                    .map { rv in
                        SelahBibleVerse(
                            reference: SelahScriptureReference(
                                bookId: bookId, chapter: chapter,
                                startVerse: rv.n, endVerse: nil
                            ),
                            number: rv.n,
                            text: rv.t
                        )
                    }
                let key = "\(bookId).\(chapter)"
                built[key] = SelahBibleChapter(
                    bookId: bookId,
                    chapter: chapter,
                    translationId: payload.translation,
                    verses: verses
                )
            }
        }
        return SelahKJVChapterIndex(chapters: built)
    }
}

struct SelahKJVChapterIndex {
    let chapters: [String: SelahBibleChapter]

    func chapter(bookId: String, chapter: Int) -> SelahBibleChapter? {
        chapters["\(bookId).\(chapter)"]
    }

    var isEmpty: Bool { chapters.isEmpty }
    var count: Int { chapters.count }
}

private struct SelahKJVJSONPayload: Decodable {
    let translation: String
    let books: [String: [String: [SelahKJVJSONVerse]]]
}

private struct SelahKJVJSONVerse: Decodable {
    let n: Int
    let t: String
}
