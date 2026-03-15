// AMENConnectAIMatchEngine.swift
// AMENAPP
//
// Lightweight, on-device AI keyword detection engine for AMEN Connect.
// Scans a user's recent posts and comments for intent signals
// (job seeking, volunteering, mentorship, prayer, marketplace needs)
// and surfaces matched Connect listings.
//
// Architecture: no network calls — pure keyword + scoring heuristics.
// Works immediately on any device without API keys.
// Can be extended with on-device CoreML or Apple FoundationModels later.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Intent Keywords Map

private typealias KeywordRule = (keywords: [String], tab: AMENConnectTab, label: String)

private let intentRules: [KeywordRule] = [
    // Jobs / hiring
    (["looking for work", "looking for a job", "need a job", "job search", "hiring", "open to work",
      "seeking employment", "want to work in ministry", "church job", "ministry job", "faith-based career",
      "need employment", "unemployed", "laid off", "career change", "new opportunity"],
     .jobs, "job seeking"),

    // Serve / volunteer
    (["want to serve", "how can I help", "volunteer", "mission trip", "outreach", "serve my community",
      "local ministry", "food pantry", "give back", "help the homeless", "disaster relief",
      "youth camp", "children's ministry volunteer", "prison ministry"],
     .serve, "volunteering"),

    // Marketplace
    (["looking for a photographer", "need a designer", "christian therapist", "faith-based counselor",
      "looking for a wedding photographer", "hire a developer", "need editing", "looking for a consultant",
      "need help with fundraising", "want to work with christians", "christian business"],
     .marketplace, "marketplace service"),

    // Events
    (["worship night", "conference", "retreat", "attending", "going to church event", "bible conference",
      "christian event near me", "looking for events", "ministry training", "kingdom conference"],
     .events, "events"),

    // Prayer
    (["please pray", "prayer request", "need prayer", "lift me up", "intercede", "praying for",
      "struggling", "going through a hard time", "need God's help", "pray with me"],
     .prayer, "prayer request"),

    // Mentorship
    (["need a mentor", "looking for accountability", "discipleship", "mentor", "accountability partner",
      "want to be mentored", "grow in faith", "spiritual guidance", "faith coach", "need direction"],
     .mentorship, "mentorship"),

    // Forum / discussion
    (["question about", "what does the bible say", "theology", "anyone else feel", "faith question",
      "does god", "struggling with my faith", "apologetics", "discuss", "looking for community"],
     .forum, "forum discussion"),

    // Network / professional
    (["connect with believers", "faith-based network", "christian professional", "kingdom business",
      "meet fellow believers", "looking for christian coworkers", "faith community professional"],
     .network, "professional network"),

    // Ministries
    (["join a bible study", "looking for a small group", "want to join a church group",
      "accountability group", "men's group", "women's ministry", "marriage ministry"],
     .ministries, "ministry group"),
]

// MARK: - Match Engine

final class AMENConnectAIMatchEngine {
    static let shared = AMENConnectAIMatchEngine()
    private init() {}

    // MARK: Scan a batch of post/comment texts

    /// Returns a list of AIConnectMatch signals ranked by confidence.
    func analyzeTexts(_ texts: [String]) -> [AIConnectMatch] {
        var allMatches: [AIConnectMatch] = []

        for text in texts {
            let normalized = text.lowercased()
            for rule in intentRules {
                for keyword in rule.keywords {
                    if normalized.contains(keyword) {
                        let confidence = computeConfidence(text: normalized, keyword: keyword)
                        if confidence > 0.3 {
                            if let listing = bestListing(for: rule.tab) {
                                let suggestion = buildSuggestion(keyword: keyword, label: rule.label, listingTitle: listing.title)
                                let match = AIConnectMatch(
                                    keyword: keyword,
                                    matchedTab: rule.tab,
                                    matchedListingTitle: listing.title,
                                    matchedListingOrg: listing.org,
                                    matchedListingIcon: listing.icon,
                                    matchedListingColor: listing.tagColor,
                                    confidence: confidence,
                                    suggestion: suggestion
                                )
                                allMatches.append(match)
                            }
                        }
                        break // one keyword match per rule per text is enough
                    }
                }
            }
        }

        // Deduplicate by tab, keep highest confidence per tab
        var best: [AMENConnectTab: AIConnectMatch] = [:]
        for match in allMatches {
            if let existing = best[match.matchedTab] {
                if match.confidence > existing.confidence {
                    best[match.matchedTab] = match
                }
            } else {
                best[match.matchedTab] = match
            }
        }

        return best.values.sorted { $0.confidence > $1.confidence }
    }

    // MARK: Fetch recent posts for current user and scan them

