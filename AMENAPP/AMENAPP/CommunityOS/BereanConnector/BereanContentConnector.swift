// BereanContentConnector.swift
// AMEN App — Community Around Content OS / Berean Connector
//
// Maps ContentObjects to scripture passages using a curated local theme→verse table.
// All lookups are purely local — no network calls, no Firestore reads.
// Gated by CommunityOSFlag.bereanContentConnector.

import Foundation

// MARK: - BereanContentConnector

actor BereanContentConnector {

    // MARK: Shared

    static let shared = BereanContentConnector()

    // MARK: Cache

    private struct CacheEntry {
        let chips: [BereanScriptureChip]
        let expiresAt: Date
    }

    /// 10-minute TTL, keyed by ContentObject.id
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 600

    // MARK: - Theme → Verse Table

    // swiftlint:disable line_length
    private let themeToVerses: [String: [BereanScriptureChip]] = [

        "trust": [
            BereanScriptureChip(
                reference: "Matthew 6:25-27",
                text: "Therefore I tell you, do not worry about your life, what you will eat or drink; or about your body, what you will wear. Is not life more than food, and the body more than clothes? Look at the birds of the air; they do not sow or reap or store away in barns, and yet your heavenly Father feeds them. Are you not much more valuable than they? Can any one of you by worrying add a single hour to your life?",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Proverbs 3:5-6",
                text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 56:3",
                text: "When I am afraid, I put my trust in you.",
                translation: "NIV"
            )
        ],

        "faith": [
            BereanScriptureChip(
                reference: "Hebrews 11:1",
                text: "Now faith is confidence in what we hope for and assurance about what we do not see.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Matthew 17:20",
                text: "He replied, 'Because you have so little faith. Truly I tell you, if you have faith as small as a mustard seed, you can say to this mountain, Move from here to there, and it will move. Nothing will be impossible for you.'",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 10:17",
                text: "Consequently, faith comes from hearing the message, and the message is heard through the word about Christ.",
                translation: "NIV"
            )
        ],

        "fear": [
            BereanScriptureChip(
                reference: "Isaiah 41:10",
                text: "So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Joshua 1:9",
                text: "Have I not commanded you? Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "2 Timothy 1:7",
                text: "For the Spirit God gave us does not make us timid, but gives us power, love and self-discipline.",
                translation: "NIV"
            )
        ],

        "worship": [
            BereanScriptureChip(
                reference: "John 4:24",
                text: "God is spirit, and his worshipers must worship in the Spirit and in truth.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 150:6",
                text: "Let everything that has breath praise the Lord. Praise the Lord.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 12:1",
                text: "Therefore, I urge you, brothers and sisters, in view of God's mercy, to offer your bodies as a living sacrifice, holy and pleasing to God — this is your true and proper worship.",
                translation: "NIV"
            )
        ],

        "prayer": [
            BereanScriptureChip(
                reference: "Philippians 4:6-7",
                text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:9-13",
                text: "This, then, is how you should pray: Our Father in heaven, hallowed be your name, your kingdom come, your will be done, on earth as it is in heaven. Give us today our daily bread. And forgive us our debts, as we also have forgiven our debtors. And lead us not into temptation, but deliver us from the evil one.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "1 Thessalonians 5:17",
                text: "Pray continually.",
                translation: "NIV"
            )
        ],

        "hope": [
            BereanScriptureChip(
                reference: "Romans 15:13",
                text: "May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Jeremiah 29:11",
                text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 8:28",
                text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
                translation: "NIV"
            )
        ],

        "healing": [
            BereanScriptureChip(
                reference: "Psalm 147:3",
                text: "He heals the brokenhearted and binds up their wounds.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Isaiah 53:5",
                text: "But he was pierced for our transgressions, he was crushed for our iniquities; the punishment that brought us peace was on him, and by his wounds we are healed.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "James 5:16",
                text: "Therefore confess your sins to each other and pray for each other so that you may be healed. The prayer of a righteous person is powerful and effective.",
                translation: "NIV"
            )
        ],

        "forgiveness": [
            BereanScriptureChip(
                reference: "Ephesians 4:32",
                text: "Be kind and compassionate to one another, forgiving each other, just as in Christ God forgave you.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Colossians 3:13",
                text: "Bear with each other and forgive one another if any of you has a grievance against someone. Forgive as the Lord forgave you.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:14-15",
                text: "For if you forgive other people when they sin against you, your heavenly Father will also forgive you. But if you do not forgive others their sins, your Father will not forgive your sins.",
                translation: "NIV"
            )
        ],

        "grace": [
            BereanScriptureChip(
                reference: "Ephesians 2:8-9",
                text: "For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God — not by works, so that no one can boast.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 12:9",
                text: "But he said to me, 'My grace is sufficient for you, for my power is made perfect in weakness.' Therefore I will boast all the more gladly about my weaknesses, so that Christ's power may rest on me.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Titus 2:11",
                text: "For the grace of God has appeared that offers salvation to all people.",
                translation: "NIV"
            )
        ],

        "love": [
            BereanScriptureChip(
                reference: "1 Corinthians 13:4-7",
                text: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs. Love does not delight in evil but rejoices with the truth. It always protects, always trusts, always hopes, always perseveres.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "John 3:16",
                text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 8:38-39",
                text: "For I am convinced that neither death nor life, neither angels nor demons, neither the present nor the future, nor any powers, neither height nor depth, nor anything else in all creation, will be able to separate us from the love of God that is in Christ Jesus our Lord.",
                translation: "NIV"
            )
        ],

        "oceans": [
            BereanScriptureChip(
                reference: "Matthew 14:28-29",
                text: "Lord, if it's you, Peter replied, tell me to come to you on the water. Come, he said. Then Peter got down out of the boat, walked on the water and came toward Jesus.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1-3",
                text: "God is our refuge and strength, an ever-present help in trouble. Therefore we will not fear, though the earth give way and the mountains fall into the heart of the sea, though its waters roar and foam and the mountains quake with their surging.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Isaiah 43:2",
                text: "When you pass through the waters, I will be with you; and when you pass through the rivers, they will not sweep over you.",
                translation: "NIV"
            )
        ],

        "water": [
            BereanScriptureChip(
                reference: "Isaiah 43:2",
                text: "When you pass through the waters, I will be with you; and when you pass through the rivers, they will not sweep over you.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1-3",
                text: "God is our refuge and strength, an ever-present help in trouble. Therefore we will not fear, though the earth give way and the mountains fall into the heart of the sea, though its waters roar and foam and the mountains quake with their surging.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "John 4:14",
                text: "But whoever drinks the water I give them will never thirst. Indeed, the water I give them will become in them a spring of water welling up to eternal life.",
                translation: "NIV"
            )
        ],

        "waves": [
            BereanScriptureChip(
                reference: "Matthew 14:28-29",
                text: "Lord, if it's you, Peter replied, tell me to come to you on the water. Come, he said. Then Peter got down out of the boat, walked on the water and came toward Jesus.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1-3",
                text: "God is our refuge and strength, an ever-present help in trouble. Therefore we will not fear, though the earth give way and the mountains fall into the heart of the sea, though its waters roar and foam and the mountains quake with their surging.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Isaiah 43:2",
                text: "When you pass through the waters, I will be with you; and when you pass through the rivers, they will not sweep over you.",
                translation: "NIV"
            )
        ],

        "goodness": [
            BereanScriptureChip(
                reference: "Psalm 23:6",
                text: "Surely your goodness and love will follow me all the days of my life, and I will dwell in the house of the Lord forever.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 8:28",
                text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 34:8",
                text: "Taste and see that the Lord is good; blessed is the one who takes refuge in him.",
                translation: "NIV"
            )
        ],

        "leadership": [
            BereanScriptureChip(
                reference: "Matthew 20:26",
                text: "Not so with you. Instead, whoever wants to become great among you must be your servant.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Proverbs 11:14",
                text: "For lack of guidance a nation falls, but victory is won through many advisers.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "1 Peter 5:2-3",
                text: "Be shepherds of God's flock that is under your care, watching over them — not because you must, but because you are willing, as God wants you to be; not pursuing dishonest gain, but eager to serve; not lording it over those entrusted to you, but being examples to the flock.",
                translation: "NIV"
            )
        ],

        "recovery": [
            BereanScriptureChip(
                reference: "Philippians 4:13",
                text: "I can do all this through him who gives me strength.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 5:17",
                text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 7:18-19",
                text: "For I know that good itself does not dwell in me, that is, in my sinful nature. For I have the desire to do what is good, but I cannot carry it out. For I do not do the good I want to do, but the evil I do not want to do — this I keep on doing.",
                translation: "NIV"
            )
        ],

        "addiction": [
            BereanScriptureChip(
                reference: "Philippians 4:13",
                text: "I can do all this through him who gives me strength.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 5:17",
                text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 7:18-19",
                text: "For I know that good itself does not dwell in me, that is, in my sinful nature. For I have the desire to do what is good, but I cannot carry it out. For I do not do the good I want to do, but the evil I do not want to do — this I keep on doing.",
                translation: "NIV"
            )
        ],

        "anxiety": [
            BereanScriptureChip(
                reference: "Philippians 4:6-7",
                text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:34",
                text: "Therefore do not worry about tomorrow, for tomorrow will worry about itself. Each day has enough trouble of its own.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "1 Peter 5:7",
                text: "Cast all your anxiety on him because he cares for you.",
                translation: "NIV"
            )
        ],

        "worry": [
            BereanScriptureChip(
                reference: "Philippians 4:6-7",
                text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Matthew 6:34",
                text: "Therefore do not worry about tomorrow, for tomorrow will worry about itself. Each day has enough trouble of its own.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "1 Peter 5:7",
                text: "Cast all your anxiety on him because he cares for you.",
                translation: "NIV"
            )
        ],

        "grief": [
            BereanScriptureChip(
                reference: "Psalm 34:18",
                text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "John 11:35",
                text: "Jesus wept.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 1:3-4",
                text: "Praise be to the God and Father of our Lord Jesus Christ, the Father of compassion and the God of all comfort, who comforts us in all our troubles, so that we can comfort those in any trouble with the comfort we ourselves receive from God.",
                translation: "NIV"
            )
        ],

        "loss": [
            BereanScriptureChip(
                reference: "Psalm 34:18",
                text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "2 Corinthians 1:3-4",
                text: "Praise be to the God and Father of our Lord Jesus Christ, the Father of compassion and the God of all comfort, who comforts us in all our troubles, so that we can comfort those in any trouble with the comfort we ourselves receive from God.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Revelation 21:4",
                text: "He will wipe every tear from their eyes. There will be no more death or mourning or crying or pain, for the old order of things has passed away.",
                translation: "NIV"
            )
        ],

        "marriage": [
            BereanScriptureChip(
                reference: "Genesis 2:24",
                text: "That is why a man leaves his father and mother and is united to his wife, and they become one flesh.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Ephesians 5:25",
                text: "Husbands, love your wives, just as Christ loved the church and gave himself up for her.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "1 Corinthians 13:4-7",
                text: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs. Love does not delight in evil but rejoices with the truth. It always protects, always trusts, always hopes, always perseveres.",
                translation: "NIV"
            )
        ],

        "purpose": [
            BereanScriptureChip(
                reference: "Jeremiah 29:11",
                text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Ephesians 2:10",
                text: "For we are God's handiwork, created in Christ Jesus to do good works, which God prepared in advance for us to do.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Romans 8:28",
                text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
                translation: "NIV"
            )
        ],

        "praise": [
            BereanScriptureChip(
                reference: "Psalm 150:1-6",
                text: "Praise the Lord. Praise God in his sanctuary; praise him in his mighty heavens. Praise him for his acts of power; praise him for his surpassing greatness. Praise him with the sounding of the trumpet, praise him with the harp and lyre, praise him with timbrel and dancing, praise him with the strings and pipe, praise him with the clash of cymbals, praise him with resounding cymbals. Let everything that has breath praise the Lord.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 9:1-2",
                text: "I will give thanks to you, Lord, with all my heart; I will tell of all your wonderful deeds. I will be glad and rejoice in you; I will sing the praises of your name, O Most High.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Hebrews 13:15",
                text: "Through Jesus, therefore, let us continually offer to God a sacrifice of praise — the fruit of lips that openly profess his name.",
                translation: "NIV"
            )
        ],

        "redemption": [
            BereanScriptureChip(
                reference: "Ephesians 1:7",
                text: "In him we have redemption through his blood, the forgiveness of sins, in accordance with the riches of God's grace.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Titus 2:14",
                text: "Who gave himself for us to redeem us from all wickedness and to purify for himself a people that are his very own, eager to do what is good.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Isaiah 44:22",
                text: "I have swept away your offenses like a cloud, your sins like the morning mist. Return to me, for I have redeemed you.",
                translation: "NIV"
            )
        ],

        "strength": [
            BereanScriptureChip(
                reference: "Philippians 4:13",
                text: "I can do all this through him who gives me strength.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Isaiah 40:31",
                text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 46:1",
                text: "God is our refuge and strength, an ever-present help in trouble.",
                translation: "NIV"
            )
        ],

        "peace": [
            BereanScriptureChip(
                reference: "John 14:27",
                text: "Peace I leave with you; my peace I give you. I do not give to you as the world gives. Do not let your hearts be troubled and do not be afraid.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Philippians 4:7",
                text: "And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Isaiah 26:3",
                text: "You will keep in perfect peace those whose minds are steadfast, because they trust in you.",
                translation: "NIV"
            )
        ],

        "joy": [
            BereanScriptureChip(
                reference: "Nehemiah 8:10",
                text: "Do not grieve, for the joy of the Lord is your strength.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "Psalm 16:11",
                text: "You make known to me the path of life; you will fill me with joy in your presence, with eternal pleasures at your right hand.",
                translation: "NIV"
            ),
            BereanScriptureChip(
                reference: "John 15:11",
                text: "I have told you this so that my joy may be in you and that your joy may be complete.",
                translation: "NIV"
            )
        ]
    ]
    // swiftlint:enable line_length

    // MARK: - Private Init

    private init() {}

    // MARK: - Public API

    /// Matches a ContentObject to relevant scripture chips using themes, title keywords,
    /// and any pre-linked verse references. Returns up to 5 deduplicated chips.
    func findVerses(for contentObject: ContentObject) -> [BereanScriptureChip] {
        guard CommunityOSFlagService.shared.isEnabled(.bereanContentConnector) else {
            dlog("[BereanContentConnector] Flag disabled — skipping verse lookup for \(contentObject.id)")
            return []
        }

        // Return cached result if still valid
        if let entry = cache[contentObject.id], entry.expiresAt > Date() {
            return entry.chips
        }

        let normalised = normalizedThemes(from: contentObject.themes)

        // Extract keyword themes from the title
        let titleWords = contentObject.title
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let titleThemes = Set(titleWords).intersection(Set(themeToVerses.keys))

        let allThemes = normalised.union(titleThemes)

        var collected: [BereanScriptureChip] = []

        // Theme-matched chips
        for theme in allThemes {
            if let chips = themeToVerses[theme] {
                collected.append(contentsOf: chips)
            }
        }

        // Chips seeded from linkedVerseRefs already on the ContentObject
        for ref in contentObject.linkedVerseRefs {
            let syntheticChip = BereanScriptureChip(reference: ref, text: "", translation: "")
            // Only insert if we don't already have a richer chip for this reference
            if !collected.contains(where: { $0.reference == ref }) {
                collected.append(syntheticChip)
            }
        }

        let result = deduplicated(collected, limit: 5)

        // Write to cache
        let expiry = Date().addingTimeInterval(cacheTTL)
        cache[contentObject.id] = CacheEntry(chips: result, expiresAt: expiry)

        dlog("[BereanContentConnector] Found \(result.count) verses for '\(contentObject.title)'")
        return result
    }

    /// Pure theme lookup. Returns up to 5 deduplicated scripture chips.
    func findVerses(for themes: [String]) -> [BereanScriptureChip] {
        guard CommunityOSFlagService.shared.isEnabled(.bereanContentConnector) else {
            dlog("[BereanContentConnector] Flag disabled — skipping theme lookup")
            return []
        }

        let normalised = normalizedThemes(from: themes)
        var collected: [BereanScriptureChip] = []

        for theme in normalised {
            if let chips = themeToVerses[theme] {
                collected.append(contentsOf: chips)
            }
        }

        return deduplicated(collected, limit: 5)
    }

    /// Returns only the reference strings — useful for writing back to ContentObject.linkedVerseRefs.
    func verseRefsOnly(for themes: [String]) -> [String] {
        findVerses(for: themes).map(\.reference)
    }

    // MARK: - Private Helpers

    /// Lowercases raw themes and applies simple singular normalization so that
    /// e.g. "fears" → "fear", "prayers" → "prayer".
    private func normalizedThemes(from raw: [String]) -> Set<String> {
        var result = Set<String>()
        for theme in raw {
            let lower = theme.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip common plural suffixes to improve match rate
            let singular: String
            if lower.hasSuffix("ies") && lower.count > 4 {
                singular = String(lower.dropLast(3)) + "y"
            } else if lower.hasSuffix("es") && lower.count > 4 {
                singular = String(lower.dropLast(2))
            } else if lower.hasSuffix("s") && lower.count > 3 {
                singular = String(lower.dropLast(1))
            } else {
                singular = lower
            }
            result.insert(lower)
            if singular != lower { result.insert(singular) }
        }
        return result
    }

    /// Deduplicates chips by reference and returns at most `limit` items.
    private func deduplicated(_ chips: [BereanScriptureChip], limit: Int) -> [BereanScriptureChip] {
        var seen = Set<String>()
        var result: [BereanScriptureChip] = []
        for chip in chips {
            guard !chip.reference.isEmpty, seen.insert(chip.reference).inserted else { continue }
            result.append(chip)
            if result.count >= limit { break }
        }
        return result
    }
}
