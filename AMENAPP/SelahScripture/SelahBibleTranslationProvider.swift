//
//  SelahBibleTranslationProvider.swift
//  AMENAPP
//
//  Translation-source abstraction for the Selah Scripture Reader.
//
//  Three conformers ship today:
//   * `SelahLocalPublicDomainBibleProvider` — KJV only, public-domain text
//     bundled at compile time. Honest: only chapters that have real text
//     return `.available`; everything else returns `.unavailable(reason:)`.
//     The reader UI surfaces that state instead of faking content.
//   * `SelahRemoteBibleProvider` — placeholder for a future licensed
//     API-backed provider. Today it returns `.unavailable` for all calls.
//   * `SelahMockBibleProvider` — synthetic placeholder. Compiled only
//     under `#if DEBUG` so production cannot accidentally render it.
//

import Foundation

// MARK: - Provider Protocol

protocol SelahBibleTranslationProvider {
    /// Translations this provider knows how to serve. The reader UI uses
    /// `availability(for:)` to decide if any one of them can render text.
    var supportedTranslations: [SelahBibleTranslation] { get }

    func availability(for translation: SelahBibleTranslation) -> SelahBibleTranslationAvailability

    func loadChapter(
        bookId: String,
        chapter: Int,
        translation: SelahBibleTranslation
    ) async throws -> SelahBibleChapter

    func search(
        keyword: String,
        translation: SelahBibleTranslation,
        limit: Int
    ) async throws -> [SelahScriptureSearchResult]
}

// MARK: - Provider Error

enum SelahBibleTranslationProviderError: LocalizedError, Equatable {
    case translationUnavailable(translationId: String, reason: String)
    case chapterNotFound(bookId: String, chapter: Int)
    case bookNotFound(bookId: String)

    var errorDescription: String? {
        switch self {
        case .translationUnavailable(_, let reason): return reason
        case .chapterNotFound(let bookId, let chapter): return "\(bookId) \(chapter) is not available."
        case .bookNotFound(let bookId): return "Unknown book '\(bookId)'."
        }
    }
}

// MARK: - Local Public-Domain Provider (KJV)

/// Loads KJV (public domain) text bundled at compile time. Only a small set
/// of well-known chapters ship inline today; the rest return
/// `.unavailable(reason:)` so the host UI can be honest with the user.
struct SelahLocalPublicDomainBibleProvider: SelahBibleTranslationProvider {

    var supportedTranslations: [SelahBibleTranslation] { [.kjv] }

    func availability(for translation: SelahBibleTranslation) -> SelahBibleTranslationAvailability {
        guard translation.id == SelahBibleTranslation.kjv.id else {
            return .unavailable(reason: "\(translation.abbreviation) is not bundled locally.")
        }
        return .available
    }

    func loadChapter(bookId: String, chapter: Int, translation: SelahBibleTranslation) async throws -> SelahBibleChapter {
        guard translation.id == SelahBibleTranslation.kjv.id else {
            throw SelahBibleTranslationProviderError.translationUnavailable(
                translationId: translation.id,
                reason: "\(translation.abbreviation) is not bundled locally."
            )
        }
        guard SelahBibleBook.find(id: bookId) != nil else {
            throw SelahBibleTranslationProviderError.bookNotFound(bookId: bookId)
        }
        if let bundled = SelahKJVBundledText.chapter(bookId: bookId, chapter: chapter) {
            return bundled
        }
        throw SelahBibleTranslationProviderError.chapterNotFound(bookId: bookId, chapter: chapter)
    }

    func search(keyword: String, translation: SelahBibleTranslation, limit: Int) async throws -> [SelahScriptureSearchResult] {
        guard translation.id == SelahBibleTranslation.kjv.id else { return [] }
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var hits: [SelahScriptureSearchResult] = []
        for chapter in SelahKJVBundledText.allChapters {
            for verse in chapter.verses {
                let body = verse.text.lowercased()
                if body.contains(needle) {
                    hits.append(SelahScriptureSearchResult(
                        reference: verse.reference,
                        translationId: chapter.translationId,
                        preview: verse.text,
                        score: 1.0
                    ))
                    if hits.count >= limit { return hits }
                }
            }
        }
        return hits
    }
}

// MARK: - Remote Provider Placeholder

/// Reserved for a future licensed API integration. Always returns
/// `.unavailable` today so production callers can wire it confidently
/// without accidentally rendering fabricated text.
struct SelahRemoteBibleProvider: SelahBibleTranslationProvider {

    var supportedTranslations: [SelahBibleTranslation] {
// TODO(legal): Add .esv/.niv/.nlt/.nasb back once commercial licenses confirmed (AMEN-CONTENT-001).
        [.csb, .nkjv]
    }

    func availability(for translation: SelahBibleTranslation) -> SelahBibleTranslationAvailability {
        .unavailable(reason: "\(translation.abbreviation) requires a licensed connection. Configure the remote translation service to enable it.")
    }

