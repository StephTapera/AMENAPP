//
//  ScriptureSentimentMapper.swift
//  AMENAPP
//
//  Maps emotional states to scripture passages using sentiment analysis.
//  Powers the "Personal Verse" feature and emotional context in Berean AI.
//

import Foundation

class ScriptureSentimentMapper {
    static let shared = ScriptureSentimentMapper()
    private init() {}

    struct EmotionMapping {
        let emotion: Emotion
        let intensity: Float // 0.0-1.0
        let scriptures: [ScriptureRecommendation]
    }

    struct ScriptureRecommendation {
        let reference: String
        let text: String
        let reason: String
        let themes: [String]
    }

    enum Emotion: String, CaseIterable {
        case joy, gratitude, peace, hope, love
        case anxiety, fear, sadness, grief, anger
        case confusion, doubt, loneliness, shame, guilt
        case overwhelm, frustration, jealousy, pride, despair
    }

    // MARK: - Emotion Detection

    func detectEmotion(in text: String) -> [(emotion: Emotion, confidence: Float)] {
        let lower = text.lowercased()
        var scores: [Emotion: Float] = [:]

        for (emotion, keywords) in emotionKeywords {
            let matchCount = keywords.filter { lower.contains($0) }.count
            if matchCount > 0 {
                scores[emotion] = Float(matchCount) / Float(keywords.count)
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (emotion: $0.key, confidence: $0.value) }
    }

    // MARK: - Scripture Mapping

    func mapToScripture(emotions: [(emotion: Emotion, confidence: Float)]) -> [ScriptureRecommendation] {
        var recommendations: [ScriptureRecommendation] = []

        for (emotion, _) in emotions.prefix(2) {
            if let verses = scriptureMap[emotion] {
                recommendations.append(contentsOf: verses.prefix(2))
            }
        }

        return recommendations
    }

    func getScripturesForEmotion(_ emotion: Emotion) -> [ScriptureRecommendation] {
        scriptureMap[emotion] ?? []
    }

    // MARK: - Full Pipeline

    func analyze(text: String) -> EmotionMapping {
        let emotions = detectEmotion(in: text)
        let primary = emotions.first?.emotion ?? .peace
        let intensity = emotions.first?.confidence ?? 0.5
        let scriptures = mapToScripture(emotions: emotions)

        return EmotionMapping(emotion: primary, intensity: intensity, scriptures: scriptures)
    }

    // MARK: - Data

    private let emotionKeywords: [Emotion: [String]] = [
        .joy:          ["joyful", "happy", "excited", "celebrating", "blessed", "wonderful"],
        .gratitude:    ["thankful", "grateful", "appreciate", "thank god", "so blessed"],
        .peace:        ["peaceful", "calm", "rest", "still", "quiet", "content"],
        .hope:         ["hopeful", "looking forward", "optimistic", "trusting", "believe"],
        .love:         ["love", "loving", "cherish", "beloved", "care deeply"],
        .anxiety:      ["anxious", "worried", "nervous", "can't stop thinking", "overwhelmed", "panicking"],
        .fear:         ["afraid", "scared", "terrified", "fearful", "frightened"],
        .sadness:      ["sad", "crying", "tears", "heartbroken", "hurting", "pain"],
        .grief:        ["loss", "lost", "passed away", "mourning", "grieving", "miss them"],
        .anger:        ["angry", "furious", "frustrated", "rage", "unfair", "injustice"],
        .confusion:    ["confused", "don't understand", "lost", "uncertain", "unsure"],
        .doubt:        ["doubt", "questioning", "struggling to believe", "faith wavering"],
        .loneliness:   ["lonely", "alone", "isolated", "no one understands", "abandoned"],
        .shame:        ["ashamed", "shame", "disgusted with myself", "unworthy"],
        .guilt:        ["guilty", "regret", "should have", "my fault", "i'm sorry"],
        .overwhelm:    ["overwhelmed", "too much", "drowning", "can't handle", "falling apart"],
        .frustration:  ["frustrated", "stuck", "hitting a wall", "nothing works", "tired of"],
        .jealousy:     ["jealous", "envious", "why them", "it's not fair", "compared to"],
        .pride:        ["proud", "accomplished", "achieved", "overcame", "victory"],
        .despair:      ["hopeless", "give up", "no point", "nothing matters", "empty"],
    ]

    private let scriptureMap: [Emotion: [ScriptureRecommendation]] = [
        .anxiety: [
            ScriptureRecommendation(reference: "Philippians 4:6-7", text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.", reason: "God invites you to bring your worries to Him", themes: ["anxiety", "prayer", "peace"]),
            ScriptureRecommendation(reference: "1 Peter 5:7", text: "Cast all your anxiety on him because he cares for you.", reason: "You don't have to carry this alone", themes: ["anxiety", "care", "surrender"]),
            ScriptureRecommendation(reference: "Matthew 6:34", text: "Therefore do not worry about tomorrow, for tomorrow will worry about itself.", reason: "Jesus speaks directly to worry about the future", themes: ["worry", "trust", "present"]),
        ],
        .fear: [
            ScriptureRecommendation(reference: "Isaiah 41:10", text: "Fear not, for I am with you; be not dismayed, for I am your God.", reason: "God promises His presence in your fear", themes: ["fear", "presence", "strength"]),
            ScriptureRecommendation(reference: "2 Timothy 1:7", text: "For God has not given us a spirit of fear, but of power and of love and of a sound mind.", reason: "Fear is not from God", themes: ["fear", "power", "courage"]),
        ],
        .sadness: [
            ScriptureRecommendation(reference: "Psalm 34:18", text: "The LORD is close to the brokenhearted and saves those who are crushed in spirit.", reason: "God draws near in your sadness", themes: ["sadness", "comfort", "nearness"]),
            ScriptureRecommendation(reference: "Revelation 21:4", text: "He will wipe every tear from their eyes. There will be no more death or mourning or crying or pain.", reason: "This pain is temporary", themes: ["hope", "eternity", "comfort"]),
        ],
        .grief: [
            ScriptureRecommendation(reference: "Psalm 147:3", text: "He heals the brokenhearted and binds up their wounds.", reason: "God is the healer of broken hearts", themes: ["grief", "healing", "comfort"]),
            ScriptureRecommendation(reference: "John 11:35", text: "Jesus wept.", reason: "Jesus knows your grief — He grieves too", themes: ["grief", "empathy", "humanity"]),
        ],
        .loneliness: [
            ScriptureRecommendation(reference: "Deuteronomy 31:6", text: "The LORD your God goes with you; he will never leave you nor forsake you.", reason: "You are never truly alone", themes: ["loneliness", "presence", "faithfulness"]),
            ScriptureRecommendation(reference: "Psalm 68:6", text: "God sets the lonely in families.", reason: "God provides community for the isolated", themes: ["loneliness", "community", "belonging"]),
        ],
        .doubt: [
            ScriptureRecommendation(reference: "Mark 9:24", text: "I do believe; help me overcome my unbelief!", reason: "Even faith heroes had doubt — it's okay to be honest", themes: ["doubt", "honesty", "growth"]),
            ScriptureRecommendation(reference: "James 1:5-6", text: "If any of you lacks wisdom, you should ask God, who gives generously to all.", reason: "God welcomes your questions", themes: ["doubt", "wisdom", "asking"]),
        ],
        .joy: [
            ScriptureRecommendation(reference: "Psalm 16:11", text: "You make known to me the path of life; you will fill me with joy in your presence.", reason: "Joy flows from being near God", themes: ["joy", "presence", "life"]),
            ScriptureRecommendation(reference: "Nehemiah 8:10", text: "The joy of the LORD is your strength.", reason: "Joy is a source of spiritual strength", themes: ["joy", "strength", "worship"]),
        ],
        .gratitude: [
            ScriptureRecommendation(reference: "1 Thessalonians 5:18", text: "Give thanks in all circumstances; for this is God's will for you in Christ Jesus.", reason: "Gratitude is a spiritual practice", themes: ["gratitude", "thanksgiving", "will"]),
        ],
        .hope: [
            ScriptureRecommendation(reference: "Romans 15:13", text: "May the God of hope fill you with all joy and peace as you trust in him.", reason: "Hope comes from trusting God", themes: ["hope", "joy", "trust"]),
            ScriptureRecommendation(reference: "Jeremiah 29:11", text: "For I know the plans I have for you, declares the LORD, plans to prosper you and not to harm you.", reason: "God has good plans for your future", themes: ["hope", "future", "plans"]),
        ],
        .shame: [
            ScriptureRecommendation(reference: "Romans 8:1", text: "There is now no condemnation for those who are in Christ Jesus.", reason: "In Christ, shame has no hold on you", themes: ["shame", "freedom", "grace"]),
        ],
        .guilt: [
            ScriptureRecommendation(reference: "1 John 1:9", text: "If we confess our sins, he is faithful and just and will forgive us our sins.", reason: "Confession leads to freedom", themes: ["guilt", "forgiveness", "confession"]),
        ],
        .overwhelm: [
            ScriptureRecommendation(reference: "Matthew 11:28-30", text: "Come to me, all you who are weary and burdened, and I will give you rest.", reason: "Jesus offers rest for the overwhelmed", themes: ["rest", "burden", "peace"]),
        ],
        .despair: [
            ScriptureRecommendation(reference: "Psalm 42:11", text: "Why, my soul, are you downcast? Put your hope in God, for I will yet praise him.", reason: "Even in despair, there is a path back to hope", themes: ["despair", "hope", "praise"]),
            ScriptureRecommendation(reference: "Lamentations 3:22-23", text: "Because of the LORD's great love we are not consumed, for his compassions never fail. They are new every morning.", reason: "Every morning is a fresh start with God", themes: ["despair", "mercy", "renewal"]),
        ],
        .anger: [
            ScriptureRecommendation(reference: "Ephesians 4:26-27", text: "In your anger do not sin. Do not let the sun go down while you are still angry.", reason: "Anger itself isn't sin — what you do with it matters", themes: ["anger", "self-control", "wisdom"]),
        ],
        .peace: [
            ScriptureRecommendation(reference: "John 14:27", text: "Peace I leave with you; my peace I give you. I do not give to you as the world gives.", reason: "Christ's peace transcends circumstances", themes: ["peace", "gift", "trust"]),
        ],
        .love: [
            ScriptureRecommendation(reference: "1 Corinthians 13:4-7", text: "Love is patient, love is kind. It does not envy, it does not boast.", reason: "The definition of love from God Himself", themes: ["love", "patience", "kindness"]),
        ],
        .confusion: [
            ScriptureRecommendation(reference: "Proverbs 3:5-6", text: "Trust in the LORD with all your heart and lean not on your own understanding.", reason: "When confused, lean on God's wisdom instead of your own", themes: ["confusion", "trust", "guidance"]),
        ],
        .frustration: [
            ScriptureRecommendation(reference: "Galatians 6:9", text: "Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up.", reason: "Persistence through frustration leads to breakthrough", themes: ["frustration", "perseverance", "harvest"]),
        ],
        .pride: [
            ScriptureRecommendation(reference: "Psalm 115:1", text: "Not to us, LORD, not to us but to your name be the glory.", reason: "Direct your achievements back to God", themes: ["pride", "glory", "humility"]),
        ],
        .jealousy: [
            ScriptureRecommendation(reference: "Galatians 6:4", text: "Each one should test their own actions. Then they can take pride in themselves alone, without comparing themselves to someone else.", reason: "Your journey is unique — comparison steals joy", themes: ["jealousy", "comparison", "identity"]),
        ],
    ]
}
