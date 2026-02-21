//
//  BereanIntegrationHelpers.swift
//  AMENAPP
//
//  Created by Assistant on 2/3/26.
//
//  Helper functions for integrating Berean with other app features
//

import Foundation
import SwiftUI

// MARK: - Verse Reference Parser

struct VerseReferenceParser {
    /// Parse a verse reference string into components
    /// Examples: "John 3:16", "Romans 8:28-30", "1 Corinthians 13:4-7"
    static func parse(_ reference: String) -> VerseReference? {
        // Remove extra whitespace
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern: (Book) (Chapter):(Verse)(-EndVerse)?
        let pattern = #"^([1-3]?\s?[A-Za-z\s]+?)\s+(\d+):(\d+)(?:-(\d+))?$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsString = trimmed as NSString
        let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = matches.first,
              match.numberOfRanges >= 4 else {
            return nil
        }
        
        let book = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let chapter = Int(nsString.substring(with: match.range(at: 2)))
        let startVerse = Int(nsString.substring(with: match.range(at: 3)))
        
        var endVerse: Int?
        if match.numberOfRanges >= 5 && match.range(at: 4).location != NSNotFound {
            endVerse = Int(nsString.substring(with: match.range(at: 4)))
        }
        
        guard let chapterNum = chapter, let verseNum = startVerse else {
            return nil
        }
        
        return VerseReference(
            book: book,
            chapter: chapterNum,
            startVerse: verseNum,
            endVerse: endVerse
        )
    }
    
    /// Validate if a string looks like a verse reference
    static func isValidReference(_ text: String) -> Bool {
        return parse(text) != nil
    }
}

// MARK: - Verse Reference Model

struct VerseReference {
    let book: String
    let chapter: Int
    let startVerse: Int
    let endVerse: Int?
    
    var fullReference: String {
        if let end = endVerse, end != startVerse {
            return "\(book) \(chapter):\(startVerse)-\(end)"
        } else {
            return "\(book) \(chapter):\(startVerse)"
        }
    }
    
    var bookChapter: String {
        return "\(book) \(chapter)"
    }
    
    var verseRange: String {
        if let end = endVerse, end != startVerse {
            return "\(startVerse)-\(end)"
        } else {
            return "\(startVerse)"
        }
    }
}

// MARK: - Navigation Helper

/// Use this to navigate to Bible view from Berean AI
/// Customize based on your app's navigation structure
struct BereanNavigationHelper {
    
    /// Navigate to a specific verse in your Bible reader
    /// Replace this implementation with your actual navigation logic
    static func openBibleVerse(reference: String, translation: String = "ESV") {
        guard let parsed = VerseReferenceParser.parse(reference) else {
            print("❌ Invalid verse reference: \(reference)")
            return
        }
        
        print("📖 Opening Bible: \(parsed.fullReference) (\(translation))")
        
        // OPTION 1: Using NavigationLink (if in NavigationStack)
        // You would need to use an EnvironmentObject or AppState
        // Example:
        // AppState.shared.navigateToBible(verse: parsed, translation: translation)
        
        // OPTION 2: Using programmatic navigation
        // Example:
        // NavigationManager.shared.push(.bible(verse: parsed, translation: translation))
        
        // OPTION 3: Using Deep Link
        // Example:
        // if let url = URL(string: "amenapp://bible/\(parsed.book)/\(parsed.chapter)/\(parsed.startVerse)") {
        //     UIApplication.shared.open(url)
        // }
        
        // ✅ Using NotificationCenter for verse navigation
        NotificationCenter.default.post(
            name: Notification.Name("OpenBibleVerse"),
            object: nil,
            userInfo: [
                "book": parsed.book,
                "chapter": parsed.chapter,
                "startVerse": parsed.startVerse,
                "endVerse": parsed.endVerse as Any,
                "translation": translation,
                "fullReference": parsed.fullReference
            ]
        )
        
        // Copy to clipboard as backup (in case navigation fails)
        Task.detached(priority: .background) {
            await MainActor.run {
                UIPasteboard.general.string = reference
            }
        }
    }
    
    /// Open Bible to a specific book and chapter
    static func openBibleChapter(book: String, chapter: Int, translation: String = "ESV") {
        print("📖 Opening Bible: \(book) \(chapter) (\(translation))")
        
        // Implement your navigation logic here
        NotificationCenter.default.post(
            name: Notification.Name("OpenBibleChapter"),
            object: nil,
            userInfo: [
                "book": book,
                "chapter": chapter,
                "translation": translation
            ]
        )
    }
}

