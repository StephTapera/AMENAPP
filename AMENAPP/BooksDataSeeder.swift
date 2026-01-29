//
//  BooksDataSeeder.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Seeds Firebase with Essential Books data
//

import Foundation
import FirebaseFirestore

/// Utility to seed Firebase with essential Christian books
class BooksDataSeeder {
    static let shared = BooksDataSeeder()
    private let apiService = FirebaseBooksService.shared
    
    private init() {}
    
    /// Seed all essential books to Firebase
    @MainActor
    func seedBooks() async throws {
        print("🌱 Starting to seed Essential Books to Firebase...")
        
        let books = createEssentialBooks()
        var successCount = 0
        
        for book in books {
            do {
                _ = try await apiService.addBook(book)
                successCount += 1
                print("✅ Added: \(book.title)")
            } catch {
                print("❌ Failed to add \(book.title): \(error)")
            }
        }
        
        print("🎉 Seeding complete! Added \(successCount)/\(books.count) books to Firebase")
    }
    
    /// Create the essential books list
    private func createEssentialBooks() -> [Book] {
        return [
            Book(
                title: "Mere Christianity",
                author: "C.S. Lewis",
                description: "A classic defense of the Christian faith",
                category: "Apologetics",
                rating: 5,
                isFeatured: true,
                isTrending: true,
                tags: ["apologetics", "theology", "classic"]
            ),
            Book(
                title: "The Purpose Driven Life",
                author: "Rick Warren",
                description: "Discover God's purpose for your life",
                category: "Devotional",
                rating: 5,
                isFeatured: true,
                tags: ["purpose", "devotional", "spiritual growth"]
            ),
            Book(
                title: "Basic Christianity",
                author: "John Stott",
                description: "Essential truths for new believers",
                category: "New Believer",
                rating: 5,
                isFeatured: true,
                tags: ["basics", "new believer", "fundamentals"]
            ),
            Book(
                title: "Knowing God",
                author: "J.I. Packer",
                description: "A journey into knowing God intimately",
                category: "Theology",
                rating: 5,
                isTrending: true,
                tags: ["theology", "knowing God", "intimacy"]
            ),
            Book(
                title: "The Ragamuffin Gospel",
                author: "Brennan Manning",
                description: "Understanding God's unconditional love",
                category: "Devotional",
                rating: 5,
                isTrending: true,
                tags: ["grace", "love", "devotional"]
            ),
            Book(
                title: "Desiring God",
                author: "John Piper",
                description: "Finding satisfaction in God alone",
                category: "Theology",
                rating: 5,
                tags: ["satisfaction", "joy", "theology"]
            ),
            Book(
                title: "The Case for Christ",
                author: "Lee Strobel",
                description: "A journalist's investigation of Jesus",
                category: "Apologetics",
                rating: 5,
                isFeatured: true,
                isTrending: true,
                tags: ["apologetics", "evidence", "investigation"]
            ),
            Book(
                title: "My Utmost for His Highest",
                author: "Oswald Chambers",
                description: "Daily devotions for spiritual growth",
                category: "Devotional",
                rating: 5,
                tags: ["daily devotional", "spiritual growth"]
            ),
            Book(
                title: "The Cost of Discipleship",
                author: "Dietrich Bonhoeffer",
                description: "What it truly means to follow Christ",
                category: "Theology",
                rating: 5,
                isTrending: true,
                tags: ["discipleship", "following Christ", "sacrifice"]
            ),
            Book(
                title: "Radical",
                author: "David Platt",
                description: "Taking back your faith from the American dream",
                category: "New Believer",
                rating: 5,
                isFeatured: true,
                tags: ["radical faith", "discipleship", "commitment"]
            ),
            Book(
                title: "The Holiness of God",
                author: "R.C. Sproul",
                description: "Understanding God's transcendent holiness",
                category: "Theology",
                rating: 5,
                tags: ["holiness", "God's character", "theology"]
            ),
            Book(
                title: "Crazy Love",
                author: "Francis Chan",
                description: "Overwhelmed by a relentless God",
                category: "Devotional",
                rating: 5,
                isTrending: true,
                tags: ["love", "devotion", "passion"]
            ),
            Book(
                title: "The Jesus I Never Knew",
                author: "Philip Yancey",
                description: "A fresh look at the historical Jesus",
                category: "Biography",
                rating: 5,
                isFeatured: true,
                tags: ["Jesus", "biography", "historical"]
            ),
            Book(
                title: "Pilgrim's Progress",
                author: "John Bunyan",
                description: "The timeless allegory of Christian journey",
                category: "Biography",
                rating: 5,
                tags: ["allegory", "journey", "classic"]
            ),
            Book(
                title: "The Pursuit of God",
                author: "A.W. Tozer",
                description: "Experiencing deeper intimacy with God",
                category: "Devotional",
                rating: 5,
                isTrending: true,
                tags: ["intimacy", "pursuit", "devotional"]
            ),
            Book(
                title: "Evidence That Demands a Verdict",
                author: "Josh McDowell",
                description: "Historical evidence for the Christian faith",
                category: "Apologetics",
                rating: 5,
                tags: ["evidence", "apologetics", "historical"]
            ),
            Book(
                title: "Boundaries",
                author: "Henry Cloud",
                description: "When to say yes, how to say no",
                category: "New Believer",
                rating: 5,
                tags: ["boundaries", "relationships", "healthy living"]
            ),
            Book(
                title: "The Screwtape Letters",
                author: "C.S. Lewis",
                description: "Letters from a senior demon to his nephew",
                category: "Theology",
                rating: 5,
                isFeatured: true,
                tags: ["spiritual warfare", "theology", "fiction"]
            ),
            Book(
                title: "Celebration of Discipline",
                author: "Richard Foster",
                description: "The path to spiritual growth",
                category: "Devotional",
                rating: 5,
                tags: ["disciplines", "spiritual growth", "practices"]
            ),
            Book(
                title: "The Reason for God",
                author: "Timothy Keller",
                description: "Belief in an age of skepticism",
                category: "Apologetics",
                rating: 5,
                isTrending: true,
                tags: ["apologetics", "skepticism", "belief"]
            ),
            Book(
                title: "Simply Christian",
                author: "N.T. Wright",
                description: "Why Christianity makes sense",
                category: "New Believer",
                rating: 5,
                tags: ["basics", "Christianity", "introduction"]
            ),
            Book(
                title: "The Hiding Place",
                author: "Corrie ten Boom",
                description: "The triumphant story of faith in the Holocaust",
                category: "Biography",
                rating: 5,
                isFeatured: true,
                isTrending: true,
                tags: ["biography", "faith", "perseverance", "Holocaust"]
            ),
            Book(
                title: "Systematic Theology",
                author: "Wayne Grudem",
                description: "An introduction to biblical doctrine",
                category: "Theology",
                rating: 5,
                tags: ["systematic theology", "doctrine", "comprehensive"]
            ),
            Book(
                title: "The Attributes of God",
                author: "A.W. Pink",
                description: "Exploring the character of God",
                category: "Theology",
                rating: 5,
                tags: ["attributes", "God's character", "theology"]
            ),
            Book(
                title: "Humility",
                author: "Andrew Murray",
                description: "The beauty of holiness",
                category: "Devotional",
                rating: 5,
                tags: ["humility", "character", "virtue"]
            ),
            Book(
                title: "The Attributes of God Vol. 2",
                author: "A.W. Tozer",
                description: "Deeper into the Almighty",
                category: "Theology",
                rating: 5,
                tags: ["attributes", "theology", "God"]
            ),
            Book(
                title: "Respectable Sins",
                author: "Jerry Bridges",
                description: "Confronting the sins we tolerate",
                category: "New Believer",
                rating: 5,
                tags: ["sin", "sanctification", "holiness"]
            ),
            Book(
                title: "Don't Waste Your Life",
                author: "John Piper",
                description: "Living for the glory of God",
                category: "Devotional",
                rating: 5,
                isFeatured: true,
                tags: ["purpose", "glory", "mission"]
            ),
            Book(
                title: "The Gospel According to Jesus",
                author: "John MacArthur",
                description: "What is authentic faith?",
                category: "Theology",
                rating: 5,
                tags: ["gospel", "faith", "salvation"]
            ),
            Book(
                title: "Absolute Surrender",
                author: "Andrew Murray",
                description: "Complete devotion to Christ",
                category: "Devotional",
                rating: 5,
                tags: ["surrender", "devotion", "commitment"]
            )
        ]
    }
}
