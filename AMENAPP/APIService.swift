//
//  APIService.swift
//  AMENAPP
//
//  API Integration Guide and Service Layer
//

import Foundation
import Combine

// MARK: - API Service Protocol

protocol APIServiceProtocol {
    func fetch<T: Decodable>(endpoint: String, type: T.Type) async throws -> T
}

// MARK: - Main API Service

class APIService: APIServiceProtocol {
    static let shared = APIService()
    
    private let baseURL = "https://api.yourdomain.com/v1"
    private let session: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }
    
    func fetch<T: Decodable>(endpoint: String, type: T.Type) async throws -> T {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication if needed
        // request.addValue("Bearer YOUR_TOKEN", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP Error: \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Bible API Service (YouVersion/Bible.org API)

/*
 ⚠️ IMPORTANT: YouVersion API Access
 
 YouVersion (Bible.com) does NOT have a public API available to third-party developers.
 They do not offer API access for their app data.
 
 Instead, use these alternatives:
 
 1. **ESV API** (Crossway) - https://api.esv.org
    - Free tier available
    - Great for ESV Bible text
    - Requires API key
 
 2. **Bible.org API** - https://bible.org/api
    - Multiple translations
    - Free access
 
 3. **Bible API** - https://bible-api.com
    - Simple, free, open source
    - Limited translations
 
 4. **API.Bible** (American Bible Society) - https://scripture.api.bible
    - Multiple translations
    - Free tier available
    - Requires API key
 */

class BibleAPIService {
    static let shared = BibleAPIService()
    
    // Example using Bible API (free, no auth required)
    private let baseURL = "https://bible-api.com"
    
    // MARK: - Get Verse of the Day
    
    func getVerseOfTheDay() async throws -> BibleVerse {
        // For demo: random popular verses
        let popularVerses = [
            "john 3:16",
            "philippians 4:13",
            "proverbs 3:5-6",
            "psalm 23:1",
            "romans 8:28",
            "jeremiah 29:11",
            "matthew 6:33",
            "2 timothy 1:7"
        ]
        
        let randomVerse = popularVerses.randomElement() ?? "john 3:16"
        return try await getVerse(reference: randomVerse)
    }
    
    // MARK: - Get Specific Verse
    
    func getVerse(reference: String) async throws -> BibleVerse {
        // Clean up reference (replace spaces with +)
        let cleanRef = reference.replacingOccurrences(of: " ", with: "+")
        
        guard let url = URL(string: "\(baseURL)/\(cleanRef)?translation=kjv") else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(BibleAPIResponse.self, from: data)
        return BibleVerse(
            text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines),
            reference: decoded.reference
        )
    }
}

// MARK: - ESV API Service (Premium Option)

class ESVAPIService {
    static let shared = ESVAPIService()
    
    private let baseURL = "https://api.esv.org/v3"
    private let apiKey = "YOUR_ESV_API_KEY_HERE" // Get from https://api.esv.org
    
    func getPassage(reference: String) async throws -> BibleVerse {
        guard let url = URL(string: "\(baseURL)/passage/text/?q=\(reference)&include-headings=false&include-footnotes=false&include-verse-numbers=false&include-short-copyright=false") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(ESVAPIResponse.self, from: data)
        return BibleVerse(
            text: decoded.passages.first ?? "",
            reference: reference
        )
    }
}

// MARK: - API.Bible Service (American Bible Society)

/*
 To use API.Bible:
 
 1. Sign up at https://scripture.api.bible
 2. Create an API key
 3. Replace YOUR_API_KEY below
 
 This gives you access to multiple Bible translations!
 */

class ScriptureAPIService {
    static let shared = ScriptureAPIService()
    
    private let baseURL = "https://api.scripture.api.bible/v1"
    private let apiKey = "YOUR_API_BIBLE_KEY_HERE"
    
    // Bible ID for KJV (you can find IDs for other translations in their docs)
    private let bibleID = "de4e12af7f28f599-02" // KJV
    
