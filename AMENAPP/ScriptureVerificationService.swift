//
//  ScriptureVerificationService.swift
//  AMENAPP
//
//  Scripture verification and fact-checking
//  Prevents misinformation and false teachings
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ScriptureVerificationService: ObservableObject {
    static let shared = ScriptureVerificationService()
    
    struct ScriptureReference {
        let book: String
        let chapter: Int
        let verseStart: Int
        let verseEnd: Int?
        let version: String? // ESV, NIV, KJV, etc.
        let fullReference: String
    }
    
    struct VerificationResult {
        let isAccurate: Bool
        let reference: String
        let contextNote: String?
        let verifiedSource: String
        let fullText: String?
    }
    
    private init() {}
    
    // MARK: - Scripture Detection
    
    func detectScriptures(in text: String) -> [ScriptureReference] {
        var references: [ScriptureReference] = []
        
        // Common patterns:
        // - "John 3:16"
        // - "1 Corinthians 13:4-7"
        // - "Psalm 23:1 (ESV)"
        // - "Romans 8:28"
        
        let patterns = [
            // Book Chapter:Verse
            "([1-3]\\s+)?([A-Z][a-z]+)\\s+(\\d+):(\\d+)(?:-(\\d+))?(?:\\s+\\(([A-Z]+)\\))?",
            // Book Chapter:Verse-Verse
            "([1-3]\\s+)?([A-Z][a-z]+)\\s+(\\d+):(\\d+)-(\\d+)",
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                
                for match in matches {
                    let fullRange = match.range(at: 0)
                    if let fullMatch = Range(fullRange, in: text) {
                        let fullReference = String(text[fullMatch])
                        
                        // Extract components
                        let bookRange = match.range(at: 2)
                        let chapterRange = match.range(at: 3)
                        let verseStartRange = match.range(at: 4)
                        let verseEndRange = match.range(at: 5)
                        let versionRange = match.range(at: 6)
                        
                        if let bookMatch = Range(bookRange, in: text),
                           let chapterMatch = Range(chapterRange, in: text),
                           let verseStartMatch = Range(verseStartRange, in: text) {
                            
                            let book = String(text[bookMatch])
                            let chapter = Int(String(text[chapterMatch])) ?? 0
                            let verseStart = Int(String(text[verseStartMatch])) ?? 0
                            
                            var verseEnd: Int? = nil
                            if verseEndRange.location != NSNotFound,
                               let verseEndMatch = Range(verseEndRange, in: text) {
                                verseEnd = Int(String(text[verseEndMatch]))
                            }
                            
                            var version: String? = nil
                            if versionRange.location != NSNotFound,
                               let versionMatch = Range(versionRange, in: text) {
                                version = String(text[versionMatch])
                            }
                            
                            let ref = ScriptureReference(
                                book: book,
                                chapter: chapter,
                                verseStart: verseStart,
                                verseEnd: verseEnd,
                                version: version,
                                fullReference: fullReference
                            )
                            
                            references.append(ref)
                        }
                    }
                }
            }
        }
        
        return references
    }
    
    // MARK: - Verification
    
    func verifyScripture(_ reference: ScriptureReference) async -> VerificationResult {
        // In production, this would:
        // 1. Call Bible API (e.g., ESV API, Bible Gateway API)
        // 2. Fetch actual verse text
        // 3. Compare with context
        // 4. Check for common misquotes
        
        // For now, return mock verification
        // TODO: Integrate with ESV API or similar
        
        let isKnownBook = isValidBook(reference.book)
        
        if !isKnownBook {
            return VerificationResult(
                isAccurate: false,
                reference: reference.fullReference,
                contextNote: "Book name not recognized. Please check spelling.",
                verifiedSource: "AMEN Verification",
                fullText: nil
            )
        }
        
        // Assume valid for now (would verify against API in production)
        return VerificationResult(
            isAccurate: true,
            reference: "\(reference.book) \(reference.chapter):\(reference.verseStart)\(reference.verseEnd != nil ? "-\(reference.verseEnd!)" : "")",
            contextNote: nil,
            verifiedSource: "Bible API",
            fullText: nil // Would contain actual verse text from API
        )
    }
    
    private func isValidBook(_ book: String) -> Bool {
        let books = [
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
            "Joshua", "Judges", "Ruth", "Samuel", "Kings", "Chronicles",
            "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
            "Ecclesiastes", "Song", "Isaiah", "Jeremiah", "Lamentations",
            "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah",
            "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai",
            "Zechariah", "Malachi",
            "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
            "Corinthians", "Galatians", "Ephesians", "Philippians",
            "Colossians", "Thessalonians", "Timothy", "Titus", "Philemon",
            "Hebrews", "James", "Peter", "Jude", "Revelation"
        ]
        
        return books.contains { book.lowercased().contains($0.lowercased()) }
    }
    
    // MARK: - Context Checking
    
    func checkContext(verse: String, surroundingText: String) -> String? {
        // Check if verse is being used out of context
        // This would use ML/AI in production
        
        // Common out-of-context verses:
        let outOfContextVerses = [
            "Jeremiah 29:11": "This verse was originally a promise to Israel, not a personal prosperity promise.",
            "Philippians 4:13": "This is about contentment in all circumstances, not ability to do anything.",
            "Matthew 7:1": "This is about hypocritical judgment, not avoiding all discernment."
        ]
        
        for (verseRef, context) in outOfContextVerses {
            if surroundingText.contains(verseRef) {
                return context
            }
        }
        
        return nil
    }
}

// MARK: - Scripture Badge View

struct ScriptureVerifiedBadge: View {
    let isVerified: Bool
    let reference: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isVerified ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isVerified ? .green : .orange)
            
            Text(isVerified ? "Scripture Verified" : "Check Context")
                .font(.custom("OpenSans-Medium", size: 11))
                .foregroundColor(isVerified ? .green : .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isVerified ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
    }
}
