//
//  BereanScriptureGrounding.swift
//  AMENAPP
//
//  Bible RAG grounding layer for Berean AI. Retrieves relevant scripture
//  verses from the local ScriptureIndex and composes them into a system
//  prompt context block so the LLM quotes canonical text instead of
//  relying on training data (which can paraphrase or hallucinate verses).
//
//  This runs synchronously on-device with zero network cost — just a
//  keyword search against the in-memory index (~100 verses).
//

import Foundation

// MARK: - Scripture Grounding Composer

struct BereanScriptureGrounding {

    /// Searches the local scripture index for verses relevant to the query
    /// and composes them into a `<scripture_context>` block for the system prompt.
    /// Returns nil if no relevant verses are found.
    static func buildContext(for query: String) -> String? {
        let matches = ScriptureIndex.search(query: query)

        // Also search the expanded index
        let expandedMatches = ExpandedScriptureIndex.search(query: query)

        // Merge and deduplicate by reference
        var seen = Set<String>()
        var allMatches: [BereanRetrievalSource] = []

        for m in (matches + expandedMatches).sorted(by: { $0.relevanceScore > $1.relevanceScore }) {
            let ref = m.reference ?? m.title
            if !seen.contains(ref) {
                seen.insert(ref)
                allMatches.append(m)
            }
        }

        // Take top 8 most relevant
        let topVerses = allMatches.prefix(8)
        guard !topVerses.isEmpty else { return nil }

        let versesBlock = topVerses.map { source in
            source.content
        }.joined(separator: "\n")

        return """
        <scripture_context>
        The following scripture verses are relevant to the user's question.
        When citing scripture, you MUST quote from these exact texts rather than paraphrasing from memory.
        You may also cite other verses you know, but prefer these retrieved references for accuracy.
        Do NOT list all of these verses — only use the ones that are genuinely relevant to the answer.

        \(versesBlock)
        </scripture_context>
        """
    }
}

// MARK: - Expanded Scripture Index

/// Extended verse catalog covering ~80 additional topics beyond the base ScriptureIndex.
/// All verses are NIV text for consistency.
struct ExpandedScriptureIndex {

    typealias Entry = ScriptureIndex.Entry

