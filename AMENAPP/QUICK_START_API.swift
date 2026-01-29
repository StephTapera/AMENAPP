//
//  QUICK_START_API.swift
//  
//  Copy this code to quickly add Bible API to your ResourcesView
//

import Foundation

// MARK: - Step 1: Add this simple Bible API service

class SimpleBibleAPI {
    static let shared = SimpleBibleAPI()
    
    func getDailyVerse() async throws -> (text: String, reference: String) {
        // Random popular verses
        let verses = [
            "john+3:16", "philippians+4:13", "proverbs+3:5-6",
            "psalm+23:1", "romans+8:28", "jeremiah+29:11",
            "matthew+6:33", "isaiah+41:10", "psalm+46:10"
        ]
        
        let randomVerse = verses.randomElement() ?? "john+3:16"
        let urlString = "https://bible-api.com/\(randomVerse)?translation=kjv"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(QuickStartBibleAPIResponse.self, from: data)
        
        return (
            text: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
            reference: response.reference
        )
    }
}

struct QuickStartBibleAPIResponse: Codable {
    let reference: String
    let text: String
}

// MARK: - Step 2: Replace this function in ResourcesView.swift

/*
 
 Find the refreshDailyVerse() function around line 300-315 and replace it with:

 private func refreshDailyVerse() {
     Task {
         withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
             isRefreshingVerse = true
         }
         
         do {
             let verse = try await SimpleBibleAPI.shared.getDailyVerse()
             
             await MainActor.run {
                 withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                     dailyVerse = DailyVerse(
                         text: verse.text,
                         reference: verse.reference
                     )
                     isRefreshingVerse = false
                 }
             }
         } catch {
             // Fallback to random sample if API fails
             await MainActor.run {
                 withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                     dailyVerse = DailyVerse.random()
                     isRefreshingVerse = false
                 }
             }
         }
     }
 }
 
 */

// MARK: - Step 3: That's it! Test it!

/*
 
 1. Copy SimpleBibleAPI class above into a new Swift file or add to APIService.swift
 2. Replace the refreshDailyVerse() function in ResourcesView.swift
 3. Run the app
 4. Tap the refresh button on Daily Bible Verse card
 5. Watch it load a real verse from the Bible API! 🎉
 
 What happens:
 - Taps refresh → Shows loading animation
 - Calls bible-api.com → Gets real verse
 - Updates UI → Smooth animation
 - If fails → Falls back to local sample verses
 
 No API key needed! bible-api.com is completely free.
 
 */

// MARK: - Optional: Add loading indicator while fetching

/*
 
 To show a better loading state, you can add a ProgressView:
 
 In DailyVerseCard, replace the refresh button with:
 
 if isRefreshing {
     ProgressView()
         .scaleEffect(0.8)
 } else {
     Button(action: onRefresh) {
         Image(systemName: "arrow.clockwise")
             .font(.system(size: 16, weight: .semibold))
             .foregroundStyle(.blue)
     }
 }
 
 */

// MARK: - Advanced: Add caching to reduce API calls

class CachedBibleAPI {
    static let shared = CachedBibleAPI()
    
    private let cacheKey = "lastDailyVerse"
    private let cacheDateKey = "lastVerseDate"
    
    func getDailyVerse() async throws -> (text: String, reference: String) {
        // Check if we have a cached verse from today
        if let cached = loadCachedVerse(), isToday(cached.date) {
            return (cached.text, cached.reference)
        }
        
        // Fetch new verse from API
        let verse = try await SimpleBibleAPI.shared.getDailyVerse()
        
        // Cache it
        saveVerse(text: verse.text, reference: verse.reference)
        
        return verse
    }
    
    private func loadCachedVerse() -> (text: String, reference: String, date: Date)? {
        guard let text = UserDefaults.standard.string(forKey: cacheKey),
              let reference = UserDefaults.standard.string(forKey: "\(cacheKey)_ref"),
              let date = UserDefaults.standard.object(forKey: cacheDateKey) as? Date else {
            return nil
        }
        return (text, reference, date)
    }
    
    private func saveVerse(text: String, reference: String) {
        UserDefaults.standard.set(text, forKey: cacheKey)
        UserDefaults.standard.set(reference, forKey: "\(cacheKey)_ref")
        UserDefaults.standard.set(Date(), forKey: cacheDateKey)
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

/*
 
 Use CachedBibleAPI instead of SimpleBibleAPI:
 
 let verse = try await CachedBibleAPI.shared.getDailyVerse()
 
 This will:
 1. Check if we already fetched a verse today
 2. If yes, return cached verse (instant!)
 3. If no, fetch from API and cache it
 
 Benefits:
 - Only 1 API call per day (saves quota)
 - Works offline if you've loaded today's verse
 - Faster response time
 
 */

// MARK: - Testing checklist

/*
 
 ✅ Test with internet:
    - Should load real verses from API
    - Different verse each refresh
    
 ✅ Test without internet (Airplane mode):
    - Should fall back to sample verses
    - No crashes
    - User sees content
    
 ✅ Test refresh multiple times:
    - Loading animation works
    - New verses load
    - No errors in console
    
 ✅ Test caching (if using CachedBibleAPI):
    - First load: fetches from API
    - Second load same day: instant (from cache)
    - Next day: fetches new verse
 
 */
