//
//  SmartIdeaFilteringService.swift
//  AMENAPP
//
//  Created by Claude on 2/15/26.
//
//  AI-powered smart filtering for Top Ideas with NLP-style category detection
//

import Foundation
import FirebaseFirestore
import Combine

/// Smart filtering service that uses keyword analysis and semantic matching
/// to categorize ideas into AI & Tech, Ministry, Business, or Creative
@MainActor
class SmartIdeaFilteringService: ObservableObject {
    static let shared = SmartIdeaFilteringService()
    
    // MARK: - Category Keywords (Optimized for Fast Matching)
    
    private let categoryKeywords: [TopIdea.IdeaCategory: Set<String>] = [
        .ai: [
            // AI & Machine Learning
            "ai", "artificial intelligence", "ml", "machine learning", "neural", "algorithm",
            "automation", "bot", "chatbot", "api", "code", "programming", "software",
            "app", "platform", "tech", "technology", "data", "analytics", "cloud",
            "blockchain", "crypto", "web3", "saas", "automation", "script", "tool",
            
            // Development
            "developer", "coding", "framework", "library", "database", "server",
            "frontend", "backend", "fullstack", "mobile", "ios", "android", "web",
            "react", "swift", "python", "javascript", "api integration",
            
            // Emerging Tech
            "ar", "vr", "metaverse", "quantum", "iot", "5g", "edge computing",
            "robotics", "drone", "autonomous", "smart device"
        ],
        
        .ministry: [
            // Church & Ministry
            "church", "ministry", "pastor", "worship", "sermon", "bible study",
            "discipleship", "evangelism", "mission", "missions", "outreach",
            "youth group", "small group", "prayer", "devotional", "scripture",
            
            // Faith Activities
            "baptism", "communion", "sunday school", "vacation bible school", "vbs",
            "retreat", "conference", "revival", "crusade", "gospel", "testimony",
            "faith", "christian", "god", "jesus", "holy spirit", "salvation",
            
            // Church Operations
            "church growth", "church planting", "pastoral care", "counseling",
            "church leadership", "elder", "deacon", "congregation", "denomination",
            "theological", "seminary", "bible college"
        ],
        
        .business: [
            // Business & Entrepreneurship
            "business", "startup", "entrepreneur", "company", "enterprise",
            "revenue", "profit", "sales", "marketing", "branding", "customer",
            "product", "service", "marketplace", "ecommerce", "store", "shop",
            
            // Finance & Growth
            "funding", "investment", "investor", "venture capital", "vc", "angel",
            "fundraising", "crowdfunding", "monetization", "pricing", "subscription",
            "growth", "scale", "expansion", "franchise", "partnership",
            
            // Operations
            "business model", "strategy", "operations", "logistics", "supply chain",
            "hr", "hiring", "team", "management", "consulting", "advisory",
            "b2b", "b2c", "saas business", "marketplace"
        ],
        
        .creative: [
            // Arts & Media
            "art", "design", "creative", "music", "video", "film", "photography",
            "graphic design", "illustration", "animation", "content", "media",
            "podcast", "youtube", "streaming", "social media", "influencer",
            
            // Writing & Communication
            "writing", "author", "book", "blog", "storytelling", "copywriting",
            "journalism", "poetry", "novel", "screenplay", "publishing",
            
            // Performance & Production
            "performance", "theater", "drama", "concert", "event", "production",
            "recording", "studio", "editing", "post-production", "visual effects",
            "sound design", "music production", "branding", "logo", "ui/ux"
        ]
    ]
    
    // MARK: - Smart Categorization Algorithm
    