    func loadChapter(bookId: String, chapter: Int, translation: SelahBibleTranslation) async throws -> SelahBibleChapter {
        throw SelahBibleTranslationProviderError.translationUnavailable(
            translationId: translation.id,
            reason: "\(translation.abbreviation) is not yet enabled in this build."
        )
    }

    func search(keyword: String, translation: SelahBibleTranslation, limit: Int) async throws -> [SelahScriptureSearchResult] {
        []
    }
}

// MARK: - Composite Provider

/// Routes by translation to the appropriate underlying provider. Production
/// callers should generally use this — it is the public face of the
/// translation system.
struct SelahCompositeBibleProvider: SelahBibleTranslationProvider {
    let local: SelahLocalPublicDomainBibleProvider
    let remote: SelahRemoteBibleProvider

    init(
        local: SelahLocalPublicDomainBibleProvider = .init(),
        remote: SelahRemoteBibleProvider = .init()
    ) {
        self.local = local
        self.remote = remote
    }

    var supportedTranslations: [SelahBibleTranslation] {
        local.supportedTranslations + remote.supportedTranslations
    }

    func availability(for translation: SelahBibleTranslation) -> SelahBibleTranslationAvailability {
        if local.supportedTranslations.contains(where: { $0.id == translation.id }) {
            return local.availability(for: translation)
        }
        if remote.supportedTranslations.contains(where: { $0.id == translation.id }) {
            return remote.availability(for: translation)
        }
        return .unavailable(reason: "\(translation.abbreviation) is not a known translation.")
    }

    func loadChapter(bookId: String, chapter: Int, translation: SelahBibleTranslation) async throws -> SelahBibleChapter {
        if local.supportedTranslations.contains(where: { $0.id == translation.id }) {
            return try await local.loadChapter(bookId: bookId, chapter: chapter, translation: translation)
        }
        return try await remote.loadChapter(bookId: bookId, chapter: chapter, translation: translation)
    }

    func search(keyword: String, translation: SelahBibleTranslation, limit: Int) async throws -> [SelahScriptureSearchResult] {
        if local.supportedTranslations.contains(where: { $0.id == translation.id }) {
            return try await local.search(keyword: keyword, translation: translation, limit: limit)
        }
        return try await remote.search(keyword: keyword, translation: translation, limit: limit)
    }
}

// MARK: - DEBUG Mock Provider

#if DEBUG
/// Synthetic provider for tests and previews ONLY. Generates predictable
/// placeholder verses so UI / preference / pagination code can be exercised
/// in isolation. Never compiled into release builds.
struct SelahMockBibleProvider: SelahBibleTranslationProvider {
    let translation: SelahBibleTranslation

    init(translation: SelahBibleTranslation = SelahBibleTranslation(
        id: "mock", displayName: "Mock", abbreviation: "MOCK", license: .mock
    )) {
        self.translation = translation
    }

    var supportedTranslations: [SelahBibleTranslation] { [translation] }

    func availability(for translation: SelahBibleTranslation) -> SelahBibleTranslationAvailability {
        translation.id == self.translation.id ? .available : .unavailable(reason: "Mock only serves its own id.")
    }

    func loadChapter(bookId: String, chapter: Int, translation: SelahBibleTranslation) async throws -> SelahBibleChapter {
        guard translation.id == self.translation.id else {
            throw SelahBibleTranslationProviderError.translationUnavailable(translationId: translation.id, reason: "Mock only serves its own id.")
        }
        let verses = (1...3).map { number in
            SelahBibleVerse(
                reference: SelahScriptureReference(bookId: bookId, chapter: chapter, startVerse: number, endVerse: nil),
                number: number,
                text: "Mock verse \(number) of \(bookId) \(chapter)."
            )
        }
        return SelahBibleChapter(bookId: bookId, chapter: chapter, translationId: translation.id, verses: verses)
    }

    func search(keyword: String, translation: SelahBibleTranslation, limit: Int) async throws -> [SelahScriptureSearchResult] {
        guard translation.id == self.translation.id else { return [] }
        let ref = SelahScriptureReference(bookId: "john", chapter: 3, startVerse: 16, endVerse: nil)
        return [SelahScriptureSearchResult(reference: ref, translationId: translation.id, preview: "Mock match for \(keyword).")]
    }
}
#endif

// MARK: - KJV Bundled Text (Public Domain)
//
// A small inline set of King James Version chapters. The KJV is public
// domain in the United States (no copyright). The selection here is
// intentionally short — enough for the reader to demonstrate paging,
// search, and navigation against real scripture. Additional chapters
// should be bundled via a separate `kjv.json` resource and loaded by
// extending `SelahKJVBundledText.allChapters`.

enum SelahKJVBundledText {

    static let allChapters: [SelahBibleChapter] = [
        psalm23,
        psalm1,
        john3,
        romans5,
        genesis1
    ]

    static func chapter(bookId: String, chapter: Int) -> SelahBibleChapter? {
        allChapters.first { $0.bookId == bookId && $0.chapter == chapter }
    }

    // MARK: Builders

