// ConnectDiscoveryFeedService.swift
// AMEN Connect Discovery Engine — Wave 2
// Decodes DiscoveryFeed from assembleDiscoveryFeed CF.
// Refuses to surface any card lacking a valid SafetyStamp.
// Renamed from DiscoveryService to avoid clash with existing DiscoveryService (universal search).

import Foundation
import FirebaseFunctions

@MainActor
final class ConnectDiscoveryFeedService {

    static let shared = ConnectDiscoveryFeedService()

    private let functions = Functions.functions(region: "us-east1")
    private let decoder = JSONDecoder.discoveryDecoder

    // MARK: - Feed

    func fetchFeed(
        geohash: String? = nil,
        interests: [String] = [],
        feedToken: String? = nil,
        categoryFilter: String? = nil
    ) async throws -> DiscoveryFeed {
        let callable = functions.httpsCallable("assembleDiscoveryFeed")
        var params: [String: Any] = [:]
        if let gh = geohash        { params["geohash"] = gh }
        if !interests.isEmpty      { params["interests"] = interests }
        if let ft = feedToken      { params["feedToken"] = ft }
        if let cf = categoryFilter { params["categoryFilter"] = cf }

        let result = try await callable.call(params)
        let feed = try decodeResult(result.data, as: DiscoveryFeed.self)
        return validated(feed)
    }

    // MARK: - Search

    func search(query: String = "", geohash: String? = nil, interests: [String] = []) async throws -> ConnectDiscoverySearchResult {
        let callable = functions.httpsCallable("searchDiscovery")
        var params: [String: Any] = ["query": query]
        if let gh = geohash      { params["geohash"] = gh }
        if !interests.isEmpty    { params["interests"] = interests }

        let result = try await callable.call(params)
        let searchResult = try decodeResult(result.data, as: ConnectDiscoverySearchResult.self)
        return validatedSearch(searchResult)
    }

    // MARK: - Decode helper

    private func decodeResult<T: Decodable>(_ data: Any, as type: T.Type) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try decoder.decode(type, from: jsonData)
    }

    // MARK: - Safety validation (client-side second gate)
    // Cards without a valid SafetyStamp are dropped here and logged as contract violations.

    private func validated(_ feed: DiscoveryFeed) -> DiscoveryFeed {
        let safeHero = feed.hero.filter { $0.card.safety.isValid }
        let safeShelves = feed.shelves.map { shelf in
            DiscoveryShelf(
                id: shelf.id,
                kind: shelf.kind,
                title: shelf.title,
                subtitle: shelf.subtitle,
                style: shelf.style,
                items: shelf.items.filter { card in
                    guard card.safety.isValid else {
                        ConnectDiscoveryTelemetry.logUnsafeCardDropped(cardId: card.id, cardType: card.type)
                        return false
                    }
                    return true
                }
            )
        }.filter { !$0.items.isEmpty }

        return DiscoveryFeed(
            generatedAt: feed.generatedAt,
            hero: safeHero,
            shelves: safeShelves,
            calmCap: feed.calmCap,
            feedToken: feed.feedToken
        )
    }

    private func validatedSearch(_ result: ConnectDiscoverySearchResult) -> ConnectDiscoverySearchResult {
        ConnectDiscoverySearchResult(
            suggested: result.suggested.filter { $0.safety.isValid },
            browseShelves: result.browseShelves.map { shelf in
                DiscoveryShelf(
                    id: shelf.id,
                    kind: shelf.kind,
                    title: shelf.title,
                    subtitle: shelf.subtitle,
                    style: shelf.style,
                    items: shelf.items.filter { $0.safety.isValid }
                )
            }.filter { !$0.items.isEmpty },
            matches: result.matches.filter { $0.safety.isValid }
        )
    }
}

// MARK: - Telemetry stub (wired in Wave 4)

enum ConnectDiscoveryTelemetry {
    static func logUnsafeCardDropped(cardId: String, cardType: DiscoveryCardType) {
        // TODO Wave 4: route through AmenAnalyticsService with hashed cardId
    }
}
