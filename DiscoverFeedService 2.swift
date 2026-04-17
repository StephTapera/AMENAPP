//
//  DiscoverFeedService.swift
//  AMENAPP
//
//  Service for loading Discover feed content
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
class DiscoverFeedService: ObservableObject {
    @Published var people: [DiscoveryPerson] = []
    @Published var posts: [DiscoveryPost] = []
    @Published var newsItems: [NewsItem] = []
    @Published var youtubeVideos: [YoutubeVideoItem] = []
    @Published var dailyVerse: DailyVerseData?
    @Published var topicPills: [DiscoverPillItem] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Auto-load on init for seamless UX
        Task {
            await loadInitialContent()
        }
    }
    
    // MARK: - Public API
    
    func loadInitialContent() async {
        isLoading = true
        error = nil
        
        // Load all content types in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPeople() }
            group.addTask { await self.loadPosts() }
            group.addTask { await self.loadNews() }
            group.addTask { await self.loadVideos() }
            group.addTask { await self.loadDailyVerse() }
            group.addTask { await self.loadTopicPills() }
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadInitialContent()
    }
    
    // MARK: - Content Loaders
    
    private func loadPeople() async {
        do {
            // Query Firestore for suggested people
            // In production, this would use a smart algorithm based on:
            // - Mutual connections
            // - Topic interests
            // - Activity patterns
            // - Location proximity
            
            let snapshot = try await db.collection("users")
                .whereField("isPrivate", isEqualTo: false)
                .limit(to: 20)
                .getDocuments()
            
            let discoveryPeople = snapshot.documents.compactMap { doc -> DiscoveryPerson? in
                guard let displayName = doc.data()["displayName"] as? String,
                      let username = doc.data()["username"] as? String else {
                    return nil
                }
                
                return DiscoveryPerson(
                    id: doc.documentID,
                    displayName: displayName,
                    username: username,
                    avatarURL: doc.data()["profileImageURL"] as? String,
                    bio: doc.data()["bio"] as? String,
                    followerCount: doc.data()["followerCount"] as? Int ?? 0,
                    followingCount: doc.data()["followingCount"] as? Int ?? 0,
                    mutualFollowerCount: 0, // Calculate from mutual connections
                    isVerified: doc.data()["isVerified"] as? Bool ?? false,
                    isPrivate: false,
                    isFollowing: false,
                    churchName: doc.data()["churchName"] as? String,
                    location: doc.data()["location"] as? String,
                    topicAffinities: doc.data()["topicAffinities"] as? [String],
                    recentPostCount: doc.data()["postCount"] as? Int ?? 0
                )
            }
            
            people = discoveryPeople
        } catch {
            dlog("❌ Failed to load discover people: \(error.localizedDescription)")
            #if DEBUG
            // Fallback to mock data for development only
            people = mockPeople()
            #else
            people = []
            #endif
        }
    }
    
    private func loadPosts() async {
        do {
            // Query trending/featured posts
            let snapshot = try await db.collection("posts")
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .getDocuments()
            
            let discoveryPosts = snapshot.documents.compactMap { doc -> DiscoveryPost? in
                guard let authorId = doc.data()["authorId"] as? String,
                      let content = doc.data()["content"] as? String else {
                    return nil
                }
                
                return DiscoveryPost(
                    id: doc.documentID,
                    authorId: authorId,
                    authorName: doc.data()["authorName"] as? String ?? "Unknown",
                    authorUsername: doc.data()["authorUsername"] as? String ?? "",
                    authorAvatarURL: doc.data()["authorAvatarURL"] as? String,
                    content: content,
                    imageURL: doc.data()["imageURL"] as? String,
                    videoURL: doc.data()["videoURL"] as? String,
                    category: parsePostCategory(doc.data()["category"] as? String),
                    timestamp: (doc.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    likeCount: doc.data()["likeCount"] as? Int ?? 0,
                    commentCount: doc.data()["commentCount"] as? Int ?? 0,
                    shareCount: doc.data()["shareCount"] as? Int ?? 0,
                    saveCount: doc.data()["saveCount"] as? Int ?? 0,
                    isVersePost: doc.data()["isVersePost"] as? Bool ?? false,
                    verseReference: doc.data()["verseReference"] as? String,
                    topicTags: doc.data()["topicTags"] as? [String]
                )
            }
            
            posts = discoveryPosts
        } catch {
            dlog("❌ Failed to load discover posts: \(error.localizedDescription)")
            #if DEBUG
            posts = mockPosts()
            #else
            posts = []
            #endif
        }
    }
    
    private func loadNews() async {
        // TODO: In production, this should fetch from a curated news API or backend service
        #if DEBUG
        // For now, use mock data in development only
        newsItems = mockNews()
        #else
        newsItems = []
        #endif
    }
    
    private func loadVideos() async {
        // TODO: In production, this should fetch from YouTube API, Vimeo, or video service
        #if DEBUG
        // For now, use mock data in development only
        youtubeVideos = mockVideos()
        #else
        youtubeVideos = []
        #endif
    }
    
    private func loadDailyVerse() async {
        do {
            // Try to fetch today's verse from Firestore
            let today = Calendar.current.startOfDay(for: Date())
            
            let snapshot = try await db.collection("daily_verses")
                .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: today))
                .limit(to: 1)
                .getDocuments()
            
            if let doc = snapshot.documents.first {
                dailyVerse = DailyVerseData(
                    id: doc.documentID,
                    text: doc.data()["text"] as? String ?? "",
                    reference: doc.data()["reference"] as? String ?? "",
                    translation: doc.data()["translation"] as? String ?? "ESV",
                    testament: doc.data()["testament"] as? String ?? "New",
                    book: doc.data()["book"] as? String ?? "",
                    chapter: doc.data()["chapter"] as? Int ?? 1,
                    verse: doc.data()["verse"] as? Int ?? 1,
                    theme: doc.data()["theme"] as? String,
                    devotional: doc.data()["devotional"] as? String,
                    imageURL: doc.data()["imageURL"] as? String,
                    accentColor: doc.data()["accentColor"] as? String,
                    discussionCount: doc.data()["discussionCount"] as? Int ?? 0,
                    saveCount: doc.data()["saveCount"] as? Int ?? 0,
                    shareCount: doc.data()["shareCount"] as? Int ?? 0,
                    date: (doc.data()["date"] as? Timestamp)?.dateValue() ?? Date()
                )
            } else {
                #if DEBUG
                dailyVerse = mockDailyVerse()
                #else
                dailyVerse = nil
                #endif
            }
        } catch {
            dlog("❌ Failed to load daily verse: \(error.localizedDescription)")
            #if DEBUG
            dailyVerse = mockDailyVerse()
            #else
            dailyVerse = nil
            #endif
        }
    }
    
    private func loadTopicPills() async {
        // Common topics for discovery
        let topics = [
            ("Prayer", "hands.sparkles"),
            ("Worship", "music.note"),
            ("Testimony", "heart.text.square"),
            ("Study", "book"),
            ("Faith", "flame"),
            ("Community", "person.3"),
            ("Ministry", "hands.and.sparkles"),
            ("Scripture", "text.book.closed")
        ]
        
        topicPills = topics.enumerated().map { index, topic in
            DiscoverPillItem(
                id: "topic_\(index)",
                title: topic.0,
                systemImage: topic.1,
                isActive: index == 0, // First one active by default
                count: nil,
                filterType: .topic(topic.0)
            ) {
                // Toggle this pill
                self.togglePill(id: "topic_\(index)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func parsePostCategory(_ category: String?) -> DiscoveryPost.PostCategory {
        guard let category = category else { return .general }
        return DiscoveryPost.PostCategory(rawValue: category) ?? .general
    }
    
    func togglePill(id: String) {
        if let index = topicPills.firstIndex(where: { $0.id == id }) {
            topicPills[index].isActive.toggle()
        }
    }
    
    // MARK: - Mock Data (for development)
    
    #if DEBUG
    private func mockPeople() -> [DiscoveryPerson] {
        return [
            DiscoveryPerson(
                id: "1",
                displayName: "Sarah Johnson",
                username: "@sarahjohnson",
                followerCount: 1240,
                mutualFollowerCount: 3,
                isVerified: true,
                churchName: "Grace Community Church",
                recentPostCount: 12
            ),
            DiscoveryPerson(
                id: "2",
                displayName: "Michael Chen",
                username: "@michaelchen",
                followerCount: 856,
                mutualFollowerCount: 1,
                churchName: "City Light Fellowship",
                recentPostCount: 8
            ),
            DiscoveryPerson(
                id: "3",
                displayName: "Pastor David",
                username: "@pastordavid",
                followerCount: 4520,
                isVerified: true,
                churchName: "Hope Church",
                recentPostCount: 24
            )
        ]
    }
    
    private func mockPosts() -> [DiscoveryPost] {
        return [
            DiscoveryPost(
                id: "1",
                authorId: "1",
                authorName: "Sarah Johnson",
                authorUsername: "@sarahjohnson",
                content: "Grateful for God's faithfulness today. He continues to show up in the small moments.",
                category: .testimony,
                likeCount: 45,
                commentCount: 12,
                shareCount: 3,
                saveCount: 8
            )
        ]
    }
    
    private func mockNews() -> [NewsItem] {
        return [
            NewsItem(
                headline: "Church Leaders Unite for Prayer Initiative",
                sourceName: "Faith Today",
                publishedAt: Date().addingTimeInterval(-3600 * 2), // 2 hours ago
                imageURL: nil,
                category: "Church"
            ),
            NewsItem(
                headline: "Global Missions Conference Draws Record Attendance",
                sourceName: "Ministry News",
                publishedAt: Date().addingTimeInterval(-3600 * 5), // 5 hours ago
                imageURL: nil,
                category: "Ministry"
            )
        ]
    }
    
    private func mockVideos() -> [YoutubeVideoItem] {
        return [
            YoutubeVideoItem(
                id: "1",
                title: "Sunday Worship Service - Live",
                channelName: "Hope Church",
                thumbnailURL: nil,
                viewCount: "1.2K",
                duration: "1:00:00"
            ),
            YoutubeVideoItem(
                id: "2",
                title: "Daily Devotional: Finding Peace in God's Presence",
                channelName: "Grace Fellowship",
                thumbnailURL: nil,
                viewCount: "856",
                duration: "15:30"
            )
        ]
    }
    
    private func mockDailyVerse() -> DailyVerseData {
        return DailyVerseData(
            id: "1",
            text: "For I know the plans I have for you, declares the LORD, plans for welfare and not for evil, to give you a future and a hope.",
            reference: "Jeremiah 29:11",
            translation: "ESV",
            testament: "Old",
            book: "Jeremiah",
            chapter: 29,
            verse: 11,
            theme: "Hope",
            devotional: "God's plans for us are good, even when we can't see them.",
            discussionCount: 48,
            saveCount: 156,
            shareCount: 32
        )
    }
    #endif
}
