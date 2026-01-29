//
//  BookDataSeeder.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Seed the Firestore database with sample Christian books for Essential Books feature
//

import Foundation
import FirebaseFirestore

/// Utility class to seed Firebase with sample book data
class BookDataSeeder {
    
    static let shared = BookDataSeeder()
    private let service = FirebaseBooksService.shared
    
    private init() {}
    
    /// Seed the database with sample Christian books
    @MainActor
    func seedBooks() async throws {
        print("🌱 Starting to seed books database...")
        
        let books = createSampleBooks()
        
        var addedCount = 0
        for book in books {
            do {
                let bookId = try await service.addBook(book)
                print("✅ Added book: \(book.title) (ID: \(bookId))")
                addedCount += 1
            } catch {
                print("❌ Failed to add book '\(book.title)': \(error)")
            }
        }
        
        print("🎉 Seeding complete! Added \(addedCount) out of \(books.count) books.")
    }
    
    /// Create sample books for each category
    private func createSampleBooks() -> [Book] {
        var books: [Book] = []
        
        // MARK: - Apologetics Books
        
        books.append(Book(
            title: "Mere Christianity",
            author: "C.S. Lewis",
            description: "A classic work of Christian apologetics that presents a rational argument for the Christian faith. Lewis explores fundamental questions about belief, morality, and the nature of God.",
            category: "Apologetics",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Mere-Christianity-C-S-Lewis/dp/0060652926",
            isbn: "9780060652920",
            pageCount: 227,
            publisher: "HarperOne",
            isFeatured: true,
            isTrending: true,
            tags: ["apologetics", "classic", "theology", "CS Lewis"]
        ))
        
        books.append(Book(
            title: "The Case for Christ",
            author: "Lee Strobel",
            description: "A journalist's personal investigation of the evidence for Jesus. Drawing on expert testimony, Strobel examines the historical reliability of the Gospels and the resurrection.",
            category: "Apologetics",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Case-Christ-Journalists-Personal-Investigation/dp/0310345863",
            isbn: "9780310345862",
            pageCount: 404,
            publisher: "Zondervan",
            isFeatured: true,
            isTrending: false,
            tags: ["apologetics", "evidence", "resurrection", "historical Jesus"]
        ))
        
        books.append(Book(
            title: "The Reason for God",
            author: "Timothy Keller",
            description: "Engaging both believers and skeptics, Keller addresses common objections to Christianity and presents compelling reasons for faith in the modern world.",
            category: "Apologetics",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Reason-God-Belief-Age-Skepticism/dp/1594483493",
            isbn: "9781594483493",
            pageCount: 336,
            publisher: "Penguin Books",
            isFeatured: false,
            isTrending: true,
            tags: ["apologetics", "skepticism", "faith", "Timothy Keller"]
        ))
        
        // MARK: - Theology Books
        
        books.append(Book(
            title: "Systematic Theology",
            author: "Wayne Grudem",
            description: "A comprehensive introduction to biblical doctrines that is accessible, balanced, and grounded in Scripture. Essential reading for serious students of the Bible.",
            category: "Theology",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Systematic-Theology-Introduction-Biblical-Doctrine/dp/0310286700",
            isbn: "9780310286707",
            pageCount: 1290,
            publisher: "Zondervan",
            isFeatured: true,
            isTrending: false,
            tags: ["theology", "systematic", "doctrine", "Wayne Grudem"]
        ))
        
        books.append(Book(
            title: "Knowing God",
            author: "J.I. Packer",
            description: "A profound exploration of God's nature and character. Packer combines theological depth with practical application, showing how knowing God transforms our daily lives.",
            category: "Theology",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Knowing-God-J-I-Packer/dp/0830816518",
            isbn: "9780830816514",
            pageCount: 319,
            publisher: "InterVarsity Press",
            isFeatured: true,
            isTrending: true,
            tags: ["theology", "God's nature", "Christian living", "J.I. Packer"]
        ))
        
        books.append(Book(
            title: "The Knowledge of the Holy",
            author: "A.W. Tozer",
            description: "Tozer explores the attributes of God, revealing how our view of God affects every aspect of our Christian walk. A transformative book on the majesty of God.",
            category: "Theology",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Knowledge-Holy-Attributes-Their-Meaning/dp/0060684127",
            isbn: "9780060684129",
            pageCount: 128,
            publisher: "HarperOne",
            isFeatured: false,
            isTrending: false,
            tags: ["theology", "God's attributes", "worship", "A.W. Tozer"]
        ))
        
        // MARK: - Devotional Books
        
        books.append(Book(
            title: "My Utmost for His Highest",
            author: "Oswald Chambers",
            description: "Classic daily devotions that have inspired millions of Christians worldwide. Chambers offers profound insights into deepening your relationship with God.",
            category: "Devotional",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/My-Utmost-His-Highest-Updated/dp/0929239571",
            isbn: "9780929239576",
            pageCount: 400,
            publisher: "Discovery House",
            isFeatured: true,
            isTrending: true,
            tags: ["devotional", "daily reading", "spiritual growth", "Oswald Chambers"]
        ))
        
        books.append(Book(
            title: "The Pursuit of God",
            author: "A.W. Tozer",
            description: "A passionate call to intimacy with God. Tozer challenges readers to move beyond intellectual knowledge to experiencing God's presence in daily life.",
            category: "Devotional",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Pursuit-God-Updated-Language-Present/dp/1600661742",
            isbn: "9781600661747",
            pageCount: 128,
            publisher: "Regal",
            isFeatured: true,
            isTrending: false,
            tags: ["devotional", "spiritual intimacy", "worship", "A.W. Tozer"]
        ))
        
        books.append(Book(
            title: "Jesus Calling",
            author: "Sarah Young",
            description: "Daily devotional readings written as if Jesus is speaking directly to you. Offers comfort, encouragement, and hope for each day.",
            category: "Devotional",
            rating: 4,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Jesus-Calling-Enjoying-Peace-Presence/dp/1591451884",
            isbn: "9781591451884",
            pageCount: 432,
            publisher: "Thomas Nelson",
            isFeatured: false,
            isTrending: true,
            tags: ["devotional", "daily reading", "encouragement", "Sarah Young"]
        ))
        
        books.append(Book(
            title: "Streams in the Desert",
            author: "L.B. Cowman",
            description: "A treasured devotional classic providing comfort and encouragement through life's trials. Includes Scripture, poetry, and inspiring stories.",
            category: "Devotional",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Streams-Desert-366-Daily-Devotional/dp/0310262747",
            isbn: "9780310262749",
            pageCount: 400,
            publisher: "Zondervan",
            isFeatured: false,
            isTrending: false,
            tags: ["devotional", "comfort", "trials", "L.B. Cowman"]
        ))
        
        // MARK: - Biography Books
        
        books.append(Book(
            title: "The Hiding Place",
            author: "Corrie ten Boom",
            description: "The remarkable story of Corrie ten Boom and her family who helped Jews escape the Nazi Holocaust. A powerful testimony of faith, forgiveness, and God's faithfulness.",
            category: "Biography",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Hiding-Place-Corrie-Ten-Boom/dp/0800794052",
            isbn: "9780800794057",
            pageCount: 242,
            publisher: "Chosen Books",
            isFeatured: true,
            isTrending: true,
            tags: ["biography", "World War II", "forgiveness", "Corrie ten Boom"]
        ))
        
        books.append(Book(
            title: "Hudson Taylor's Spiritual Secret",
            author: "Dr. and Mrs. Howard Taylor",
            description: "The inspiring biography of Hudson Taylor, missionary to China. Reveals the spiritual principles that guided his remarkable life and ministry.",
            category: "Biography",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Hudson-Taylors-Spiritual-Secret-Howard/dp/0802471935",
            isbn: "9780802471932",
            pageCount: 288,
            publisher: "Moody Publishers",
            isFeatured: false,
            isTrending: false,
            tags: ["biography", "missions", "China", "Hudson Taylor", "faith"]
        ))
        
        books.append(Book(
            title: "George Müller: Man of Faith",
            author: "Basil Miller",
            description: "The story of George Müller who cared for thousands of orphans in Bristol, England, relying entirely on prayer and faith. A testament to God's provision.",
            category: "Biography",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/George-Muller-Man-Faith-Triumph/dp/0871239752",
            isbn: "9780871239754",
            pageCount: 160,
            publisher: "Bethany House",
            isFeatured: false,
            isTrending: false,
            tags: ["biography", "faith", "prayer", "George Müller", "orphans"]
        ))
        
        // MARK: - New Believer Books
        
        books.append(Book(
            title: "The Purpose Driven Life",
            author: "Rick Warren",
            description: "A 40-day spiritual journey that helps you discover God's purpose for your life. Over 50 million copies sold worldwide, transforming lives globally.",
            category: "New Believer",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Purpose-Driven-Life-What-Earth/dp/0310329477",
            isbn: "9780310329473",
            pageCount: 336,
            publisher: "Zondervan",
            isFeatured: true,
            isTrending: true,
            tags: ["new believer", "purpose", "spiritual growth", "Rick Warren"]
        ))
        
        books.append(Book(
            title: "The New Believer's Bible",
            author: "Greg Laurie",
            description: "Perfect for those new to Christianity, this Bible includes helpful notes, reading plans, and guidance for starting your faith journey.",
            category: "New Believer",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/New-Believers-Bible-Greg-Laurie/dp/1414302622",
            isbn: "9781414302621",
            pageCount: 1536,
            publisher: "Tyndale House",
            isFeatured: true,
            isTrending: false,
            tags: ["new believer", "Bible", "study guide", "Greg Laurie"]
        ))
        
        books.append(Book(
            title: "Basic Christianity",
            author: "John Stott",
            description: "A clear, balanced presentation of Christianity's core truths. Ideal for new believers and those exploring the faith.",
            category: "New Believer",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Basic-Christianity-John-Stott/dp/0830834133",
            isbn: "9780830834136",
            pageCount: 160,
            publisher: "InterVarsity Press",
            isFeatured: false,
            isTrending: false,
            tags: ["new believer", "basics", "foundation", "John Stott"]
        ))
        
        books.append(Book(
            title: "The Gospel According to Jesus",
            author: "John MacArthur",
            description: "A clear explanation of the Gospel and what it means to truly follow Christ. Essential reading for understanding biblical discipleship.",
            category: "New Believer",
            rating: 5,
            coverImageURL: nil,
            purchaseURL: "https://www.amazon.com/Gospel-According-Jesus-Anniversary/dp/0310285038",
            isbn: "9780310285038",
            pageCount: 304,
            publisher: "Zondervan",
            isFeatured: false,
            isTrending: true,
            tags: ["new believer", "gospel", "discipleship", "John MacArthur"]
        ))
        
        return books
    }
    
    /// Delete all books (USE WITH CAUTION!)
    @MainActor
    func clearAllBooks() async throws {
        print("🗑️ WARNING: Deleting all books from database...")
        
        let books = try await service.fetchAllBooks()
        
        for book in books {
            if let bookId = book.id {
                try await service.deleteBook(id: bookId)
                print("🗑️ Deleted: \(book.title)")
            }
        }
        
        print("✅ All books deleted")
    }
}

// MARK: - How to Use

/*
 
 To seed your Firebase database with sample books, run this code once:
 
 ```swift
 Task {
     do {
         try await BookDataSeeder.shared.seedBooks()
     } catch {
         print("❌ Error seeding books: \(error)")
     }
 }
 ```
 
 You can add this to a debug menu in your app, or run it once in your app's initialization.
 
 ⚠️ IMPORTANT: Only run this ONCE or you'll get duplicate books!
 
 To clear all books (be careful!):
 
 ```swift
 Task {
     do {
         try await BookDataSeeder.shared.clearAllBooks()
     } catch {
         print("❌ Error clearing books: \(error)")
     }
 }
 ```
 
 */
