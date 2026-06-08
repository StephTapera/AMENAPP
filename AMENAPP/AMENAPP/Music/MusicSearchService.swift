// MUSIC FEATURE — Agent B
// MusicSearchService.swift
// AMENAPP
//
// Observable service that wraps Firebase Cloud Functions for music search
// and trending tracks. Falls back to .sample on any network or decode error.

import Foundation
import FirebaseFunctions

@MainActor
final class MusicSearchService: ObservableObject {
    @Published private(set) var trendingTracks: [MusicAttachment] = []
    @Published private(set) var searchResults: [MusicAttachment] = []
    @Published private(set) var isLoading = false

    private let functions = Functions.functions()

    // MARK: - Public API

    func loadTrending() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("getMusicTrending").call([:])
            trendingTracks = decodeTracks(from: result.data)
        } catch {
            trendingTracks = [.sample]
        }
    }

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("searchMusic").call(["query": query])
            searchResults = decodeTracks(from: result.data)
        } catch {
            searchResults = [.sample]
        }
    }

    // MARK: - Decoding

    private func decodeTracks(from data: Any?) -> [MusicAttachment] {
        guard let dict = data as? [String: Any],
              let tracksData = dict["tracks"],
              let jsonData = try? JSONSerialization.data(withJSONObject: tracksData),
              let tracks = try? JSONDecoder().decode([MusicAttachment].self, from: jsonData)
        else { return [.sample] }
        return tracks
    }
}
