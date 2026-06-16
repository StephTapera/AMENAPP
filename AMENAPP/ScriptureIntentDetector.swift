//
//  ScriptureIntentDetector.swift
//  AMENAPP
//
//  Detects scripture intent from draft text using local rule-based
//  phrase matching, reference detection, and theme inference.
//  Designed for speed — all local, no network calls.
//

import Foundation

struct BereanScriptureChip: Equatable {
    let reference: String
    let text: String
    let translation: String
}

struct ScriptureIntentResult {
    let verse: BereanScriptureChip
    let confidence: Double   // 0.0 - 1.0
    let reason: String       // e.g. "Suggested from your draft"
    let matchType: MatchType

    enum MatchType {
        case exactPhrase
        case referenceTyped
        case themeInference
    }
}

@MainActor
final class ScriptureIntentDetector {
    
    // MARK: - Known Biblical Phrases → Verse Mappings
    
    // TODO(legal): All verse texts replaced with KJV (public domain) per AMEN-CONTENT-001.
    // NIV (Biblica) texts removed — copyrighted without license.
    private let phraseMap: [(phrases: [String], reference: String, text: String, translation: String)] = [
        (["be still", "be still and know"], "Psalm 46:10",
         "Be still, and know that I am God: I will be exalted among the heathen, I will be exalted in the earth.", "KJV"),
        
        (["i can do all things", "all things through christ", "i can do all things through"], "Philippians 4:13",
         "I can do all things through Christ which strengtheneth me.", "KJV"),
        
        (["the lord is my shepherd", "lord is my shepherd"], "Psalm 23:1",
         "The Lord is my shepherd; I shall not want.", "KJV"),
        
        (["for god so loved", "god so loved the world"], "John 3:16",
         "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.", "KJV"),
        
        (["plans to prosper", "plans for you", "plans i have for you", "hope and a future"], "Jeremiah 29:11",
         "For I know the thoughts that I think toward you, saith the Lord, thoughts of peace, and not of evil, to give you an expected end.", "KJV"),
        
        (["trust in the lord", "lean not on your own", "lean not"], "Proverbs 3:5-6",
         "Trust in the Lord with all thine heart; and lean not unto thine own understanding. In all thy ways acknowledge him, and he shall direct thy paths.", "KJV"),
        
        (["all things work together", "work together for good", "in all things god works"], "Romans 8:28",
         "And we know that all things work together for good to them that love God, to them who are the called according to his purpose.", "KJV"),
        
        (["the joy of the lord", "joy of the lord is my strength"], "Nehemiah 8:10",
         "Then he said unto them, Go your way, eat the fat, and drink the sweet, and send portions unto them for whom nothing is prepared: for this day is holy unto our Lord: neither be ye sorry; for the joy of the Lord is your strength.", "KJV"),
        
        (["love is patient", "love is kind"], "1 Corinthians 13:4",
         "Charity suffereth long, and is kind; charity envieth not; charity vaunteth not itself, is not puffed up.", "KJV"),
        
        (["do not be anxious", "do not worry", "be anxious for nothing"], "Philippians 4:6",
         "Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God.", "KJV"),
        
        (["fear not", "do not fear", "i am with you", "do not be afraid"], "Isaiah 41:10",
         "Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee; yea, I will help thee; yea, I will uphold thee with the right hand of my righteousness.", "KJV"),
        
        (["the lord bless you", "bless you and keep you"], "Numbers 6:24",
         "The Lord bless thee, and keep thee.", "KJV"),
        
        (["new creation", "new creature", "old has gone"], "2 Corinthians 5:17",
         "Therefore if any man be in Christ, he is a new creature: old things are passed away; behold, all things are become new.", "KJV"),
        
        (["i am the way", "way truth and life", "way the truth"], "John 14:6",
         "Jesus saith unto him, I am the way, the truth, and the life: no man cometh unto the Father, but by me.", "KJV"),
        
        (["greater is he", "greater is he that is in you"], "1 John 4:4",
         "Ye are of God, little children, and have overcome them: because greater is he that is in you, than he that is in the world.", "KJV"),
        
        (["no weapon formed", "no weapon"], "Isaiah 54:17",
         "No weapon that is formed against thee shall prosper; and every tongue that shall rise against thee in judgment thou shalt condemn.", "KJV"),
        
        (["this is the day", "day the lord has made"], "Psalm 118:24",
         "This is the day which the Lord hath made; we will rejoice and be glad in it.", "KJV"),
        
        (["seek first", "seek first the kingdom", "seek ye first"], "Matthew 6:33",
         "But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you.", "KJV"),
        
        (["by grace you have been saved", "by grace through faith"], "Ephesians 2:8",
         "For by grace are ye saved through faith; and that not of yourselves: it is the gift of God.", "KJV"),
        
        (["consider it pure joy", "consider it joy", "count it all joy"], "James 1:2",
         "My brethren, count it all joy when ye fall into divers temptations.", "KJV"),
    ]
    
    // MARK: - Theme → Verse Mappings
    