// MARK: - Example Integration with Your Bible View

/*
 In your Bible Reader View, listen for the notification:
 
 struct BibleReaderView: View {
     @State private var currentVerse: VerseReference?
     @State private var translation = "ESV"
     
     var body: some View {
         // Your Bible UI
         ScrollView {
             // Bible content
         }
         .onAppear {
             setupVerseNavigation()
         }
     }
     
     private func setupVerseNavigation() {
         NotificationCenter.default.addObserver(
             forName: Notification.Name("OpenBibleVerse"),
             object: nil,
             queue: .main
         ) { notification in
             if let reference = notification.userInfo?["reference"] as? VerseReference,
                let trans = notification.userInfo?["translation"] as? String {
                 
                 // Navigate to this verse
                 self.currentVerse = reference
                 self.translation = trans
                 
                 // Scroll to verse
                 scrollToVerse(reference)
             }
         }
     }
     
     private func scrollToVerse(_ reference: VerseReference) {
         // Your scroll logic here
     }
 }
*/

// MARK: - Deep Link Handler

/// Register this in your App or SceneDelegate
struct BereanDeepLinkHandler {
    
    /// Handle deep links to Bible verses
    /// URL format: amenapp://bible/John/3/16
    /// or: amenapp://bible/John/3/16?translation=NIV
    static func handleURL(_ url: URL) -> Bool {
        guard url.scheme == "amenapp",
              url.host == "bible" else {
            return false
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard pathComponents.count >= 3 else {
            return false
        }
        
        let book = pathComponents[0].replacingOccurrences(of: "%20", with: " ")
        guard let chapter = Int(pathComponents[1]),
              let verse = Int(pathComponents[2]) else {
            return false
        }
        
        // Parse query parameters
        var translation = "ESV"
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                if item.name == "translation", let value = item.value {
                    translation = value
                }
            }
        }
        
        let reference = VerseReference(
            book: book,
            chapter: chapter,
            startVerse: verse,
            endVerse: nil
        )
        
        BereanNavigationHelper.openBibleVerse(
            reference: reference.fullReference,
            translation: translation
        )
        
        return true
    }
}

// MARK: - Example Usage in Your App

/*
 // In your @main App struct:
 
 @main
 struct AMENApp: App {
     var body: some Scene {
         WindowGroup {
             ContentView()
                 .onOpenURL { url in
                     _ = BereanDeepLinkHandler.handleURL(url)
                 }
         }
     }
 }
 
 // In your main navigation coordinator or app state:
 
 class AppNavigationCoordinator: ObservableObject {
     @Published var selectedTab: Tab = .home
     @Published var bibleVerse: VerseReference?
     @Published var bibleTranslation: String = "ESV"
     
     init() {
         setupBereanIntegration()
     }
     
     private func setupBereanIntegration() {
         NotificationCenter.default.addObserver(
             forName: Notification.Name("OpenBibleVerse"),
             object: nil,
             queue: .main
         ) { [weak self] notification in
             if let reference = notification.userInfo?["reference"] as? VerseReference,
                let translation = notification.userInfo?["translation"] as? String {
                 
                 self?.selectedTab = .bible
                 self?.bibleVerse = reference
                 self?.bibleTranslation = translation
             }
         }
     }
 }
*/

// MARK: - Test Cases

#if DEBUG
extension VerseReferenceParser {
    static func runTests() {
        let testCases: [(String, Bool)] = [
            ("John 3:16", true),
            ("Romans 8:28-30", true),
            ("1 Corinthians 13:4", true),
            ("2 Timothy 3:16-17", true),
            ("Psalm 23:1", true),
            ("Invalid Reference", false),
            ("John 3:", false),
            ("3:16", false),
        ]
        
        print("🧪 Running Verse Reference Parser Tests:")
        for (input, expectedValid) in testCases {
            let result = parse(input)
            let isValid = result != nil
            let status = isValid == expectedValid ? "✅" : "❌"
            print("\(status) '\(input)' - Valid: \(isValid) (Expected: \(expectedValid))")
            if let parsed = result {
                print("   Parsed: \(parsed.fullReference)")
            }
        }
    }
}
#endif