    static let index: [Entry] = [
        // ── Forgiveness ──
        Entry(reference: "Ephesians 4:32", text: "Be kind and compassionate to one another, forgiving each other, just as in Christ God forgave you.",
              keywords: ["forgiveness", "forgive", "compassion", "kindness", "grudge", "resentment"]),
        Entry(reference: "Colossians 3:13", text: "Bear with each other and forgive one another if any of you has a grievance against someone. Forgive as the Lord forgave you.",
              keywords: ["forgiveness", "forgive", "grievance", "grudge", "letting go"]),
        Entry(reference: "Matthew 6:14-15", text: "For if you forgive other people when they sin against you, your heavenly Father will also forgive you.",
              keywords: ["forgiveness", "forgive", "sin", "reconciliation"]),

        // ── Grief and Loss ──
        Entry(reference: "Psalm 34:18", text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit.",
              keywords: ["grief", "loss", "brokenhearted", "pain", "death", "mourning", "sorrow"]),
        Entry(reference: "Revelation 21:4", text: "He will wipe every tear from their eyes. There will be no more death or mourning or crying or pain.",
              keywords: ["grief", "death", "heaven", "hope", "tears", "mourning", "loss"]),
        Entry(reference: "Matthew 5:4", text: "Blessed are those who mourn, for they will be comforted.",
              keywords: ["mourning", "grief", "comfort", "loss", "blessed"]),

        // ── Anger ──
        Entry(reference: "James 1:19-20", text: "Everyone should be quick to listen, slow to speak and slow to become angry, because human anger does not produce the righteousness that God desires.",
              keywords: ["anger", "listen", "patience", "wrath", "temper", "conflict"]),
        Entry(reference: "Proverbs 15:1", text: "A gentle answer turns away wrath, but a harsh word stirs up anger.",
              keywords: ["anger", "words", "gentleness", "conflict", "speech", "wrath"]),
        Entry(reference: "Ephesians 4:26-27", text: "In your anger do not sin: Do not let the sun go down while you are still angry, and do not give the devil a foothold.",
              keywords: ["anger", "sin", "devil", "conflict", "emotions"]),

        // ── Identity in Christ ──
        Entry(reference: "2 Corinthians 5:17", text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!",
              keywords: ["identity", "new creation", "transformation", "change", "past", "worth"]),
        Entry(reference: "Psalm 139:13-14", text: "For you created my inmost being; you knit me together in my mother's womb. I praise you because I am fearfully and wonderfully made.",
              keywords: ["identity", "self-worth", "creation", "body image", "value", "purpose", "insecurity"]),
        Entry(reference: "Galatians 2:20", text: "I have been crucified with Christ and I no longer live, but Christ lives in me.",
              keywords: ["identity", "christ", "living", "crucified", "faith", "transformation"]),

        // ── Marriage and Relationships ──
        Entry(reference: "Ecclesiastes 4:9-10", text: "Two are better than one, because they have a good return for their labor: If either of them falls down, one can help the other up.",
              keywords: ["marriage", "relationships", "friendship", "partnership", "community", "loneliness"]),
        Entry(reference: "Proverbs 18:22", text: "He who finds a wife finds what is good and receives favor from the Lord.",
              keywords: ["marriage", "spouse", "dating", "relationship", "wife", "husband"]),
        Entry(reference: "Mark 10:9", text: "Therefore what God has joined together, let no one separate.",
              keywords: ["marriage", "divorce", "relationship", "commitment"]),

        // ── Parenting ──
        Entry(reference: "Proverbs 22:6", text: "Start children off on the way they should go, and even when they are old they will not turn from it.",
              keywords: ["parenting", "children", "raising", "family", "discipline", "teaching"]),
        Entry(reference: "Deuteronomy 6:6-7", text: "These commandments that I give you today are to be on your hearts. Impress them on your children.",
              keywords: ["parenting", "children", "teaching", "family", "faith", "home"]),

        // ── Money and Finances ──
        Entry(reference: "Proverbs 21:20", text: "The wise store up choice food and olive oil, but fools gulp theirs down.",
              keywords: ["money", "finances", "saving", "budget", "stewardship", "spending"]),
        Entry(reference: "1 Timothy 6:10", text: "For the love of money is a root of all kinds of evil.",
              keywords: ["money", "greed", "wealth", "materialism", "contentment"]),
        Entry(reference: "Malachi 3:10", text: "Bring the whole tithe into the storehouse, that there may be food in my house. Test me in this, says the Lord Almighty.",
              keywords: ["tithing", "giving", "generosity", "money", "offering", "stewardship"]),
        Entry(reference: "Matthew 6:19-21", text: "Do not store up for yourselves treasures on earth, where moths and vermin destroy. But store up for yourselves treasures in heaven.",
              keywords: ["money", "treasure", "wealth", "materialism", "eternal", "priorities"]),

        // ── Temptation ──
        Entry(reference: "1 Corinthians 10:13", text: "No temptation has overtaken you except what is common to mankind. And God is faithful; he will not let you be tempted beyond what you can bear.",
              keywords: ["temptation", "struggle", "sin", "addiction", "faithful", "escape"]),
        Entry(reference: "James 4:7", text: "Submit yourselves, then, to God. Resist the devil, and he will flee from you.",
              keywords: ["temptation", "devil", "resist", "submit", "spiritual warfare"]),

        // ── Patience and Waiting ──
        Entry(reference: "Psalm 27:14", text: "Wait for the Lord; be strong and take heart and wait for the Lord.",
              keywords: ["patience", "waiting", "timing", "trust", "strength"]),
        Entry(reference: "Isaiah 40:31", text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary.",
              keywords: ["patience", "hope", "strength", "endurance", "waiting", "tired", "weary"]),
        Entry(reference: "Lamentations 3:25", text: "The Lord is good to those whose hope is in him, to the one who seeks him.",
              keywords: ["patience", "hope", "seeking", "waiting", "trust"]),

        // ── Gratitude ──
        Entry(reference: "1 Thessalonians 5:16-18", text: "Rejoice always, pray continually, give thanks in all circumstances; for this is God's will for you in Christ Jesus.",
              keywords: ["gratitude", "thankfulness", "joy", "prayer", "rejoice", "thanksgiving"]),
        Entry(reference: "Psalm 100:4", text: "Enter his gates with thanksgiving and his courts with praise; give thanks to him and praise his name.",
              keywords: ["gratitude", "thanksgiving", "praise", "worship", "thankful"]),

        // ── Depression and Sadness ──
        Entry(reference: "Psalm 42:11", text: "Why, my soul, are you downcast? Why so disturbed within me? Put your hope in God, for I will yet praise him, my Savior and my God.",
              keywords: ["depression", "sad", "downcast", "hopeless", "despairing", "discouraged"]),
        Entry(reference: "Psalm 30:5", text: "For his anger lasts only a moment, but his favor lasts a lifetime; weeping may stay for the night, but rejoicing comes in the morning.",
              keywords: ["sadness", "grief", "hope", "morning", "joy", "weeping", "depression"]),

        // ── Loneliness ──
        Entry(reference: "Deuteronomy 31:6", text: "Be strong and courageous. Do not be afraid or terrified because of them, for the Lord your God goes with you; he will never leave you nor forsake you.",
              keywords: ["loneliness", "alone", "abandoned", "courage", "presence", "afraid"]),
        Entry(reference: "Hebrews 13:5", text: "Keep your lives free from the love of money and be content with what you have, because God has said, 'Never will I leave you; never will I forsake you.'",
              keywords: ["loneliness", "contentment", "abandoned", "presence", "faithfulness"]),

        // ── Healing ──
        Entry(reference: "Psalm 147:3", text: "He heals the brokenhearted and binds up their wounds.",
              keywords: ["healing", "broken", "wounds", "restoration", "pain", "recovery"]),
        Entry(reference: "James 5:14-15", text: "Is anyone among you sick? Let them call the elders of the church to pray over them and anoint them with oil in the name of the Lord.",
              keywords: ["healing", "sick", "illness", "prayer", "health", "recovery"]),
        Entry(reference: "Jeremiah 17:14", text: "Heal me, Lord, and I will be healed; save me and I will be saved, for you are the one I praise.",
              keywords: ["healing", "prayer", "salvation", "praise", "restoration"]),

        // ── Doubt ──
        Entry(reference: "Mark 9:24", text: "Immediately the boy's father exclaimed, 'I do believe; help me overcome my unbelief!'",
              keywords: ["doubt", "faith", "believe", "unbelief", "struggling", "questions"]),
        Entry(reference: "John 20:29", text: "Then Jesus told him, 'Because you have seen me, you have believed; blessed are those who have not seen and yet have believed.'",
              keywords: ["doubt", "faith", "believe", "evidence", "thomas", "trust"]),

        // ── Church and Community ──
        Entry(reference: "Hebrews 10:24-25", text: "And let us consider how we may spur one another on toward love and good deeds, not giving up meeting together.",
              keywords: ["church", "community", "fellowship", "gathering", "encouragement", "together"]),
        Entry(reference: "Acts 2:42", text: "They devoted themselves to the apostles' teaching and to fellowship, to the breaking of bread and to prayer.",
              keywords: ["church", "fellowship", "community", "devotion", "prayer", "worship"]),

        // ── Leadership and Influence ──
        Entry(reference: "Proverbs 11:14", text: "For lack of guidance a nation falls, but victory is won through many advisers.",
              keywords: ["leadership", "guidance", "advice", "mentorship", "wisdom", "counsel"]),
        Entry(reference: "Mark 10:43-45", text: "Whoever wants to become great among you must be your servant, and whoever wants to be first must be slave of all.",
              keywords: ["leadership", "servant", "humility", "greatness", "ministry"]),

        // ── Perseverance ──
        Entry(reference: "Romans 5:3-4", text: "We also glory in our sufferings, because we know that suffering produces perseverance; perseverance, character; and character, hope.",
              keywords: ["perseverance", "suffering", "character", "hope", "endurance", "trials"]),
        Entry(reference: "Hebrews 12:1", text: "Let us throw off everything that hinders and the sin that so easily entangles. And let us run with perseverance the race marked out for us.",
              keywords: ["perseverance", "race", "endurance", "sin", "running", "discipline"]),
        Entry(reference: "Galatians 6:9", text: "Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up.",
              keywords: ["perseverance", "weary", "giving up", "harvest", "good works", "patience"]),

        // ── Holy Spirit ──
        Entry(reference: "John 14:26", text: "But the Advocate, the Holy Spirit, whom the Father will send in my name, will teach you all things and will remind you of everything I have said to you.",
              keywords: ["holy spirit", "advocate", "teacher", "comforter", "spirit"]),
        Entry(reference: "Acts 1:8", text: "But you will receive power when the Holy Spirit comes on you; and you will be my witnesses in Jerusalem, and to the ends of the earth.",
              keywords: ["holy spirit", "power", "witness", "evangelism", "pentecost"]),
        Entry(reference: "Romans 8:26", text: "In the same way, the Spirit helps us in our weakness. We do not know what we ought to pray for, but the Spirit himself intercedes for us.",
              keywords: ["holy spirit", "prayer", "weakness", "intercession", "help"]),

        // ── Grace ──
        Entry(reference: "Ephesians 2:8-9", text: "For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God — not by works.",
              keywords: ["grace", "salvation", "faith", "works", "gift", "saved"]),
        Entry(reference: "2 Corinthians 12:9", text: "But he said to me, 'My grace is sufficient for you, for my power is made perfect in weakness.'",
              keywords: ["grace", "weakness", "power", "sufficient", "strength", "struggle"]),
        Entry(reference: "Romans 6:14", text: "For sin shall no longer be your master, because you are not under the law, but under grace.",
              keywords: ["grace", "sin", "law", "freedom", "salvation"]),

        // ── Baptism ──
        Entry(reference: "Romans 6:3-4", text: "Or don't you know that all of us who were baptized into Christ Jesus were baptized into his death? We were therefore buried with him through baptism into death in order that, just as Christ was raised from the dead, we too may live a new life.",
              keywords: ["baptism", "death", "resurrection", "new life", "faith"]),
        Entry(reference: "Acts 2:38", text: "Repent and be baptized, every one of you, in the name of Jesus Christ for the forgiveness of your sins.",
              keywords: ["baptism", "repent", "forgiveness", "salvation", "sins"]),

        // ── Heaven and Eternity ──
        Entry(reference: "John 14:2-3", text: "My Father's house has many rooms; if that were not so, would I have told you that I am going there to prepare a place for you?",
              keywords: ["heaven", "eternal life", "afterlife", "death", "eternity", "mansions"]),
        Entry(reference: "Philippians 3:20", text: "But our citizenship is in heaven. And we eagerly await a Savior from there, the Lord Jesus Christ.",
              keywords: ["heaven", "citizenship", "eternal", "hope", "savior"]),

        // ── Worship ──
        Entry(reference: "Psalm 95:1-2", text: "Come, let us sing for joy to the Lord; let us shout aloud to the Rock of our salvation. Let us come before him with thanksgiving.",
              keywords: ["worship", "praise", "singing", "music", "thanksgiving", "joy"]),
        Entry(reference: "John 4:24", text: "God is spirit, and his worshipers must worship in the Spirit and in truth.",
              keywords: ["worship", "spirit", "truth", "prayer", "devotion"]),

        // ── Obedience ──
        Entry(reference: "John 14:15", text: "If you love me, keep my commandments.",
              keywords: ["obedience", "love", "commandments", "following", "discipline"]),
        Entry(reference: "1 Samuel 15:22", text: "To obey is better than sacrifice, and to heed is better than the fat of rams.",
              keywords: ["obedience", "sacrifice", "listening", "following god"]),

        // ── Righteousness ──
        Entry(reference: "Matthew 5:6", text: "Blessed are those who hunger and thirst for righteousness, for they will be filled.",
              keywords: ["righteousness", "justice", "holiness", "blessed", "hunger"]),
        Entry(reference: "Romans 3:23-24", text: "For all have sinned and fall short of the glory of God, and all are justified freely by his grace through the redemption that came by Christ Jesus.",
              keywords: ["sin", "righteousness", "justification", "grace", "redemption", "salvation"]),

        // ── Unity ──
        Entry(reference: "Psalm 133:1", text: "How good and pleasant it is when God's people live together in unity!",
              keywords: ["unity", "community", "peace", "together", "church", "harmony"]),
        Entry(reference: "Ephesians 4:3", text: "Make every effort to keep the unity of the Spirit through the bond of peace.",
              keywords: ["unity", "peace", "spirit", "effort", "church", "division"]),

        // ── Humility ──
        Entry(reference: "Philippians 2:3-4", text: "Do nothing out of selfish ambition or vain conceit. Rather, in humility value others above yourselves.",
              keywords: ["humility", "selfishness", "pride", "others", "servant"]),
        Entry(reference: "Proverbs 11:2", text: "When pride comes, then comes disgrace, but with humility comes wisdom.",
              keywords: ["humility", "pride", "wisdom", "disgrace"]),
        Entry(reference: "James 4:10", text: "Humble yourselves before the Lord, and he will lift you up.",
              keywords: ["humility", "humble", "exalt", "pride", "god"]),

        // ── Hope ──
        Entry(reference: "Romans 15:13", text: "May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit.",
              keywords: ["hope", "joy", "peace", "trust", "spirit", "overflow"]),
        Entry(reference: "Psalm 46:1", text: "God is our refuge and strength, an ever-present help in trouble.",
              keywords: ["hope", "refuge", "strength", "trouble", "help", "safety", "protection"]),
    ]

    static func search(query: String) -> [BereanRetrievalSource] {
        let lower = query.lowercased()
        let queryWords = lower.split(separator: " ").map(String.init).filter { $0.count > 3 }

        return index.compactMap { entry -> (BereanRetrievalSource, Double)? in
            var score = 0.0
            // Direct reference match (highest)
            if lower.contains(entry.reference.lowercased()) { score += 1.0 }
            // Keyword matches
            let matchedKeywords = entry.keywords.filter { keyword in
                queryWords.contains(where: { $0.contains(keyword) || keyword.contains($0) })
            }
            score += Double(matchedKeywords.count) * 0.15
            guard score > 0 else { return nil }
            let source = BereanRetrievalSource(
                id: "scripture-expanded-\(entry.reference.replacingOccurrences(of: " ", with: "-"))",
                type: .scripture,
                title: entry.reference,
                content: "\(entry.reference): \"\(entry.text)\"",
                reference: entry.reference,
                relevanceScore: min(1.0, score),
                url: nil
            )
            return (source, score)
        }
        .sorted { $0.1 > $1.1 }
        .map { $0.0 }
    }
}
