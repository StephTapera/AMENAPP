// AMENMediaService.swift
// AMENAPP
//
// YouTube Data API v3 + Spotify Web API service layer.
// All network calls are off the main thread.
// Results are cached in-memory per session.

import Foundation
import FirebaseFunctions

// MARK: - Configuration

private enum MediaAPIConfig {
    /// Set YOUTUBE_API_KEY in Config.xcconfig
    static var youtubeAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_API_KEY") as? String ?? "").trimmingCharacters(in: .whitespaces)
    }
    /// Set SPOTIFY_CLIENT_ID in Config.xcconfig.
    /// The client secret is NOT read from the client — Spotify token exchange
    /// must go through the spotifyTokenProxy Cloud Function (P0-2 fix 2026-06-03).
    static var spotifyClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String ?? ""
    }
}

// MARK: - Cache Actor

private actor MediaCache {
    private var sermons: [String: [AMENSermon]] = [:]
    private var episodes: [String: [AMENPodcastEpisode]] = [:]

    func getSermons(_ key: String) -> [AMENSermon]? { sermons[key] }
    func setSermons(_ key: String, _ value: [AMENSermon]) { sermons[key] = value }
    func getEpisodes(_ key: String) -> [AMENPodcastEpisode]? { episodes[key] }
    func setEpisodes(_ key: String, _ value: [AMENPodcastEpisode]) { episodes[key] = value }
    func clear() { sermons.removeAll(); episodes.removeAll() }
}

// MARK: - Service

final class AMENMediaService: @unchecked Sendable {
    static let shared = AMENMediaService()
    private init() {}

    private let cache = MediaCache()
    private var spotifyToken: String?
    private var spotifyTokenExpiry: Date = .distantPast
    private let session = URLSession.shared
    private let functions = Functions.functions()

    // MARK: - YouTube Sermons

    /// Search YouTube for Christian sermons matching `query`.
    /// Returns curated content immediately if the API key is missing.
    func searchSermons(query: String, maxResults: Int = 10) async -> [AMENSermon] {
        let key = "yt:\(query):\(maxResults)"
        if let cached = await cache.getSermons(key) { return cached }

        let apiKey = MediaAPIConfig.youtubeAPIKey
        guard !apiKey.isEmpty else { return AMENSermon.curated }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            .init(name: "part",        value: "snippet"),
            .init(name: "q",           value: "\(query) sermon Christian"),
            .init(name: "type",        value: "video"),
            .init(name: "maxResults",  value: "\(maxResults)"),
            .init(name: "relevanceLanguage", value: "en"),
            .init(name: "safeSearch",  value: "strict"),
            .init(name: "key",         value: apiKey)
        ]

