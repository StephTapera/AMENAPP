// ChristianMediaViewModel.swift — ViewModel for the Christian Media feature

import Foundation
import SwiftUI
import Combine
import AVFoundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ChristianMediaViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentItem: MediaItem? = nil
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0.0
    @Published var selectedTab: MediaTab = .forYou
    @Published var selectedFilter: MediaFilterType = .all
    @Published var items: [MediaItem] = []
    @Published var libraryItems: [MediaItem] = []
    @Published var isLoading: Bool = false
    @Published var showPlayer: Bool = false
    @Published var loadError: String? = nil
    @Published var playbackSpeed: Float = 1.0
    var player: AVPlayer?

    // MARK: - Computed Properties

    var filteredItems: [MediaItem] {
        let base: [MediaItem]
        if selectedFilter == .all {
            base = items
        } else {
            base = items.filter { $0.type == selectedFilter }
        }
        return base.sorted { $0.publishedDate > $1.publishedDate }
    }

    var forYouItems: [MediaItem] {
        // Determine user preference based on bookmarked types
        let bookmarkedTypes = libraryItems.filter { $0.isBookmarked }.map { $0.type }
        var typeWeights: [MediaFilterType: Int] = [:]
        for type in bookmarkedTypes {
            typeWeights[type, default: 0] += 1
        }

        let sorted = items.sorted { a, b in
            let weightA = typeWeights[a.type] ?? 0
            let weightB = typeWeights[b.type] ?? 0
            if weightA != weightB { return weightA > weightB }
            return a.publishedDate > b.publishedDate
        }
        return Array(sorted.prefix(20))
    }

    var displayItems: [MediaItem] {
        switch selectedTab {
        case .forYou:    return forYouItems
        case .discover:  return filteredItems
        case .library:   return libraryItems
        }
    }

    // MARK: - Content Loading

    func loadContent() async {
        isLoading = true
        loadError = nil

        do {
            let fetched = await MediaService.shared.fetchAll()
            guard !fetched.isEmpty else { throw MediaError.emptyResponse }
            items = fetched
            MediaService.shared.cacheItems(fetched)
            isLoading = false
        } catch {
            dlog("ChristianMediaViewModel: loadContent error — \(error.localizedDescription)")
            loadError = "Couldn't load content. Showing cached results."
            isLoading = false

            if let cached = MediaService.shared.cachedItems(), !cached.isEmpty {
                items = cached
            } else {
                items = MediaItem.sampleItems
            }
        }
    }

    func loadLibrary() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("ChristianMediaViewModel: loadLibrary called but user not authenticated")
            return
        }

        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("users")
                .document(uid)
                .collection("bookmarkedMedia")
                .order(by: "savedAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            libraryItems = snapshot.documents.compactMap { doc -> MediaItem? in
                let data = doc.data()
                guard
                    let itemId = data["itemId"] as? String,
                    let title = data["title"] as? String,
                    let author = data["author"] as? String,
                    let typeRaw = data["type"] as? String,
                    let type = MediaFilterType(rawValue: typeRaw),
                    let contentURL = data["contentURL"] as? String,
                    let sourceTypeRaw = data["sourceType"] as? String,
                    let sourceType = MediaSource(rawValue: sourceTypeRaw)
                else { return nil }

                let savedAt = (data["savedAt"] as? Timestamp)?.dateValue() ?? Date()

                return MediaItem(
                    id: itemId,
                    title: title,
                    author: author,
                    channelOrShow: data["channelOrShow"] as? String ?? author,
                    type: type,
                    duration: data["duration"] as? String ?? "",
                    thumbnailURL: data["thumbnailURL"] as? String ?? "",
                    contentURL: contentURL,
                    sourceType: sourceType,
                    scriptureRef: data["scriptureRef"] as? String,
                    publishedDate: savedAt,
                    isBookmarked: true,
                    dominantColor: data["dominantColor"] as? String ?? "#7C3AED"
                )
            }
        } catch {
            dlog("ChristianMediaViewModel: loadLibrary error — \(error.localizedDescription)")
        }
    }

    // MARK: - Playback

    func play(_ item: MediaItem) {
        currentItem = item
        isPlaying = true
        progress = 0.0
        showPlayer = true

        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let historyRef = db.collection("users")
            .document(uid)
            .collection("mediaHistory")
            .document(item.id)

        historyRef.setData([
            "itemId": item.id,
            "title": item.title,
            "author": item.author,
            "type": item.type.rawValue,
            "watchedAt": FieldValue.serverTimestamp(),
            "completed": false
        ], merge: true) { error in
            if let error = error {
                dlog("ChristianMediaViewModel: Failed to record media history — \(error.localizedDescription)")
            }
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            player?.play()
            player?.rate = playbackSpeed
        } else {
            player?.pause()
        }
    }

    func toggleBookmark(_ item: MediaItem) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("ChristianMediaViewModel: toggleBookmark called but user not authenticated")
            return
        }

        let db = Firestore.firestore()
        let bookmarkRef = db.collection("users")
            .document(uid)
            .collection("bookmarkedMedia")
            .document(item.id)

        if item.isBookmarked {
            // Remove bookmark
            do {
                try await bookmarkRef.delete()
                updateItemBookmark(id: item.id, isBookmarked: false)
                libraryItems.removeAll { $0.id == item.id }
            } catch {
                dlog("ChristianMediaViewModel: Failed to remove bookmark — \(error.localizedDescription)")
            }
        } else {
            // Add bookmark
            let data: [String: Any] = [
                "itemId": item.id,
                "type": item.type.rawValue,
                "savedAt": FieldValue.serverTimestamp(),
                "sourceType": item.sourceType.rawValue,
                "contentURL": item.contentURL,
                "title": item.title,
                "author": item.author,
                "channelOrShow": item.channelOrShow,
                "thumbnailURL": item.thumbnailURL,
                "duration": item.duration,
                "dominantColor": item.dominantColor,
                "scriptureRef": item.scriptureRef as Any
            ]
            do {
                try await bookmarkRef.setData(data)
                updateItemBookmark(id: item.id, isBookmarked: true)
                var bookmarkedVersion = item
                bookmarkedVersion.isBookmarked = true
                if !libraryItems.contains(where: { $0.id == item.id }) {
                    libraryItems.insert(bookmarkedVersion, at: 0)
                }
            } catch {
                dlog("ChristianMediaViewModel: Failed to add bookmark — \(error.localizedDescription)")
            }
        }
    }

    func updateProgress(_ p: Double) {
        progress = max(0, min(1, p))
    }

    func markCompleted(_ item: MediaItem) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        db.collection("users")
            .document(uid)
            .collection("mediaHistory")
            .document(item.id)
            .setData(["completed": true, "completedAt": FieldValue.serverTimestamp()], merge: true) { error in
                if let error = error {
                    dlog("ChristianMediaViewModel: Failed to mark completed — \(error.localizedDescription)")
                }
            }
    }

    func skipForward() {
        guard let player = player else { return }
        let current = player.currentTime().seconds
        let target = min(current + 30, player.currentItem?.duration.seconds ?? current)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skipBack() {
        guard let player = player else { return }
        let current = player.currentTime().seconds
        let target = max(current - 15, 0)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardownPlayer() {
        player?.pause()
        player = nil
        isPlaying = false
        progress = 0.0
    }

    func nextItem() {
        guard let current = currentItem,
              let index = displayItems.firstIndex(where: { $0.id == current.id }),
              index + 1 < displayItems.count else { return }
        play(displayItems[index + 1])
    }

    func previousItem() {
        guard let current = currentItem,
              let index = displayItems.firstIndex(where: { $0.id == current.id }),
              index - 1 >= 0 else { return }
        play(displayItems[index - 1])
    }

    // MARK: - Private Helpers

    private func updateItemBookmark(id: String, isBookmarked: Bool) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isBookmarked = isBookmarked
        }
    }
}

// MARK: - Errors
private enum MediaError: Error {
    case emptyResponse
}
