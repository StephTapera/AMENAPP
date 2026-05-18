//
//  SelahScripturePreviews.swift
//  AMENAPP
//
//  SwiftUI `#Preview` macros for the Selah Scripture surfaces. Compiled
//  only in DEBUG so they don't bloat release builds. Use these in Xcode
//  Canvas to visually verify the reader, search, and supporting cards
//  without needing to launch the simulator end-to-end.
//

#if DEBUG
import SwiftUI

#Preview("Scripture Reader · Psalm 23 (KJV)") {
    SelahScriptureReaderView(
        initialReference: SelahScriptureReference(
            bookId: "psalms", chapter: 23, startVerse: nil, endVerse: nil
        ),
        provider: SelahLocalPublicDomainBibleProvider(),
        preferencesStore: SelahScriptureReaderPreferencesStore(
            defaults: UserDefaults(suiteName: "selah.preview.reader") ?? .standard
        )
    )
}

#Preview("Scripture Reader · Romans 8 (KJV)") {
    SelahScriptureReaderView(
        initialReference: SelahScriptureReference(
            bookId: "romans", chapter: 8, startVerse: 28, endVerse: nil
        ),
        provider: SelahLocalPublicDomainBibleProvider(),
        preferencesStore: SelahScriptureReaderPreferencesStore(
            defaults: UserDefaults(suiteName: "selah.preview.reader.2") ?? .standard
        )
    )
}

#Preview("Scripture Search · idle") {
    SelahScriptureSearchView(
        provider: SelahCompositeBibleProvider(),
        preferencesStore: SelahScriptureReaderPreferencesStore(
            defaults: UserDefaults(suiteName: "selah.preview.search") ?? .standard
        )
    )
}

#Preview("Reaction Picker · John 3:16") {
    SelahVerseReactionPickerSheet(
        reference: SelahScriptureReference(
            bookId: "john", chapter: 3, startVerse: 16, endVerse: nil
        ),
        translationId: "kjv",
        store: SelahVerseEngagementStore(
            defaults: UserDefaults(suiteName: "selah.preview.engagement") ?? .standard
        )
    )
}

#Preview("Share Card · Psalm 23:1") {
    SelahScriptureShareCardView(
        reference: SelahScriptureReference(
            bookId: "psalms", chapter: 23, startVerse: 1, endVerse: nil
        ),
        text: "The LORD is my shepherd; I shall not want.",
        translationAbbreviation: "KJV"
    )
    .padding(40)
    .background(Color(.systemGroupedBackground))
}

#Preview("Verse Context Peek") {
    SelahVerseContextPeek(
        reference: "Romans 5:3-5",
        snippet: "And not only so, but we glory in tribulations also: knowing that tribulation worketh patience; And patience, experience; and experience, hope.",
        translation: "KJV"
    )
    .padding(.vertical, 60)
    .background(Color(.systemGroupedBackground))
}

#Preview("Continue Reading Banner") {
    SelahContinueReadingBanner(
        title: "Continue in Romans 5",
        subtitle: "Resume your reading"
    )
    .padding(20)
    .background(Color(.systemBackground))
}

#Preview("Topic Exploration") {
    SelahTopicExplorationView()
}

#Preview("Scripture Timeline") {
    SelahScriptureTimelineView()
}
#endif