    func scanRecentPostsForCurrentUser() async -> [AIConnectMatch] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 30)
                .getDocuments()
            let texts: [String] = snap.documents.compactMap { doc in
                let data = doc.data()
                let content = data["content"] as? String ?? ""
                let caption = data["caption"] as? String ?? ""
                return [content, caption].filter { !$0.isEmpty }.joined(separator: " ")
            }
            return analyzeTexts(texts)
        } catch {
            return []
        }
    }

    /// Scan a specific post text (called from PostCard / CreatePost on save)
    func scanText(_ text: String, postID: String) async {
        let matches = analyzeTexts([text])
        guard !matches.isEmpty else { return }
        let keywords = matches.map { $0.keyword }

        // Store intent signals to Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        for match in matches.prefix(3) {
            var signal = IntentSignal()
            signal.uid = uid
            signal.keyword = match.keyword
            signal.resolvedCategory = match.matchedTab
            signal.resolvedListingTitle = match.matchedListingTitle
            signal.confidence = match.confidence
            signal.sourcePostID = postID
            if let encoded = try? Firestore.Encoder().encode(signal) {
                try? await db.collection("amenConnectIntentSignals").document(signal.id).setData(encoded)
            }
        }

        // Update the membership profile's intent keywords
        await AMENConnectMembershipStore.shared.updateIntentKeywords(keywords)
    }

    // MARK: Helpers

    private func computeConfidence(text: String, keyword: String) -> Double {
        // Base score for exact match
        var score = 0.6

        // Boost for exclamation / question — shows genuine intent
        if text.contains("!") || text.contains("?") { score += 0.1 }

        // Boost for longer text — more context, more certain
        if text.count > 80 { score += 0.1 }

        // Boost for first-person framing
        let firstPerson = ["i ", "i'm", "i've", "my ", "me ", "myself", "i need", "i want", "i'm looking"]
        if firstPerson.contains(where: { text.contains($0) }) { score += 0.15 }

        return min(score, 1.0)
    }

    private func buildSuggestion(keyword: String, label: String, listingTitle: String) -> String {
        let phrases = [
            "We noticed you mentioned \"\(keyword)\" — \(listingTitle) might be helpful.",
            "Based on something you shared, \(listingTitle) could be a great fit.",
            "It looks like you're interested in \(label). Check out: \(listingTitle).",
            "Your recent post hints you might benefit from \(listingTitle).",
        ]
        return phrases[abs(keyword.hashValue) % phrases.count]
    }
}

// MARK: - Listing reference (mirrors amenConnectListings subset for matching)

private let matchableListings: [(tab: AMENConnectTab, title: String, org: String, icon: String, tagColor: any Hashable)] = [
    (.jobs, "Faith-Based Jobs", "Church hiring board", "briefcase.fill", 0),
    (.serve, "Serve & Volunteer", "Local outreach", "hands.sparkles.fill", 1),
    (.marketplace, "Kingdom Marketplace", "Christian services", "storefront.fill", 2),
    (.events, "Events & Gatherings", "Faith events", "calendar.badge.plus", 3),
    (.prayer, "Submit a Prayer Request", "AMEN Prayer Network", "hands.sparkles.fill", 4),
    (.mentorship, "Find a Faith Mentor", "AMEN mentorship network", "person.fill.checkmark", 5),
    (.forum, "Community Discussion", "Faith forums", "text.bubble.fill", 6),
    (.network, "Professional Network", "AMEN Pro", "person.3.sequence.fill", 7),
    (.ministries, "Ministries & Groups", "Local church groups", "book.fill", 8),
]

private func bestListing(for tab: AMENConnectTab) -> (title: String, org: String, icon: String, tagColor: Color)? {
    let colorMap: [Int: Color] = [
        0: Color(red: 0.15, green: 0.45, blue: 0.82),
        1: Color(red: 0.18, green: 0.62, blue: 0.36),
        2: Color(red: 0.90, green: 0.47, blue: 0.10),
        3: Color(red: 0.62, green: 0.28, blue: 0.82),
        4: Color(red: 0.42, green: 0.24, blue: 0.82),
        5: Color(red: 0.18, green: 0.55, blue: 0.45),
        6: Color(red: 0.85, green: 0.32, blue: 0.32),
        7: Color(red: 0.42, green: 0.24, blue: 0.82),
        8: Color(red: 0.15, green: 0.35, blue: 0.80),
    ]
    guard let entry = matchableListings.first(where: { $0.tab == tab }),
          let colorIndex = entry.tagColor as? Int,
          let color = colorMap[colorIndex] else { return nil }
    return (entry.title, entry.org, entry.icon, color)
}
