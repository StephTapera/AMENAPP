//
//  PostTranslationService.swift
//  AMENAPP
//
//  Translation service for posts using Firebase Cloud Functions + OpenAI
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class PostTranslationService: ObservableObject {
    static let shared = PostTranslationService()
    
    @Published var isTranslating = false
    @Published var translationCache: [String: CachedTranslation] = [:]
    
    private let db = Firestore.firestore()
    private let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
    
    struct CachedTranslation: Codable {
        let originalText: String
        let translatedText: String
        let sourceLanguage: String
        let targetLanguage: String
        let timestamp: Date
    }
    
    private init() {
        print("✅ PostTranslationService initialized (device language: \(deviceLanguage))")
    }
    
    /// Detect the language of a text using OpenAI
    func detectLanguage(_ text: String) async throws -> String {
        // Use OpenAI to detect language
        let openAI = OpenAIService.shared
        
        let prompt = """
        Detect the language of this text and respond with ONLY the two-letter ISO 639-1 language code (e.g., 'en', 'es', 'fr', 'de', 'pt', 'zh', 'ar', 'hi', 'ko', 'ja').
        
        Text: "\(text)"
        
        Language code:
        """
        
        let response = try await openAI.sendMessageSync(prompt)
        let languageCode = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Validate it's a 2-letter code
        if languageCode.count == 2 {
            return languageCode
        }
        
        // Fallback to English if detection fails
        return "en"
    }
    
    /// Translate text using OpenAI
    func translateText(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        // Check cache first
        let cacheKey = "\(sourceLanguage)_\(targetLanguage)_\(text.hashValue)"
        if let cached = translationCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 3600 { // 1 hour cache
            print("✅ Using cached translation")
            return cached.translatedText
        }
        
        // Use OpenAI to translate
        let openAI = OpenAIService.shared
        
        let languageNames = [
            "en": "English",
            "es": "Spanish",
            "fr": "French",
            "de": "German",
            "pt": "Portuguese",
            "zh": "Chinese",
            "ar": "Arabic",
            "hi": "Hindi",
            "ko": "Korean",
            "ja": "Japanese",
            "it": "Italian",
            "ru": "Russian"
        ]
        
        let sourceLangName = languageNames[sourceLanguage] ?? sourceLanguage.uppercased()
        let targetLangName = languageNames[targetLanguage] ?? targetLanguage.uppercased()
        
        let prompt = """
        Translate this text from \(sourceLangName) to \(targetLangName). Preserve the original tone, meaning, and formatting. Only respond with the translation, nothing else.
        
        Text to translate:
        \(text)
        
        Translation:
        """
        
        let translation = try await openAI.sendMessageSync(prompt)
        let cleanedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Cache the translation
        let cachedTranslation = CachedTranslation(
            originalText: text,
            translatedText: cleanedTranslation,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            timestamp: Date()
        )
        translationCache[cacheKey] = cachedTranslation
        
        // Store in Firestore for reuse across sessions
        try await storeTranslationInFirestore(cacheKey: cacheKey, translation: cachedTranslation)
        
        return cleanedTranslation
    }
    
    /// Store translation in Firestore for cross-device caching
    private func storeTranslationInFirestore(cacheKey: String, translation: CachedTranslation) async throws {
        try await db.collection("translations").document(cacheKey).setData([
            "originalText": translation.originalText,
            "translatedText": translation.translatedText,
            "sourceLanguage": translation.sourceLanguage,
            "targetLanguage": translation.targetLanguage,
            "timestamp": Timestamp(date: translation.timestamp)
        ])
    }
    
    /// Fetch translation from Firestore if available
    func fetchTranslationFromFirestore(text: String, sourceLanguage: String, targetLanguage: String) async throws -> String? {
        let cacheKey = "\(sourceLanguage)_\(targetLanguage)_\(text.hashValue)"
        
        let doc = try await db.collection("translations").document(cacheKey).getDocument()
        
        if doc.exists,
           let data = doc.data(),
           let translatedText = data["translatedText"] as? String,
           let timestamp = data["timestamp"] as? Timestamp {
            
            // Check if cache is still valid (within 1 week)
            let age = Date().timeIntervalSince(timestamp.dateValue())
            if age < 604800 { // 7 days
                // Update local cache
                let cachedTranslation = CachedTranslation(
                    originalText: text,
                    translatedText: translatedText,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    timestamp: timestamp.dateValue()
                )
                translationCache[cacheKey] = cachedTranslation
                
                return translatedText
            }
        }
        
        return nil
    }
    
    /// Translate a post asynchronously (non-blocking)
    func translatePost(_ post: Post) async -> Post {
        do {
            // Detect source language
            let sourceLanguage = try await detectLanguage(post.content)
            
            // If post is already in device language, no need to translate
            if sourceLanguage == deviceLanguage {
                print("✅ Post already in device language (\(deviceLanguage))")
                return post
            }
            
            // Check Firestore cache first
            if let cachedTranslation = try await fetchTranslationFromFirestore(
                text: post.content,
                sourceLanguage: sourceLanguage,
                targetLanguage: deviceLanguage
            ) {
                print("✅ Using Firestore cached translation")
                var translatedPost = post
                translatedPost.content = cachedTranslation
                return translatedPost
            }
            
            // Translate the content
            await MainActor.run {
                isTranslating = true
            }
            
            let translatedContent = try await translateText(
                post.content,
                from: sourceLanguage,
                to: deviceLanguage
            )
            
            await MainActor.run {
                isTranslating = false
            }
            
            var translatedPost = post
            translatedPost.content = translatedContent
            
            print("✅ Post translated from \(sourceLanguage) to \(deviceLanguage)")
            return translatedPost
            
        } catch {
            print("❌ Translation failed: \(error.localizedDescription)")
            await MainActor.run {
                isTranslating = false
            }
            return post // Return original on error
        }
    }
    
    /// Get device language code
    func getDeviceLanguage() -> String {
        return deviceLanguage
    }
}
