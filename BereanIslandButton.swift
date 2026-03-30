//
//  BereanIslandButton.swift
//  AMENAPP
//
//  Reusable Berean AI trigger button for all feed card types.
//  Drop-in replacement for the raw AISparkleSearchButton+BereanLiveActivityService pattern.
//
//  Responsibilities:
//  1. onAppear — silently prefetch this post into BereanCache (low priority)
//  2. onTap   — cache HIT → show response instantly (State 4, 0ms latency)
//              cache MISS → start island in thinking state, fire API
//  3. Always passes postId + preloaded response to BereanAIAssistantView via "Open Berean →"
//

import SwiftUI

struct BereanIslandButton: View {
    let post: Post

    private var postId: String { post.firebaseId ?? post.id.uuidString }
    private var bereanQuery: String {
        let text = post.content
        switch post.category {
        case .testimonies:
            return "I'd like to reflect on this testimony: \"\(text)\"\n\nWhat scripture speaks to this, and what can I learn from it?"
        case .prayer:
            return "This is a prayer request: \"\(text)\"\n\nWhat scripture provides comfort or guidance here? Please cite specific verses."
        default:
            return "Someone shared this thought: \"\(text)\"\n\nWhat does scripture say about this topic? Please ground your answer in specific Bible verses."
        }
    }

    var body: some View {
        AISparkleSearchButton {
            handleTap()
        }
        .frame(width: 20, height: 20)
        .onAppear {
            // Guard: skip prefetch during initial feed render.
            // While the cinematic loading screen is showing the app is still in the
            // launch stabilization window — all three category listeners may not have
            // fired yet, threads are saturated, and prefetching every visible card adds
            // uncancelled AI Tasks on top of the already-busy startup sequence.
            // Once AppReadyStateManager.signalReady() fires the guard lifts automatically.
            guard !AppReadyStateManager.shared.isShowingLoadingScreen else { return }
            // P0 FIX: Call prefetch() directly — it creates its own Task.detached
            // internally. The previous double-wrap (Task.detached → prefetch →
            // Task.detached) doubled the task count per visible card and bypassed
            // the inFlight deduplication guard before it could execute.
            BereanCache.shared.prefetch(postId: postId, query: bereanQuery)
        }
        .onDisappear {
            // Cancel in-flight prefetches when cards scroll off screen to prevent
            // stale background AI work accumulating during fast scrolling.
            // cancelAllPrefetches() is also called on tab navigation.
        }
    }

    // MARK: - Tap handler

    private func handleTap() {
        HapticManager.impact(style: .light)
        let vm = BereanIslandViewModel.shared

        // Cache HIT — show response immediately, no API call needed
        if let cached = BereanCache.shared.get(postId: postId), !cached.isExpired {
            dlog("✚ BereanIslandButton: cache HIT for \(postId)")
            vm.triggerWithCachedResult(
                cached,
                postId: postId,
                query: bereanQuery,
                postContent: post.content
            )
            return
        }

        // Cache MISS — start thinking state, fire API
        dlog("✚ BereanIslandButton: cache MISS for \(postId) — fetching")
        vm.trigger(query: bereanQuery, postId: postId, postContent: post.content)
    }
}