        guard let url = components.url else { return AMENSermon.curated }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            let sermons = response.items.compactMap { item -> AMENSermon? in
                guard let videoID = item.id.videoId else { return nil }
                return AMENSermon(
                    id: videoID,
                    title: item.snippet.title.htmlDecoded,
                    speaker: "",
                    church: item.snippet.channelTitle,
                    topic: query,
                    youtubeVideoID: videoID,
                    thumbnailURL: item.snippet.thumbnails.bestURL,
                    durationSeconds: nil,
                    publishedAt: ISO8601DateFormatter().date(from: item.snippet.publishedAt),
                    description: item.snippet.description,
                    scriptureReference: nil,
                    series: nil,
                    viewCount: nil
                )
            }
            let result = sermons.isEmpty ? AMENSermon.curated : sermons
            await cache.setSermons(key, result)
            return result
        } catch {
            return AMENSermon.curated
        }
    }

    /// Fetch curated sermons for the home carousel (uses curated seed list if no API key).
    func fetchFeaturedSermons() async -> [AMENSermon] {
        let key = "yt:featured"
        if let cached = await cache.getSermons(key) { return cached }
        let result = await searchSermons(query: "sermon faith 2025", maxResults: 8)
        await cache.setSermons(key, result)
        return result
    }

    // MARK: - Spotify Podcasts

    /// Search Spotify for Christian podcast episodes.
    func searchPodcasts(query: String, maxResults: Int = 10) async -> [AMENPodcastEpisode] {
        let key = "sp:\(query):\(maxResults)"
        if let cached = await cache.getEpisodes(key) { return cached }

        let clientID = MediaAPIConfig.spotifyClientID
        // Token exchange moved server-side (spotifyTokenProxy CF). Client secret removed (P0-2).
        guard !clientID.isEmpty, let token = await fetchSpotifyToken(clientID: clientID) else {
            return AMENPodcastEpisode.curated
        }

        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            .init(name: "q",      value: "\(query) Christian"),
            .init(name: "type",   value: "episode"),
            .init(name: "market", value: "US"),
            .init(name: "limit",  value: "\(maxResults)")
        ]

        guard let url = components.url else { return AMENPodcastEpisode.curated }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
            let episodes = (response.episodes?.items ?? []).map { item -> AMENPodcastEpisode in
                AMENPodcastEpisode(
                    id: item.id,
                    title: item.name,
                    showName: item.show?.name ?? "Christian Podcast",
                    host: item.show?.publisher ?? "",
                    thumbnailURL: item.thumbnailURL,
                    durationSeconds: item.durationSeconds,
                    publishedAt: Self.parseSpotifyDate(item.release_date),
                    description: item.description,
                    spotifyEpisodeID: item.id,
                    spotifyShowID: item.show?.id,
                    rssAudioURL: nil,
                    topic: query
                )
            }
            let result = episodes.isEmpty ? AMENPodcastEpisode.curated : episodes
            await cache.setEpisodes(key, result)
            return result
        } catch {
            return AMENPodcastEpisode.curated
        }
    }

    func fetchFeaturedPodcasts() async -> [AMENPodcastEpisode] {
        let key = "sp:featured"
        if let cached = await cache.getEpisodes(key) { return cached }
        let result = await searchPodcasts(query: "sermon faith", maxResults: 6)
        await cache.setEpisodes(key, result)
        return result
    }

    // MARK: - Spotify Track Search (for WorshipSongPickerSheet)

    /// Search Spotify for tracks by name/artist. Returns up to `maxResults` results.
    /// Used by the worship song picker to let users attach Spotify tracks to Church Notes.
    func searchSpotifyTracks(query: String, maxResults: Int = 15) async -> [SpotifyTrackItem] {
        let clientID = MediaAPIConfig.spotifyClientID
        guard !clientID.isEmpty, let token = await fetchSpotifyToken(clientID: clientID) else {
            return []
        }

        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            .init(name: "q",      value: query),
            .init(name: "type",   value: "track"),
            .init(name: "market", value: "US"),
            .init(name: "limit",  value: "\(maxResults)")
        ]

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(SpotifyTrackSearchResponse.self, from: data)
            return response.tracks?.items ?? []
        } catch {
            return []
        }
    }


    // MARK: - Spotify Token (Client Credentials)

    // Calls `spotifyTokenProxy` CF. The Spotify client secret stays server-side.
    private func fetchSpotifyToken(clientID: String) async -> String? {
        if let spotifyToken, spotifyTokenExpiry > Date().addingTimeInterval(60) {
            return spotifyToken
        }

        do {
            let result = try await functions.httpsCallable("spotifyTokenProxy").safeCall([
                "clientId": clientID,
            ])
            guard let payload = result.data as? [String: Any] else { return nil }
            let token = payload["accessToken"] as? String ?? payload["token"] as? String
            guard let token, !token.isEmpty else { return nil }

            let expiresInDirect: TimeInterval? = (payload["expiresIn"] as? TimeInterval)
                ?? (payload["expires_in"] as? TimeInterval)
            let expiresInFromInt: TimeInterval? = (payload["expiresIn"] as? Int).map(TimeInterval.init)
                ?? (payload["expires_in"] as? Int).map(TimeInterval.init)
            let expiresIn: TimeInterval = expiresInDirect ?? expiresInFromInt ?? 3_000

            spotifyToken = token
            spotifyTokenExpiry = Date().addingTimeInterval(max(300, expiresIn))
            return token
        } catch {
            dlog("⚠️ [AMENMediaService] Spotify token proxy failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private static func parseSpotifyDate(_ string: String) -> Date? {
        let formats = ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
        for fmt in formats {
            let df = DateFormatter()
            df.dateFormat = fmt
            if let date = df.date(from: string) { return date }
        }
        return nil
    }

    func clearCache() {
        Task { await cache.clear() }
    }
}

// MARK: - String HTML decode helper

private extension String {
    var htmlDecoded: String {
        guard self.contains("&") else { return self }
        let replacements: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")
        ]
        var result = self
        for (entity, char) in replacements {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}
