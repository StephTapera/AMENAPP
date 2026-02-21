//
//  AIContentDetectionService.swift
//  AMENAPP
//
//  P0 FIX: Detect AI-generated content (ChatGPT, Claude, etc.)
//  Multi-heuristic detection with confidence scoring
//

import Foundation

struct AIDetectionResult {
    let isLikelyAI: Bool
    let confidence: Double  // 0.0 to 1.0
    let reasons: [String]
    
    var likelihood: String {
        switch confidence {
        case 0.0..<0.3:
            return "Low"
        case 0.3..<0.5:
            return "Medium-Low"
        case 0.5..<0.7:
            return "Medium"
        case 0.7..<0.9:
            return "High"
        default:
            return "Very High"
        }
    }
}

@MainActor
class AIContentDetectionService {
    static let shared = AIContentDetectionService()
    
    private init() {}
    
    // MARK: - Detection Threshold
    
    private let detectionThreshold: Double = 0.5  // 50% confidence = flag as AI
    
    // MARK: - Main Detection Method
    
    /// Detect if text is likely AI-generated
    func detectAIContent(_ text: String) -> AIDetectionResult {
        var score: Double = 0.0
        var reasons: [String] = []
        
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanText.isEmpty else {
            return AIDetectionResult(isLikelyAI: false, confidence: 0.0, reasons: [])
        }
        
        // 1. Assistant-like phrases (20% weight)
        let (hasAssistantPhrases, assistantScore) = checkAssistantPhrases(cleanText)
        if hasAssistantPhrases {
            score += assistantScore * 0.20
            reasons.append("Contains AI assistant phrases")
        }
        
        // 2. Perfect formatting (15% weight)
        let (hasPerfectFormatting, formattingScore) = checkPerfectFormatting(cleanText)
        if hasPerfectFormatting {
            score += formattingScore * 0.15
            reasons.append("Unnaturally perfect formatting")
        }
        
        // 3. Overly formal tone (15% weight)
        let (isOverlyFormal, formalScore) = checkFormalTone(cleanText)
        if isOverlyFormal {
            score += formalScore * 0.15
            reasons.append("Overly formal tone for social media")
        }
        
        // 4. Unnatural length patterns (10% weight)
        let (hasUnnaturalLength, lengthScore) = checkUnnaturalLength(cleanText)
        if hasUnnaturalLength {
            score += lengthScore * 0.10
            reasons.append("Unusual length patterns")
        }
        
        // 5. Lack of personal voice (20% weight)
        let (lacksPersonalVoice, personalScore) = checkPersonalVoice(cleanText)
        if lacksPersonalVoice {
            score += personalScore * 0.20
            reasons.append("Lacks personal voice/emotion")
        }
        
        // 6. Perfect grammar/punctuation (10% weight)
        let (isPerfectGrammar, grammarScore) = checkPerfectGrammar(cleanText)
        if isPerfectGrammar {
            score += grammarScore * 0.10
            reasons.append("Suspiciously perfect grammar")
        }
        
        // 7. Generic motivational content (10% weight)
        let (isGenericMotivational, motivationalScore) = checkGenericMotivational(cleanText)
        if isGenericMotivational {
            score += motivationalScore * 0.10
            reasons.append("Generic motivational content")
        }
        
        let isLikelyAI = score >= detectionThreshold
        
        if isLikelyAI {
            print("🤖 [AI DETECT] Text flagged as AI (confidence: \(String(format: "%.1f", score * 100))%)")
            reasons.forEach { print("   - \($0)") }
        }
        
        return AIDetectionResult(
            isLikelyAI: isLikelyAI,
            confidence: score,
            reasons: reasons
        )
    }
    
    // MARK: - Detection Heuristics
    
    /// Check for AI assistant phrases
    private func checkAssistantPhrases(_ text: String) -> (Bool, Double) {
        let lowerText = text.lowercased()
        
        let assistantPhrases = [
            "here are", "here's a", "i'd be happy to", "let me break this down",
            "here's a comprehensive", "to summarize", "in summary",
            "it's important to note", "it's worth noting", "as an ai",
            "i don't have personal", "i can provide", "i can help",
            "certainly", "absolutely", "specifically speaking",
            "to be clear", "to clarify", "in other words",
            "from my perspective", "in my analysis", "based on",
            "it's crucial to", "key takeaways", "moving forward"
        ]
        
        var matchCount = 0
        for phrase in assistantPhrases {
            if lowerText.contains(phrase) {
                matchCount += 1
            }
        }
        
        let score = min(1.0, Double(matchCount) / 3.0)  // 3+ matches = max score
        return (matchCount > 0, score)
    }
    