    private static func verse(_ bookId: String, _ chapter: Int, _ n: Int, _ text: String) -> SelahBibleVerse {
        SelahBibleVerse(
            reference: SelahScriptureReference(bookId: bookId, chapter: chapter, startVerse: n, endVerse: nil),
            number: n,
            text: text
        )
    }

    private static func chapter(_ bookId: String, _ chapter: Int, _ verses: [SelahBibleVerse]) -> SelahBibleChapter {
        SelahBibleChapter(bookId: bookId, chapter: chapter, translationId: SelahBibleTranslation.kjv.id, verses: verses)
    }

    // MARK: Psalm 23

    static let psalm23: SelahBibleChapter = chapter("psalms", 23, [
        verse("psalms", 23, 1, "The LORD is my shepherd; I shall not want."),
        verse("psalms", 23, 2, "He maketh me to lie down in green pastures: he leadeth me beside the still waters."),
        verse("psalms", 23, 3, "He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake."),
        verse("psalms", 23, 4, "Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me."),
        verse("psalms", 23, 5, "Thou preparest a table before me in the presence of mine enemies: thou anointest my head with oil; my cup runneth over."),
        verse("psalms", 23, 6, "Surely goodness and mercy shall follow me all the days of my life: and I will dwell in the house of the LORD for ever.")
    ])

    // MARK: Psalm 1

    static let psalm1: SelahBibleChapter = chapter("psalms", 1, [
        verse("psalms", 1, 1, "Blessed is the man that walketh not in the counsel of the ungodly, nor standeth in the way of sinners, nor sitteth in the seat of the scornful."),
        verse("psalms", 1, 2, "But his delight is in the law of the LORD; and in his law doth he meditate day and night."),
        verse("psalms", 1, 3, "And he shall be like a tree planted by the rivers of water, that bringeth forth his fruit in his season; his leaf also shall not wither; and whatsoever he doeth shall prosper."),
        verse("psalms", 1, 4, "The ungodly are not so: but are like the chaff which the wind driveth away."),
        verse("psalms", 1, 5, "Therefore the ungodly shall not stand in the judgment, nor sinners in the congregation of the righteous."),
        verse("psalms", 1, 6, "For the LORD knoweth the way of the righteous: but the way of the ungodly shall perish.")
    ])

    // MARK: John 3 (the famous verses around 16)

    static let john3: SelahBibleChapter = chapter("john", 3, [
        verse("john", 3, 14, "And as Moses lifted up the serpent in the wilderness, even so must the Son of man be lifted up:"),
        verse("john", 3, 15, "That whosoever believeth in him should not perish, but have eternal life."),
        verse("john", 3, 16, "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
        verse("john", 3, 17, "For God sent not his Son into the world to condemn the world; but that the world through him might be saved."),
        verse("john", 3, 18, "He that believeth on him is not condemned: but he that believeth not is condemned already, because he hath not believed in the name of the only begotten Son of God."),
        verse("john", 3, 19, "And this is the condemnation, that light is come into the world, and men loved darkness rather than light, because their deeds were evil."),
        verse("john", 3, 20, "For every one that doeth evil hateth the light, neither cometh to the light, lest his deeds should be reproved."),
        verse("john", 3, 21, "But he that doeth truth cometh to the light, that his deeds may be made manifest, that they are wrought in God.")
    ])

    // MARK: Romans 5 (suffering → hope passage)

    static let romans5: SelahBibleChapter = chapter("romans", 5, [
        verse("romans", 5, 1, "Therefore being justified by faith, we have peace with God through our Lord Jesus Christ:"),
        verse("romans", 5, 2, "By whom also we have access by faith into this grace wherein we stand, and rejoice in hope of the glory of God."),
        verse("romans", 5, 3, "And not only so, but we glory in tribulations also: knowing that tribulation worketh patience;"),
        verse("romans", 5, 4, "And patience, experience; and experience, hope:"),
        verse("romans", 5, 5, "And hope maketh not ashamed; because the love of God is shed abroad in our hearts by the Holy Ghost which is given unto us."),
        verse("romans", 5, 6, "For when we were yet without strength, in due time Christ died for the ungodly."),
        verse("romans", 5, 7, "For scarcely for a righteous man will one die: yet peradventure for a good man some would even dare to die."),
        verse("romans", 5, 8, "But God commendeth his love toward us, in that, while we were yet sinners, Christ died for us.")
    ])

    // MARK: Genesis 1 (creation prologue)

    static let genesis1: SelahBibleChapter = chapter("genesis", 1, [
        verse("genesis", 1, 1, "In the beginning God created the heaven and the earth."),
        verse("genesis", 1, 2, "And the earth was without form, and void; and darkness was upon the face of the deep. And the Spirit of God moved upon the face of the waters."),
        verse("genesis", 1, 3, "And God said, Let there be light: and there was light."),
        verse("genesis", 1, 4, "And God saw the light, that it was good: and God divided the light from the darkness."),
        verse("genesis", 1, 5, "And God called the light Day, and the darkness he called Night. And the evening and the morning were the first day.")
    ])
}