    func getVerse(bookId: String, chapter: Int, verse: Int) async throws -> BibleVerse {
        let verseId = "\(bookId).\(chapter).\(verse)"
        
        guard let url = URL(string: "\(baseURL)/bibles/\(bibleID)/verses/\(verseId)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "api-key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(ScriptureAPIResponse.self, from: data)
        return BibleVerse(
            text: decoded.data.content,
            reference: decoded.data.reference
        )
    }
}

// MARK: - Response Models

struct BibleAPIResponse: Codable {
    let reference: String
    let verses: [VerseDetail]
    let text: String
    let translation_id: String
    let translation_name: String
}

struct VerseDetail: Codable {
    let book_id: String
    let book_name: String
    let chapter: Int
    let verse: Int
    let text: String
}

struct ESVAPIResponse: Codable {
    let passages: [String]
    let canonical: String
}

struct ScriptureAPIResponse: Codable {
    let data: ScriptureData
}

struct ScriptureData: Codable {
    let id: String
    let reference: String
    let content: String
}

struct BibleVerse: Codable {
    let text: String
    let reference: String
}

// MARK: - How to Use the API Service

/*
 
 ## STEP 1: Update ResourcesView to use API
 
 In ResourcesView.swift, replace the refreshDailyVerse function:
 
 ```swift
 private func refreshDailyVerse() {
     Task {
         withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
             isRefreshingVerse = true
         }
         
         do {
             let verse = try await BibleAPIService.shared.getVerseOfTheDay()
             withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                 dailyVerse = DailyVerse(
                     text: verse.text,
                     reference: verse.reference
                 )
                 isRefreshingVerse = false
             }
         } catch {
             print("Error fetching verse: \(error)")
             // Fall back to random sample verse
             withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                 dailyVerse = DailyVerse.random()
                 isRefreshingVerse = false
             }
         }
     }
 }
 ```
 
 ## STEP 2: Add API keys to Info.plist (for security)
 
 1. Open Info.plist
 2. Add keys:
    - ESV_API_KEY
    - BIBLE_API_KEY
 
 3. Access in code:
 ```swift
 if let apiKey = Bundle.main.object(forInfoPListKey: "ESV_API_KEY") as? String {
     // Use apiKey
 }
 ```
 
 ## STEP 3: Handle Network Errors Gracefully
 
 Always provide fallback content when API calls fail!
 
 ## STEP 4: Add Loading States
 
 Show activity indicators during API calls for better UX.
 
 ## RECOMMENDED APIS FOR YOUR APP:
 
 ✅ **Bible Verse**: Bible API (bible-api.com) - Free, no auth
 ✅ **Bible Facts**: Create your own database or use a facts API
 ✅ **Sermons**: YouTube Data API (you're already using embeds)
 ✅ **Podcasts**: Apple Podcasts API or RSS feeds
 ✅ **Books**: Open Library API or Google Books API
 ✅ **Churches**: Google Places API
 
 ## IMPORTANT NOTES:
 
 1. **Rate Limits**: Most free APIs have limits (e.g., 100 requests/day)
 2. **Caching**: Cache API responses to reduce calls
 3. **Error Handling**: Always handle network failures
 4. **Privacy**: Never store API keys in source code
 5. **Testing**: Test with and without internet connection
 
 */

// MARK: - Example: Google Books API (for Essential Books)

class BooksAPIService {
    static let shared = BooksAPIService()
    
    private let baseURL = "https://www.googleapis.com/books/v1"
    
    func searchBooks(query: String, category: String = "christianity") async throws -> [BookResult] {
        let searchQuery = "\(query) subject:\(category)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "\(baseURL)/volumes?q=\(searchQuery)&maxResults=20") else {
            throw APIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
        
        return response.items?.map { item in
            BookResult(
                title: item.volumeInfo.title,
                authors: item.volumeInfo.authors ?? [],
                description: item.volumeInfo.description ?? "",
                imageURL: item.volumeInfo.imageLinks?.thumbnail,
                purchaseLink: item.saleInfo?.buyLink
            )
        } ?? []
    }
}

struct GoogleBooksResponse: Codable {
    let items: [BookItem]?
}

struct BookItem: Codable {
    let volumeInfo: VolumeInfo
    let saleInfo: SaleInfo?
}

struct VolumeInfo: Codable {
    let title: String
    let authors: [String]?
    let description: String?
    let imageLinks: ImageLinks?
}

struct ImageLinks: Codable {
    let thumbnail: String?
}

struct SaleInfo: Codable {
    let buyLink: String?
}

struct BookResult {
    let title: String
    let authors: [String]
    let description: String
    let imageURL: String?
    let purchaseLink: String?
}

// MARK: - Example: Custom AMEN API

/*
 When you build your own backend, you'll have endpoints like:
 
 - GET /api/v1/verse-of-the-day
 - GET /api/v1/bible-facts
 - GET /api/v1/articles
 - GET /api/v1/resources
 - POST /api/v1/bookmarks
 - GET /api/v1/user/saved-items
 
 Example usage:
 
 ```swift
 class AMENAPIService {
     static let shared = AMENAPIService()
     private let baseURL = "https://api.amenapp.com/v1"
     
     func getVerseOfTheDay() async throws -> DailyVerse {
         try await APIService.shared.fetch(
             endpoint: "verse-of-the-day",
             type: DailyVerse.self
         )
     }
     
     func getBibleFact() async throws -> BibleFact {
         try await APIService.shared.fetch(
             endpoint: "bible-facts/random",
             type: BibleFact.self
         )
     }
 }
 ```
 */
