// AmenLibraryCatalogProvider.swift
// AMENAPP

import Foundation
import FirebaseFirestore

// MARK: - Protocol

protocol AmenLibraryCatalogProvider {
    func fetchFeatured() async throws -> [WLBook]
    func fetchByCategory(_ category: WLBookCategory, maxResults: Int) async throws -> [WLBook]
    func search(query: String, maxResults: Int) async throws -> [WLBook]
    func fetchByIds(_ ids: [String]) async throws -> [WLBook]
}

// MARK: - Mock Provider (tests + previews)

final class MockAmenLibraryCatalogProvider: AmenLibraryCatalogProvider {

    var mockBooks: [WLBook] = GoogleBooksService.fallbackCatalog

    func fetchFeatured() async throws -> [WLBook] {
        mockBooks.filter { $0.isFeatured }
    }

    func fetchByCategory(_ category: WLBookCategory, maxResults: Int) async throws -> [WLBook] {
        Array(mockBooks
            .filter { $0.curatedTags.contains { $0.localizedCaseInsensitiveContains(category.rawValue) } }
            .prefix(maxResults))
    }

    func search(query: String, maxResults: Int) async throws -> [WLBook] {
        let q = query.lowercased()
        return Array(mockBooks
            .filter { $0.title.lowercased().contains(q) || $0.authors.joined().lowercased().contains(q) }
            .prefix(maxResults))
    }

    func fetchByIds(_ ids: [String]) async throws -> [WLBook] {
        mockBooks.filter { ids.contains($0.id) }
    }
}

// MARK: - Google Books Provider

final class GoogleBooksAmenCatalogProvider: AmenLibraryCatalogProvider {

    private let service = GoogleBooksService.shared

    func fetchFeatured() async throws -> [WLBook] {
        try await service.search(query: "christian bestseller recommended", maxResults: 12)
    }

    func fetchByCategory(_ category: WLBookCategory, maxResults: Int) async throws -> [WLBook] {
        try await service.search(query: category.googleQuery, maxResults: maxResults)
    }

    func search(query: String, maxResults: Int) async throws -> [WLBook] {
        try await service.search(query: query, maxResults: maxResults)
    }

    func fetchByIds(_ ids: [String]) async throws -> [WLBook] {
        // Google Books has no batch-by-id endpoint; fetch each individually
        var results: [WLBook] = []
        for id in ids.prefix(10) {
            if let book = try? await service.fetchById(id) {
                results.append(book)
            }
        }
        return results
    }
}

// MARK: - Firestore Provider (future: church sermon library, curated publisher feeds)

final class FirestoreAmenCatalogProvider: AmenLibraryCatalogProvider {

    private let db = Firestore.firestore()

    // Reads from amenLibrary collection; Apple Books affiliate links + church sermon sources planned.

    func fetchFeatured() async throws -> [WLBook] {
        let snap = try await db.collection("amenLibrary")
            .whereField("isFeatured", isEqualTo: true)
            .limit(to: 20)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: WLBook.self) }
    }

    func fetchByCategory(_ category: WLBookCategory, maxResults: Int) async throws -> [WLBook] {
        let snap = try await db.collection("amenLibrary")
            .whereField("curatedTags", arrayContains: category.rawValue)
            .limit(to: maxResults)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: WLBook.self) }
    }

    func search(query: String, maxResults: Int) async throws -> [WLBook] {
        // Full-text search requires Algolia amenLibrary index (not yet indexed).
        return []
    }

    func fetchByIds(_ ids: [String]) async throws -> [WLBook] {
        guard !ids.isEmpty else { return [] }
        let snap = try await db.collection("amenLibrary")
            .whereField(FieldPath.documentID(), in: Array(ids.prefix(10)))
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: WLBook.self) }
    }
}