    /// Analyze idea content and automatically detect category
    /// Uses fast keyword matching with weighted scoring
    func detectCategory(for idea: String) -> TopIdea.IdeaCategory {
        let cleanedIdea = idea.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
        
        var scores: [TopIdea.IdeaCategory: Double] = [
            .all: 0,
            .ai: 0,
            .ministry: 0,
            .business: 0,
            .creative: 0
        ]
        
        // Score each category based on keyword matches
        for (category, keywords) in categoryKeywords {
            var categoryScore: Double = 0
            
            for keyword in keywords {
                // Exact match gets full points
                if cleanedIdea.contains(keyword) {
                    // Longer, more specific keywords score higher
                    let specificity = Double(keyword.count) / 10.0
                    categoryScore += 1.0 + specificity
                    
                    // Bonus if keyword appears multiple times
                    let occurrences = cleanedIdea.components(separatedBy: keyword).count - 1
                    if occurrences > 1 {
                        categoryScore += Double(occurrences - 1) * 0.5
                    }
                }
            }
            
            scores[category] = categoryScore
        }
        
        // Return category with highest score
        let topCategory = scores
            .filter { $0.key != .all }
            .max(by: { $0.value < $1.value })
        
        // If no clear winner (score < 2), default to .all
        if let category = topCategory?.key, topCategory?.value ?? 0 > 2.0 {
            return category
        }
        
        return .all
    }
    
    // MARK: - Fast Batch Filtering
    
    /// Filter and categorize multiple ideas efficiently
    func categorizeIdeas(_ ideas: [TopIdea]) -> [TopIdea.IdeaCategory: [TopIdea]] {
        var categorized: [TopIdea.IdeaCategory: [TopIdea]] = [
            .all: ideas,
            .ai: [],
            .ministry: [],
            .business: [],
            .creative: []
        ]
        
        for idea in ideas {
            let category = detectCategory(for: idea.content)
            categorized[category, default: []].append(idea)
        }
        
        return categorized
    }
    
    // MARK: - Smart Filtering with Multiple Criteria
    
    /// Advanced filter that combines category, timeframe, and engagement
    func filterIdeas(
        _ ideas: [TopIdea],
        category: TopIdea.IdeaCategory,
        timeframe: TimeInterval,
        minEngagement: Int = 0
    ) -> [TopIdea] {
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-timeframe)
        
        return ideas.filter { idea in
            // Category filter
            let matchesCategory = category == .all || detectCategory(for: idea.content) == category
            
            // Timeframe filter
            let isInTimeframe = idea.createdAt >= cutoffDate
            
            // Engagement filter
            let meetsEngagement = idea.lightbulbCount >= minEngagement
            
            return matchesCategory && isInTimeframe && meetsEngagement
        }
        .sorted { idea1, idea2 in
            // Sort by engagement (lightbulbs + comments)
            let engagement1 = idea1.lightbulbCount + idea1.commentCount
            let engagement2 = idea2.lightbulbCount + idea2.commentCount
            return engagement1 > engagement2
        }
    }
    
    // MARK: - Trending Detection
    
    /// Detect if an idea is trending (rapid engagement growth)
    func isTrending(_ idea: TopIdea, comparedTo average: Double) -> Bool {
        let engagement = Double(idea.lightbulbCount + idea.commentCount)
        let ageInHours = Date().timeIntervalSince(idea.createdAt) / 3600
        
        // Avoid division by zero
        guard ageInHours > 0 else { return false }
        
        // Calculate engagement rate (engagements per hour)
        let engagementRate = engagement / ageInHours
        
        // Trending if rate is 2x average or higher
        return engagementRate > average * 2.0
    }
    
    // MARK: - Category Statistics
    
    /// Get engagement statistics per category
    func getCategoryStats(_ ideas: [TopIdea]) -> [TopIdea.IdeaCategory: CategoryStats] {
        var stats: [TopIdea.IdeaCategory: CategoryStats] = [:]
        
        let categorized = categorizeIdeas(ideas)
        
        for (category, categoryIdeas) in categorized where category != .all {
            let totalEngagement = categoryIdeas.reduce(0) { $0 + $1.lightbulbCount + $1.commentCount }
            let avgEngagement = categoryIdeas.isEmpty ? 0 : Double(totalEngagement) / Double(categoryIdeas.count)
            
            stats[category] = CategoryStats(
                count: categoryIdeas.count,
                totalEngagement: totalEngagement,
                averageEngagement: avgEngagement,
                topIdea: categoryIdeas.max(by: { $0.lightbulbCount < $1.lightbulbCount })
            )
        }
        
        return stats
    }
}

// MARK: - Supporting Models

struct CategoryStats {
    let count: Int
    let totalEngagement: Int
    let averageEngagement: Double
    let topIdea: TopIdea?
}