    // TODO(legal): All verse texts replaced with KJV (public domain) per AMEN-CONTENT-001.
    // NIV (Biblica) texts removed — copyrighted without license.
    private let themeMap: [(keywords: [String], reference: String, text: String, translation: String, label: String)] = [
        (["anxiety", "anxious", "worried", "stress", "stressed", "overwhelmed"],
         "Philippians 4:6-7",
         "Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God. And the peace of God, which passeth all understanding, shall keep your hearts and minds through Christ Jesus.",
         "KJV", "Related to peace"),
        
        (["thankful", "grateful", "gratitude", "thanksgiving", "blessed", "blessings"],
         "1 Thessalonians 5:18",
         "In every thing give thanks: for this is the will of God in Christ Jesus concerning you.",
         "KJV", "Related to gratitude"),
        
        (["strength", "strong", "endure", "persevere", "hardship", "struggle"],
         "Isaiah 40:31",
         "But they that wait upon the Lord shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.",
         "KJV", "Related to strength"),
        
        (["forgive", "forgiveness", "forgiven", "letting go", "grudge"],
         "Colossians 3:13",
         "Forbearing one another, and forgiving one another, if any man have a quarrel against any: even as Christ forgave you, so also do ye.",
         "KJV", "Related to forgiveness"),
        
        (["lonely", "alone", "isolation", "abandoned"],
         "Deuteronomy 31:6",
         "Be strong and of a good courage, fear not, nor be afraid of them: for the Lord thy God, he it is that doth go with thee; he will not fail thee, nor forsake thee.",
         "KJV", "Related to God's presence"),
        
        (["waiting", "patience", "patient", "waiting on god"],
         "Psalm 27:14",
         "Wait on the Lord: be of good courage, and he shall strengthen thine heart: wait, I say, on the Lord.",
         "KJV", "Related to patience"),
        
        (["healing", "heal", "sick", "illness", "recovery", "pain"],
         "Jeremiah 17:14",
         "Heal me, O Lord, and I shall be healed; save me, and I shall be saved: for thou art my praise.",
         "KJV", "Related to healing"),
        
        (["grief", "loss", "mourn", "mourning", "death", "passed away"],
         "Psalm 34:18",
         "The Lord is nigh unto them that are of a broken heart; and saveth such as be of a contrite spirit.",
         "KJV", "Related to comfort"),
        
        (["wisdom", "decision", "discernment", "guidance", "direction"],
         "James 1:5",
         "If any of you lack wisdom, let him ask of God, that giveth to all men liberally, and upbraideth not; and it shall be given him.",
         "KJV", "Related to wisdom"),
        
        (["praise", "worship", "glorify", "exalt", "sing"],
         "Psalm 150:6",
         "Let every thing that hath breath praise the Lord. Praise ye the Lord.",
         "KJV", "Related to praise"),
        
        (["new beginning", "fresh start", "new season", "new chapter"],
         "Isaiah 43:19",
         "Behold, I will do a new thing; now it shall spring forth; shall ye not know it? I will even make a way in the wilderness, and rivers in the desert.",
         "KJV", "Related to new beginnings"),
        
        (["purpose", "calling", "destiny", "mission"],
         "Ephesians 2:10",
         "For we are his workmanship, created in Christ Jesus unto good works, which God hath before ordained that we should walk in them.",
         "KJV", "Related to purpose"),
    ]
    
    // MARK: - Reference Pattern
    
    private static let referencePattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"[1-3]?\s?[A-Za-z]+\.?\s+\d+:\d+(?:\s?[-–]\s?\d+)?"#
        )
    }()
    
    // MARK: - Detection
    
    func detect(in text: String) -> ScriptureIntentResult {
        let lowered = text.lowercased()
        
        // 1. Check for exact biblical phrase match (highest confidence)
        for entry in phraseMap {
            for phrase in entry.phrases {
                if lowered.contains(phrase) {
                    return ScriptureIntentResult(
                        verse: BereanScriptureChip(reference: entry.reference, text: entry.text, translation: entry.translation),
                        confidence: 0.95,
                        reason: "Suggested from your draft",
                        matchType: .exactPhrase
                    )
                }
            }
        }
        
        // 2. Check for typed reference pattern (high confidence)
        let range = NSRange(text.startIndex..., in: text)
        if let match = Self.referencePattern?.firstMatch(in: text, range: range),
           let swiftRange = Range(match.range, in: text) {
            let ref = String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
            return ScriptureIntentResult(
                verse: BereanScriptureChip(reference: ref, text: "", translation: "KJV"), // TODO(legal): was NIV (Biblica, copyrighted) — changed to KJV (public domain) per AMEN-CONTENT-001
                confidence: 0.9,
                reason: "Reference detected",
                matchType: .referenceTyped
            )
        }
        
        // 3. Theme inference (moderate confidence)
        var bestMatch: (entry: (keywords: [String], reference: String, text: String, translation: String, label: String), score: Int)?
        
        for entry in themeMap {
            var score = 0
            for keyword in entry.keywords {
                if lowered.contains(keyword) {
                    score += 1
                }
            }
            if score > 0 {
                if score > (bestMatch?.score ?? 0) {
                    bestMatch = (entry, score)
                }
            }
        }
        
        if let best = bestMatch {
            let confidence = min(Double(best.score) * 0.35, 0.85)
            return ScriptureIntentResult(
                verse: BereanScriptureChip(reference: best.entry.reference, text: best.entry.text, translation: best.entry.translation),
                confidence: confidence,
                reason: best.entry.label,
                matchType: .themeInference
            )
        }
        
        // No match
        return ScriptureIntentResult(
            verse: BereanScriptureChip(reference: "", text: "", translation: ""),
            confidence: 0,
            reason: "",
            matchType: .themeInference
        )
    }
}
