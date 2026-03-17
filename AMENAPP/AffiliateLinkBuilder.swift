// AffiliateLinkBuilder.swift
// AMENAPP
//
// Generates Amazon Associates and Apple Books affiliate links for a WLBook.
//
// Setup:
//   Amazon: apply at affiliate-program.amazon.com → set AMAZON_AFFILIATE_TAG in Config.xcconfig
//   Apple:  apply at affiliate.itunes.apple.com   → set APPLE_AFFILIATE_TOKEN in Config.xcconfig
//
// Both are free to join. Amazon pays ~4–10%, Apple ~7% on qualifying purchases.

import Foundation
import UIKit

// MARK: - Config

enum AffiliateConfig {
    static let amazonTag: String = Bundle.main.object(
        forInfoDictionaryKey: "AMAZON_AFFILIATE_TAG") as? String ?? "amenapp-20"
    static let appleToken: String = Bundle.main.object(
        forInfoDictionaryKey: "APPLE_AFFILIATE_TOKEN") as? String ?? ""

    /// Amazon requires a visible disclosure wherever affiliate links appear.
    static let disclosure = "AMEN may earn a commission from qualifying purchases."
}

// MARK: - Builder

enum AffiliateLinkBuilder {

    // MARK: Amazon

    static func amazonURL(for book: WLBook) -> URL? {
        let tag = AffiliateConfig.amazonTag
        if let isbn = book.isbn13 ?? book.isbn10 {
            var c = URLComponents(string: "https://www.amazon.com/dp/\(isbn)")!
            c.queryItems = [.init(name: "tag", value: tag)]
            return c.url
        }
        // Fallback: Amazon search
        var c = URLComponents(string: "https://www.amazon.com/s")!
        c.queryItems = [
            .init(name: "k",   value: "\(book.title) \(book.primaryAuthor)"),
            .init(name: "i",   value: "stripbooks"),
            .init(name: "tag", value: tag)
        ]
        return c.url
    }

    // MARK: Apple Books

    static func appleBooksURL(for book: WLBook) -> URL? {
        let token = AffiliateConfig.appleToken
        let suffix = token.isEmpty ? "" : "?at=\(token)"
        if let isbn13 = book.isbn13 {
            return URL(string: "https://books.apple.com/us/book/isbn\(isbn13)\(suffix)")
        }
        var c = URLComponents(string: "https://books.apple.com/us/search")!
        var items: [URLQueryItem] = [
            .init(name: "term", value: "\(book.title) \(book.primaryAuthor)")
        ]
        if !token.isEmpty { items.append(.init(name: "at", value: token)) }
        c.queryItems = items
        return c.url
    }

    // MARK: Open

    static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:])
    }

    static func openAmazon(for book: WLBook) {
        guard let url = amazonURL(for: book) else { return }
        open(url)
        WLBookAnalytics.trackOutbound(book: book, destination: .amazon)
    }

    static func openAppleBooks(for book: WLBook) {
        guard let url = appleBooksURL(for: book) else { return }
        open(url)
        WLBookAnalytics.trackOutbound(book: book, destination: .appleBooks)
    }
}

// MARK: - Analytics

enum WLBookAnalytics {
    enum Destination: String { case amazon, appleBooks }

    static func trackOutbound(book: WLBook, destination: Destination) {
        dlog("📚 Outbound → \(destination.rawValue): \(book.title)")
    }
    static func trackSave(book: WLBook) { dlog("📚 Saved: \(book.title)") }
    static func trackDetailOpen(book: WLBook, source: String) {
        dlog("📚 Detail [\(source)]: \(book.title)")
    }
}
