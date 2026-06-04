// BereanFormationService.swift
// AMENAPP — Berean Daily Formation Companion — Card assembly + verse gate
//
// HARD CONSTRAINT: all verse text flows through getVerse() only.
// Crisis items are excluded from the arc and feed cards.

import Foundation

enum BereanFormationService {

    // MARK: - Verse gate (single source of truth)

    static func getVerse(_ ref: String, translation: String = "ESV") -> BereanVerse {
        guard !ref.isEmpty else {
            return BereanVerse(text: "", citation: "", isMock: false)
        }
        let book = BereanMockData.verseDB[ref]
        let text = book?[translation] ?? book?.values.first
            ?? "[MOCK — \(translation)] \(ref)"
#if !DEBUG
        // Mock verse text must never ship — block the verse card in release builds
        // until a YouVersion Content API license is obtained and integrated.
        assert(false, "BereanFormationService.getVerse() returned mock text in a non-DEBUG build. Integrate the YouVersion Content API before release.")
        return BereanVerse(text: "", citation: "", isMock: false)
#else
        return BereanVerse(text: text, citation: "\(ref) (\(translation))", isMock: true)
#endif
    }

    // MARK: - Clean display text (strips [MOCK — XYZ] prefix)

    static func displayText(_ verse: BereanVerse) -> String {
        verse.text.replacingOccurrences(
            of: #"\[MOCK — \w+\] "#,
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - Today's ISO date

    private static var todayISO: String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return fmt.string(from: Date())
    }

    // MARK: - Card assembly (deterministic, no shuffle)

    // AUDIT GAP: assembleCards() has no daily quota or rate-limit guard. When this
    // function is wired to real AI-generated reflection content (e.g. a CF that
    // calls the LLM to personalise the verse reflection), callers must check a
    // Firestore-backed daily counter before invoking. A hard cap of 1 formation
    // generation per user per UTC day should be enforced server-side in the CF and
    // echoed client-side to prevent duplicate CF invocations.
    //
    // AUDIT GAP: assembleCards() has no BereanGuardrailEngine pass on any
    // AI-generated reflection text. When real LLM-produced content replaces the
    // hardcoded reflection strings in BereanVerseReflectionCard, each generated
    // string must be passed through BereanGuardrailEngine (or its server-side
    // equivalent) before being stored in Firestore and before being rendered.
    static func assembleCards(
        readingPlan: BereanReadingPlan,
        prayerList: [BereanPrayerItem],
        sanctuaries: [BereanSanctuary],
        highlights: [BereanHighlight],
        memoryVerses: [BereanMemoryVerse],
        seasonal: BereanSeasonalRhythm?,
        translationPref: String,
        selectedTopics: Set<String>
    ) -> [BereanFormationCard] {
        var cards: [BereanFormationCard] = []

        // 1. Verse & Reflection
        if selectedTopics.contains("verse") {
            let verse = getVerse(readingPlan.todayPassageRef, translation: translationPref)
            cards.append(BereanFormationCard(
                id: "card-verse",
                cardType: .verse,
                typeLabel: "Daily Verse",
                icon: "sparkle",
                source: "readingPlan",
                sourceDetail: readingPlan.name,
                previewText: String(displayText(verse).prefix(100)) + "\u{2026}",
                verseChipRef: readingPlan.todayPassageRef,
                data: .verse(verse, passageRange: readingPlan.todayPassageRange)
            ))
        }

        // 2. Reading Plan
        if selectedTopics.contains("plan") {
            cards.append(BereanFormationCard(
                id: "card-plan",
                cardType: .plan,
                typeLabel: "Reading Plan",
                icon: "book",
                source: "readingPlan",
                sourceDetail: readingPlan.name,
                previewText: "Day \(readingPlan.currentDay) of \(readingPlan.totalDays) \u{2014} \(readingPlan.todayPassageRange)",
                verseChipRef: nil,
                data: .plan(readingPlan)
            ))
        }

        // 3. Prayer (skip crisis — safety engine handles them separately)
        if selectedTopics.contains("prayer") {
            let nonCrisisPrayers = prayerList.filter {
                $0.sensitivity != .crisis && $0.status == "active"
            }
            if let prayer = nonCrisisPrayers.first {
                cards.append(BereanFormationCard(
                    id: "card-prayer-\(prayer.id)",
                    cardType: .prayer,
                    typeLabel: "Prayer Follow-up",
                    icon: "hands.clap",
                    source: "prayerList",
                    sourceDetail: "Your prayer list",
                    previewText: prayer.subject,
                    verseChipRef: nil,
                    data: .prayer(prayer)
                ))
            }
        }

        // 4. Sanctuary
        if selectedTopics.contains("sanctuary"), let s = sanctuaries.first {
            cards.append(BereanFormationCard(
                id: "card-sanctuary-\(s.id)",
                cardType: .sanctuary,
                typeLabel: "Sanctuary",
                icon: "building.columns",
                source: "sanctuary",
                sourceDetail: s.name,
                previewText: "\(s.openPrayerRequests) open prayer requests \u{00B7} \(s.recentActivity)",
                verseChipRef: nil,
                data: .sanctuary(s)
            ))
        }

        // 5. Study
        if selectedTopics.contains("study"), let h = highlights.last {
            let verse = getVerse(h.verseRef, translation: translationPref)
            cards.append(BereanFormationCard(
                id: "card-study",
                cardType: .study,
                typeLabel: "Open Study",
                icon: "magnifyingglass",
                source: "highlights",
                sourceDetail: "Your highlights",
                previewText: "\"\(h.note)\"",
                verseChipRef: h.verseRef,
                data: .study(h, verse: verse)
            ))
        }

        // 6. Memory (only if SRS due date <= today)
        if selectedTopics.contains("memory") {
            let today = todayISO
            if let due = memoryVerses
                .filter({ $0.srsDueDate <= today })
                .sorted(by: { $0.strength < $1.strength })
                .first {
                let verse = getVerse(due.verseRef, translation: translationPref)
                cards.append(BereanFormationCard(
                    id: "card-memory-\(due.id)",
                    cardType: .memory,
                    typeLabel: "Memory Verse",
                    icon: "brain",
                    source: "memoryVerses",
                    sourceDetail: "Scripture memorization",
                    previewText: "\(due.verseRef) \u{2014} \(Int(due.strength * 100))% strength \u{00B7} review due today",
                    verseChipRef: due.verseRef,
                    data: .memory(due, verse: verse)
                ))
            }
        }

        // 7. Seasonal
        if selectedTopics.contains("seasonal"), let s = seasonal {
            cards.append(BereanFormationCard(
                id: "card-seasonal",
                cardType: .seasonal,
                typeLabel: "Seasonal Rhythm",
                icon: "leaf",
                source: "liturgicalCalendar",
                sourceDetail: s.liturgicalSeason,
                previewText: s.prompt,
                verseChipRef: nil,
                data: .seasonal(s)
            ))
        }

        return cards
    }
}
