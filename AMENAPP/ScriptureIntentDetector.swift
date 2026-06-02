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
    
    private let phraseMap: [(phrases: [String], reference: String, text: String, translation: String)] = [
        (["be still", "be still and know"], "Psalm 46:10",
         "Be still, and know that I am God; I will be exalted among the nations, I will be exalted in the earth.", "NIV"),
        
        (["i can do all things", "all things through christ", "i can do all things through"], "Philippians 4:13",
         "I can do all this through him who gives me strength.", "NIV"),
        
        (["the lord is my shepherd", "lord is my shepherd"], "Psalm 23:1",
         "The Lord is my shepherd, I lack nothing.", "NIV"),
        
        (["for god so loved", "god so loved the world"], "John 3:16",
         "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.", "NIV"),
        
        (["plans to prosper", "plans for you", "plans i have for you", "hope and a future"], "Jeremiah 29:11",
         "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.", "NIV"),
        
        (["trust in the lord", "lean not on your own", "lean not"], "Proverbs 3:5-6",
         "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.", "NIV"),
        
        (["all things work together", "work together for good", "in all things god works"], "Romans 8:28",
         "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.", "NIV"),
        
        (["the joy of the lord", "joy of the lord is my strength"], "Nehemiah 8:10",
         "Do not grieve, for the joy of the Lord is your strength.", "NIV"),
        
        (["love is patient", "love is kind"], "1 Corinthians 13:4",
         "Love is patient, love is kind. It does not envy, it does not boast, it is not proud.", "NIV"),
        
        (["do not be anxious", "do not worry", "be anxious for nothing"], "Philippians 4:6",
         "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.", "NIV"),
        
        (["fear not", "do not fear", "i am with you", "do not be afraid"], "Isaiah 41:10",
         "So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand.", "NIV"),
        
        (["the lord bless you", "bless you and keep you"], "Numbers 6:24",
         "The Lord bless you and keep you.", "NIV"),
        
        (["new creation", "new creature", "old has gone"], "2 Corinthians 5:17",
         "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!", "NIV"),
        
        (["i am the way", "way truth and life", "way the truth"], "John 14:6",
         "Jesus answered, I am the way and the truth and the life. No one comes to the Father except through me.", "NIV"),
        
        (["greater is he", "greater is he that is in you"], "1 John 4:4",
         "You, dear children, are from God and have overcome them, because the one who is in you is greater than the one who is in the world.", "NIV"),
        
        (["no weapon formed", "no weapon"], "Isaiah 54:17",
         "No weapon forged against you will prevail, and you will refute every tongue that accuses you.", "NIV"),
        
        (["this is the day", "day the lord has made"], "Psalm 118:24",
         "The Lord has done it this very day; let us rejoice today and be glad.", "NIV"),
        
        (["seek first", "seek first the kingdom", "seek ye first"], "Matthew 6:33",
         "But seek first his kingdom and his righteousness, and all these things will be given to you as well.", "NIV"),
        
        (["by grace you have been saved", "by grace through faith"], "Ephesians 2:8",
         "For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God.", "NIV"),
        
        (["consider it pure joy", "consider it joy", "count it all joy"], "James 1:2",
         "Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds.", "NIV"),
    ]
    
    // MARK: - Theme → Verse Mappings
    
    private let themeMap: [(keywords: [String], reference: String, text: String, translation: String, label: String)] = [
        (["anxiety", "anxious", "worried", "stress", "stressed", "overwhelmed"],
         "Philippians 4:6-7",
         "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
         "NIV", "Related to peace"),
        
        (["thankful", "grateful", "gratitude", "thanksgiving", "blessed", "blessings"],
         "1 Thessalonians 5:18",
         "Give thanks in all circumstances; for this is God's will for you in Christ Jesus.",
         "NIV", "Related to gratitude"),
        
        (["strength", "strong", "endure", "persevere", "hardship", "struggle"],
         "Isaiah 40:31",
         "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.",
         "NIV", "Related to strength"),
        
        (["forgive", "forgiveness", "forgiven", "letting go", "grudge"],
         "Colossians 3:13",
         "Bear with each other and forgive one another if any of you has a grievance against someone. Forgive as the Lord forgave you.",
         "NIV", "Related to forgiveness"),
        
        (["lonely", "alone", "isolation", "abandoned"],
         "Deuteronomy 31:6",
         "Be strong and courageous. Do not be afraid or terrified because of them, for the Lord your God goes with you; he will never leave you nor forsake you.",
         "NIV", "Related to God's presence"),
        
        (["waiting", "patience", "patient", "waiting on god"],
         "Psalm 27:14",
         "Wait for the Lord; be strong and take heart and wait for the Lord.",
         "NIV", "Related to patience"),
        
        (["healing", "heal", "sick", "illness", "recovery", "pain"],
         "Jeremiah 17:14",
         "Heal me, Lord, and I will be healed; save me and I will be saved, for you are the one I praise.",
         "NIV", "Related to healing"),
        
        (["grief", "loss", "mourn", "mourning", "death", "passed away"],
         "Psalm 34:18",
         "The Lord is close to the brokenhearted and saves those who are crushed in spirit.",
         "NIV", "Related to comfort"),
        
        (["wisdom", "decision", "discernment", "guidance", "direction"],
         "James 1:5",
         "If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.",
         "NIV", "Related to wisdom"),
        
        (["praise", "worship", "glorify", "exalt", "sing"],
         "Psalm 150:6",
         "Let everything that has breath praise the Lord. Praise the Lord.",
         "NIV", "Related to praise"),
        
        (["new beginning", "fresh start", "new season", "new chapter"],
         "Isaiah 43:19",
         "See, I am doing a new thing! Now it springs up; do you not perceive it? I am making a way in the wilderness and streams in the wasteland.",
         "NIV", "Related to new beginnings"),
        
        (["purpose", "calling", "destiny", "mission"],
         "Ephesians 2:10",
         "For we are God's handiwork, created in Christ Jesus to do good works, which God prepared in advance for us to do.",
         "NIV", "Related to purpose"),
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
                verse: BereanScriptureChip(reference: ref, text: "", translation: "NIV"),
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
                if bestMatch == nil || score > bestMatch!.score {
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
