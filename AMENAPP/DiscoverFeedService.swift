// DEFERRED-DEPLOY: loadInitialContent() is an empty stub. Production content
// requires a real apiKey to be set via Firebase Remote Config or backend config.
// The full Firestore-backed implementation exists as an untracked file pending
// Xcode project integration. (GAP A1-P1)

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
    @Published var people: [DiscoverSearchPerson] = []
    @Published var posts: [DiscoverFeedPost] = []
    @Published var newsItems: [NewsItem] = []
    @Published var youtubeVideos: [YoutubeVideoItem] = []
    @Published var dailyVerse: DiscoverDailyVerseData?
    @Published var topicPills: [DiscoverPillItem] = []
    @Published var isLoading = false
    @Published var error: Error?

    init() {
        Task { await loadInitialContent() }
    }

    func loadInitialContent() async {
        isLoading = true
        error = nil
        isLoading = false
    }

    func refresh() async {
        await loadInitialContent()
    }
}
