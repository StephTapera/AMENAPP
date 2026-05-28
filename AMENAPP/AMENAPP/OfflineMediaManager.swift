// OfflineMediaManager.swift
// AMENAPP
//
// Metadata tracker and simulated download manager for offline media saves.
// Real download integration (URLSession, background transfers) is deferred to a
// production backend service. This layer tracks what is saved, drives UI progress,
// and persists metadata to UserDefaults.
//
// Gated by AMENFeatureFlags.shared.mediaLowBandwidthModeEnabled

import Combine
import Foundation
import SwiftUI

// MARK: - Models

struct OfflineMediaItem: Identifiable, Codable {
    /// Matches `mediaId` for stable identity across sessions.
    let id: String
    let postId: String
    let mediaId: String
    let title: String?
    /// The bandwidth mode the item was saved under.
    let savedMode: LowBandwidthMediaMode
    let savedAt: Date
    let fileSizeBytes: Int?
    /// True when the metadata record exists and the file is considered present on disk.
    var isAvailable: Bool
}

struct OfflineDownloadProgress: Identifiable {
    let id: String  // = mediaId
    var fractionCompleted: Double
    var isIndeterminate: Bool
    var error: String?
}

// MARK: - Manager

@MainActor
final class OfflineMediaManager: ObservableObject {

    // MARK: Singleton

    static let shared = OfflineMediaManager()

    // MARK: Published State

    @Published private(set) var downloadedItems: [OfflineMediaItem] = []
    @Published private(set) var activeDownloads: [String: OfflineDownloadProgress] = [:]

    // MARK: Private

    private static let defaultsKey = "amen_offline_items"
    private var timers: [String: AnyCancellable] = [:]

    // MARK: Init

    private init() {
        loadFromDefaults()
    }

    // MARK: - Public API

    /// Begins a simulated offline save for the given media item.
    /// Tracks progress from 0 → 1 over ~2 seconds, then marks the item as available.
    /// No-op if the feature flag is off or the item is already downloaded/downloading.
    func saveForOffline(
        postId: String,
        mediaId: String,
        title: String?,
        mode: LowBandwidthMediaMode
    ) async {
        guard AMENFeatureFlags.shared.mediaLowBandwidthModeEnabled else { return }
        guard !isDownloaded(mediaId: mediaId) else { return }
        guard activeDownloads[mediaId] == nil else { return }

        // Create progress entry
        let progress = OfflineDownloadProgress(
            id: mediaId,
            fractionCompleted: 0,
            isIndeterminate: false,
            error: nil
        )
        activeDownloads[mediaId] = progress

        // Track analytics
        AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "offline_save"))

        // Simulate download with a repeating timer (tick every 100 ms, completes in ~2 s)
        let tickInterval: TimeInterval = 0.1
        let totalTicks: Double = 20  // 20 × 0.1 s = 2 s
        var ticks: Double = 0

        timers[mediaId] = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                ticks += 1
                let fraction = min(ticks / totalTicks, 1.0)

                if var current = self.activeDownloads[mediaId] {
                    current.fractionCompleted = fraction
                    self.activeDownloads[mediaId] = current
                }

                if ticks >= totalTicks {
                    self.timers[mediaId]?.cancel()
                    self.timers[mediaId] = nil
                    self.activeDownloads.removeValue(forKey: mediaId)

                    let item = OfflineMediaItem(
                        id: mediaId,
                        postId: postId,
                        mediaId: mediaId,
                        title: title,
                        savedMode: mode,
                        savedAt: Date(),
                        fileSizeBytes: self.estimatedBytes(for: mode),
                        isAvailable: true
                    )
                    self.downloadedItems.append(item)
                    self.persistToDefaults()
                }
            }
    }

    /// Cancels an in-progress download. Does nothing if no download is active.
    func cancelDownload(mediaId: String) {
        timers[mediaId]?.cancel()
        timers[mediaId] = nil
        activeDownloads.removeValue(forKey: mediaId)
    }

    /// Removes a saved item from the in-memory list and UserDefaults.
    func removeOfflineItem(mediaId: String) {
        cancelDownload(mediaId: mediaId)
        downloadedItems.removeAll { $0.mediaId == mediaId }
        persistToDefaults()
        AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "offline_remove"))
    }

    /// Returns true when the item is present in `downloadedItems` and marked available.
    func isDownloaded(mediaId: String) -> Bool {
        downloadedItems.contains { $0.mediaId == mediaId && $0.isAvailable }
    }

    /// Returns live download progress for an in-flight download, or nil.
    func downloadProgress(for mediaId: String) -> OfflineDownloadProgress? {
        activeDownloads[mediaId]
    }

    // MARK: - Persistence

    private func persistToDefaults() {
        guard let data = try? JSONEncoder().encode(downloadedItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func loadFromDefaults() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let items = try? JSONDecoder().decode([OfflineMediaItem].self, from: data)
        else { return }
        downloadedItems = items
    }

    // MARK: - Helpers

    private func estimatedBytes(for mode: LowBandwidthMediaMode) -> Int {
        switch mode {
        case .automatic:          return 25_000_000   // ~25 MB
        case .lowQualityVideo:    return 12_000_000   // ~12 MB
        case .audioOnly:          return  4_000_000   //  ~4 MB
        case .transcriptOnly:     return     50_000   //  ~50 KB
        case .wifiOnly:           return 25_000_000   // ~25 MB (same as automatic)
        }
    }
}
