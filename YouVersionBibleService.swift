//
//  YouVersionBibleService.swift
//  AMENAPP
//
//  YouVersion Bible API integration for cost-effective Scripture fetching.
//  Replaces AI-generated verse content with real Bible data.
//

import Foundation
import Combine

// MARK: - YouVersion Bible Service

@MainActor
class YouVersionBibleService: ObservableObject {
    static let shared = YouVersionBibleService()
    
    private let apiKey: String = BundleConfig.string(forKey: "YOUVERSION_API_KEY") ?? ""
    private let baseURL = "https://api.scripture.api.bible/v1"
    
    @Published var isLoading = false
    
    // Cache for fetched verses
    private var verseCache: [String: YouVersionVerse] = [:]
    
    private init() {}
    
    // MARK: - Fetch Scripture
    
    /// Fetch verse from YouVersion API
    func fetchVerse(reference: String, version: ScripturePassage.BibleVersion = .esv) async throws -> ScripturePassage {
        dlog("📖 YouVersion: Fetching \(reference) (\(version.rawValue))...")
        
        // Check cache first
        let cacheKey = "\(reference)_\(version.rawValue)"
        if let cached = verseCache[cacheKey] {
            return convertToScripturePassage(cached, reference: reference, version: version)
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Parse reference (e.g., "John 3:16" or "John 3:16-17")
        guard let parsedRef = parseReference(reference) else {
            throw YouVersionError.invalidReference
        }
        
        // Get Bible version ID
        let bibleId = getBibleId(for: version)
        
        // Build URL
        let verseId = buildVerseId(parsedRef)
        let urlString = "\(baseURL)/bibles/\(bibleId)/verses/\(verseId)"
        
        guard let url = URL(string: urlString) else {
            throw YouVersionError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Fetch
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YouVersionError.apiError
        }
        
        // Parse response
        let decoder = JSONDecoder()
        let youVersionResponse = try decoder.decode(YouVersionResponse.self, from: data)
        
        // Cache result
        verseCache[cacheKey] = youVersionResponse.data
        
        // Convert to ScripturePassage
        let passage = convertToScripturePassage(youVersionResponse.data, reference: reference, version: version)
        
        dlog("✅ YouVersion: Fetched \(reference)")
        return passage
    }
    
    /// Fetch multiple verses in parallel for faster response
    func fetchVerses(references: [String], version: ScripturePassage.BibleVersion = .esv) async throws -> [ScripturePassage] {
        guard !references.isEmpty else { return [] }
        
        // Deduplicate references before fetching
        let uniqueRefs = Array(NSOrderedSet(array: references)) as? [String] ?? references
        
        // Fetch all verses in parallel using a task group
        return await withTaskGroup(of: (Int, ScripturePassage?).self) { group in
            for (index, reference) in uniqueRefs.enumerated() {
                group.addTask {
                    do {
                        let passage = try await self.fetchVerse(reference: reference, version: version)
                        return (index, passage)
                    } catch {
                        dlog("⚠️ YouVersion: Failed to fetch \(reference): \(error)")
                        return (index, nil)
                    }
                }
            }
            
            // Collect results, preserving order
            var indexed: [(Int, ScripturePassage)] = []
            for await (index, passage) in group {
                if let passage = passage {
                    indexed.append((index, passage))
                }
            }
            return indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
    
    // MARK: - Reference Parsing
    
    private func parseReference(_ reference: String) -> ParsedReference? {
        // Pattern: "Book Chapter:Verse" or "Book Chapter:Verse-Verse"
        let pattern = "([1-3]?\\s?[A-Za-z]+)\\s+(\\d+):(\\d+)(?:-(\\d+))?"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsString = reference as NSString
        guard let match = regex.firstMatch(in: reference, options: [], range: NSRange(location: 0, length: nsString.length)),
              match.numberOfRanges >= 4 else {
            return nil
        }
        
        let book = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        guard let chapter = Int(nsString.substring(with: match.range(at: 2))),
              let startVerse = Int(nsString.substring(with: match.range(at: 3))) else {
            return nil
        }
        
        var endVerse: Int?
        if match.numberOfRanges >= 5 && match.range(at: 4).location != NSNotFound {
            endVerse = Int(nsString.substring(with: match.range(at: 4)))
        }
        
        return ParsedReference(
            book: normalizeBookName(book),
            chapter: chapter,
            startVerse: startVerse,
            endVerse: endVerse
        )
    }
    
    private func normalizeBookName(_ book: String) -> String {
        // Map common variations to standard names
        let bookMap: [String: String] = [
            "1 john": "1JN",
            "2 john": "2JN",
            "3 john": "3JN",
            "1 peter": "1PE",
            "2 peter": "2PE",
            "1 corinthians": "1CO",
            "2 corinthians": "2CO",
            "john": "JHN",
            "genesis": "GEN",
            "exodus": "EXO",
            "matthew": "MAT",
            "mark": "MRK",
            "luke": "LUK",
            "romans": "ROM",
            "psalms": "PSA",
            "proverbs": "PRO",
            "isaiah": "ISA",
            "jeremiah": "JER",
            "acts": "ACT",
            "revelation": "REV"
        ]
        
        let normalized = book.lowercased()
        return bookMap[normalized] ?? book.uppercased().prefix(3).description
    }
    
    private func buildVerseId(_ ref: ParsedReference) -> String {
        // YouVersion format: BOOK.CHAPTER.VERSE or BOOK.CHAPTER.VERSE-BOOK.CHAPTER.VERSE
        if let endVerse = ref.endVerse {
            return "\(ref.book).\(ref.chapter).\(ref.startVerse)-\(ref.book).\(ref.chapter).\(endVerse)"
        } else {
            return "\(ref.book).\(ref.chapter).\(ref.startVerse)"
        }
    }
    
    private func getBibleId(for version: ScripturePassage.BibleVersion) -> String {
        // Official API.Bible (scripture.api.bible) Bible IDs.
        // Verify / update at https://scripture.api.bible/livedocs#/Bibles/getBibles
        switch version {
        case .esv:
            return "de4e12af7f28f599-02" // English Standard Version (2016)
        case .niv:
            return "78a9f6124f344018-01" // New International Version
        case .kjv:
            return "de4e12af7f28f599-01" // King James Version (with Apocrypha)
        case .nkjv:
            return "55ec70d2c5bbcafa-01" // New King James Version
        case .nlt:
            return "65eec8e0b60e656b-01" // New Living Translation
        case .nasb:
            return "f7d2a1cce62e12e0-01" // New American Standard Bible (1995)
        }
    }
    
    // MARK: - Conversion
    
    private func convertToScripturePassage(
        _ verse: YouVersionVerse,
        reference: String,
        version: ScripturePassage.BibleVersion
    ) -> ScripturePassage {
        // Parse the reference to get book, chapter, verses
        guard let parsed = parseReference(reference) else {
            return ScripturePassage(
                id: UUID().uuidString,
                book: "Unknown",
                chapter: 0,
                verses: "0",
                text: verse.content,
                version: version
            )
        }
        
        let verseRange = if let endVerse = parsed.endVerse {
            "\(parsed.startVerse)-\(endVerse)"
        } else {
            "\(parsed.startVerse)"
        }
        
        return ScripturePassage(
            id: verse.id,
            book: parsed.book,
            chapter: parsed.chapter,
            verses: verseRange,
            text: verse.content,
            version: version
        )
    }
    
    // MARK: - Search
    
    /// Search for verses containing keywords
    func searchVerses(query: String, version: ScripturePassage.BibleVersion = .esv, limit: Int = 10) async throws -> [ScripturePassage] {
        dlog("🔍 YouVersion: Searching '\(query)'...")
        
        let bibleId = getBibleId(for: version)
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/bibles/\(bibleId)/search?query=\(encodedQuery)&limit=\(limit)"
        
        guard let url = URL(string: urlString) else {
            throw YouVersionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YouVersionError.apiError
        }
        
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(YouVersionSearchResponse.self, from: data)
        
        // Convert to ScripturePassages
        return searchResponse.data.verses.compactMap { verse in
            // Extract reference from verse
            guard let reference = verse.reference else { return nil }
            return convertToScripturePassage(verse, reference: reference, version: version)
        }
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        verseCache.removeAll()
        dlog("🧹 YouVersion: Cache cleared")
    }
    
    func getCacheSize() -> Int {
        return verseCache.count
    }
}

// MARK: - Models

struct ParsedReference {
    let book: String
    let chapter: Int
    let startVerse: Int
    let endVerse: Int?
}

struct YouVersionResponse: Codable {
    let data: YouVersionVerse
}

struct YouVersionVerse: Codable {
    let id: String
    let content: String
    let reference: String?
    let verseCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case reference
        case verseCount
    }
}

struct YouVersionSearchResponse: Codable {
    let data: YouVersionSearchData
}

struct YouVersionSearchData: Codable {
    let verses: [YouVersionVerse]
    let total: Int?
}

enum YouVersionError: Error {
    case invalidReference
    case invalidURL
    case apiError
    case parsingError
    
    var localizedDescription: String {
        switch self {
        case .invalidReference:
            return "Invalid Bible reference format"
        case .invalidURL:
            return "Invalid API URL"
        case .apiError:
            return "YouVersion API error"
        case .parsingError:
            return "Failed to parse response"
        }
    }
}

// MARK: - Bible Version Extension

extension ScripturePassage.BibleVersion {
    var youVersionId: String {
        switch self {
        case .esv:  return "de4e12af7f28f599-02"
        case .niv:  return "78a9f6124f344018-01"
        case .kjv:  return "de4e12af7f28f599-01"
        case .nkjv: return "55ec70d2c5bbcafa-01"
        case .nlt:  return "65eec8e0b60e656b-01"
        case .nasb: return "f7d2a1cce62e12e0-01"
        }
    }
}