    /// Check for unnaturally perfect formatting
    private func checkPerfectFormatting(_ text: String) -> (Bool, Double) {
        // Count numbered lists, bullet points, and section headers
        let numberListPattern = #"(?:^|\n)[\d]+\."#
        let bulletPattern = #"(?:^|\n)[•\-\*]"#
        let headerPattern = #"(?:^|\n)#{1,6}\s"#
        
        var formattingCount = 0
        
        if text.range(of: numberListPattern, options: .regularExpression) != nil {
            formattingCount += 1
        }
        if text.range(of: bulletPattern, options: .regularExpression) != nil {
            formattingCount += 1
        }
        if text.range(of: headerPattern, options: .regularExpression) != nil {
            formattingCount += 1
        }
        
        // Check if text has multiple well-formatted paragraphs
        let paragraphs = text.components(separatedBy: "\n\n")
        if paragraphs.count >= 3 {
            formattingCount += 1
        }
        
        let score = min(1.0, Double(formattingCount) / 3.0)
        return (formattingCount >= 2, score)
    }
    
    /// Check for overly formal tone
    private func checkFormalTone(_ text: String) -> (Bool, Double) {
        let lowerText = text.lowercased()
        
        let formalWords = [
            "furthermore", "moreover", "additionally", "consequently",
            "thus", "therefore", "hence", "whereby", "wherein",
            "notwithstanding", "nevertheless", "nonetheless",
            "facilitate", "utilize", "implement", "execute", "demonstrate"
        ]
        
        var formalCount = 0
        for word in formalWords {
            if lowerText.contains(word) {
                formalCount += 1
            }
        }
        
        let score = min(1.0, Double(formalCount) / 3.0)
        return (formalCount >= 2, score)
    }
    
    /// Check for unnatural length (too short or suspiciously perfect length)
    private func checkUnnaturalLength(_ text: String) -> (Bool, Double) {
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).count
        
        // Suspiciously perfect paragraph lengths (exactly 100, 200, 300 words)
        let isPerfectLength = wordCount % 100 == 0 && wordCount >= 100
        
        // Unusually long for social media (>500 words)
        let isTooLong = wordCount > 500
        
        if isPerfectLength || isTooLong {
            return (true, 0.8)
        }
        
        return (false, 0.0)
    }
    
    /// Check for lack of personal voice
    private func checkPersonalVoice(_ text: String) -> (Bool, Double) {
        let lowerText = text.lowercased()
        
        // Check for personal indicators
        let personalIndicators = ["i'm", "i've", "my", "lol", "haha", "omg", "tbh", "imo", "literally"]
        let hasPersonalVoice = personalIndicators.contains { lowerText.contains($0) }
        
        // Check for emotional punctuation
        let hasEmotionalPunctuation = text.contains("!") || text.contains("?!") || text.contains("...")
        
        // Check for contractions
        let hasContractions = text.range(of: #"\b\w+'[a-z]+"#, options: .regularExpression) != nil
        
        let personalityScore = [hasPersonalVoice, hasEmotionalPunctuation, hasContractions].filter { $0 }.count
        
        // Lack of personality = high score
        let score = 1.0 - (Double(personalityScore) / 3.0)
        return (personalityScore == 0, score)
    }
    
    /// Check for suspiciously perfect grammar
    private func checkPerfectGrammar(_ text: String) -> (Bool, Double) {
        // Check sentence structure consistency
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if sentences.isEmpty {
            return (false, 0.0)
        }
        
        // Count sentences starting with capital letters
        let properSentences = sentences.filter { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.first?.isUppercase == true
        }
        
        let perfectionRatio = Double(properSentences.count) / Double(sentences.count)
        
        // 100% proper capitalization = suspicious for social media
        let isPerfect = perfectionRatio == 1.0 && sentences.count >= 3
        return (isPerfect, perfectionRatio)
    }
    
    /// Check for generic motivational content
    private func checkGenericMotivational(_ text: String) -> (Bool, Double) {
        let lowerText = text.lowercased()
        
        let motivationalPhrases = [
            "believe in yourself", "stay positive", "never give up",
            "chase your dreams", "follow your heart", "be the change",
            "live your best life", "you got this", "stay strong",
            "keep pushing", "the sky's the limit", "anything is possible"
        ]
        
        var matchCount = 0
        for phrase in motivationalPhrases {
            if lowerText.contains(phrase) {
                matchCount += 1
            }
        }
        
        let score = min(1.0, Double(matchCount) / 2.0)
        return (matchCount >= 1, score)
    }
}
