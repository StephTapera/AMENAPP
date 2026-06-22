// BereanFormationMockData.swift
// AMENAPP — Berean Daily Formation Companion — Mock data
//
// All verse text prefixed [MOCK — TRANSLATION]. Real text requires
// a YouVersion Content API license. This placeholder must never ship.

import Foundation

enum BereanMockData {

    // MARK: - Verse DB

    // TODO(legal): ESV/NIV mock keys replaced with KJV per AMEN-CONTENT-001.
    static let verseDB: [String: [String: String]] = [
        "Acts 17:11": [
            "KJV": "[MOCK — KJV] Now these Jews were more noble than those in Thessalonica; they received the word with all eagerness, examining the Scriptures daily to see if these things were so.",
        ],
        "Psalm 46:10": [
            "KJV": "[MOCK — KJV] Be still, and know that I am God. I will be exalted among the nations, I will be exalted in the earth!",
        ],
        "Isaiah 40:31": [
            "KJV": "[MOCK — KJV] But they who wait for the LORD shall renew their strength; they shall mount up with wings like eagles; they shall run and not be weary; they shall walk and not faint.",
        ],
        "Matthew 6:33": [
            "KJV": "[MOCK — KJV] But seek first the kingdom of God and his righteousness, and all these things will be added to you.",
        ],
        "Romans 8:28": [
            "KJV": "[MOCK — KJV] And we know that for those who love God all things work together for good, for those who are called according to his purpose.",
        ],
        "Lamentations 3:22-23": [
            "KJV": "[MOCK — KJV] The steadfast love of the LORD never ceases; his mercies never come to an end; they are new every morning; great is your faithfulness.",
        ],
        "Philippians 4:6-7": [
            "KJV": "[MOCK — KJV] Do not be anxious about anything, but in everything by prayer and supplication with thanksgiving let your requests be made known to God.",
        ],
        "1 Peter 5:7": [
            "KJV": "[MOCK — KJV] Casting all your anxieties on him, because he cares for you.",
        ],
    ]

    // MARK: - Reading plan

    static let readingPlan = BereanReadingPlan(
        name: "Through the Gospels in 90 Days",
        currentDay: 23,
        totalDays: 90,
        todayPassageRef: "Matthew 6:33",
        todayPassageRange: "Matthew 6:25\u{2013}34"
    )

    // MARK: - Prayer list

    static let prayerList: [BereanPrayerItem] = [
        BereanPrayerItem(id: "p1", subject: "Mom's surgery recovery",              forWhom: "Mom",  prayedOn: "2026-05-28", status: "active",   sensitivity: .tender),
        BereanPrayerItem(id: "p2", subject: "Jake's job search",                   forWhom: "Jake", prayedOn: "2026-06-01", status: "active",   sensitivity: .normal),
        BereanPrayerItem(id: "p3", subject: "Mental health \u{2014} walking a dark season", forWhom: "Self", prayedOn: "2026-05-30", status: "active",   sensitivity: .crisis),
        BereanPrayerItem(id: "p4", subject: "Gratitude for new community",         forWhom: "Self", prayedOn: "2026-06-02", status: "answered", sensitivity: .normal),
    ]

    // MARK: - Sanctuaries

    static let sanctuaries: [BereanSanctuary] = [
        BereanSanctuary(id: "s1", name: "Oakwood Young Adults",  openPrayerRequests: 3, activeThreads: 2, recentActivity: "Sofia shared a testimony this morning"),
        BereanSanctuary(id: "s2", name: "Morning Prayer Circle", openPrayerRequests: 7, activeThreads: 1, recentActivity: "New prayer request from Marcus"),
    ]

    // MARK: - Highlights

    static let highlights: [BereanHighlight] = [
        BereanHighlight(id: "h1", verseRef: "Isaiah 40:31", note: "This hit me during the hard week. Still processing.", savedOn: "2026-05-25"),
        BereanHighlight(id: "h2", verseRef: "Romans 8:28",  note: "Want to dig into the Greek for \"called according to purpose\".", savedOn: "2026-06-01"),
    ]

    // MARK: - Memory verses

    static let memoryVerses: [BereanMemoryVerse] = [
        BereanMemoryVerse(id: "mv1", verseRef: "Psalm 46:10",          srsDueDate: "2026-06-02", strength: 0.55, streak: 5),
        BereanMemoryVerse(id: "mv2", verseRef: "Lamentations 3:22-23", srsDueDate: "2026-06-04", strength: 0.80, streak: 12),
    ]

    // MARK: - Seasonal

    static let seasonal = BereanSeasonalRhythm(
        liturgicalSeason: "Ordinary Time",
        prompt: "Ordinary Time invites faithful attention to the everyday. Where is the sacred hiding in your routine today?"
    )
}
