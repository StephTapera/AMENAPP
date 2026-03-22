//
//  Feature02_CrisisTone.swift
//  AMENAPP
//
//  Crisis Tone Detection — debounced on-device keyword analysis while the user
//  types in the message composer. Never logs or stores the crisis level.
//

import SwiftUI
import Combine

// MARK: - Model

enum CrisisLevel: Int, Comparable {
    case none     = 0
    case mild     = 1
    case moderate = 2
    case high     = 3

    static func < (lhs: CrisisLevel, rhs: CrisisLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Manager

final class CrisisToneDetector: ObservableObject {
    static let shared = CrisisToneDetector()

    @Published var showCrisisBanner: Bool = false

    // Tracks chars typed after banner shown; hides after 10 more chars
    private var charsTypedSinceBanner = 0
    private var bannerShownAtLength   = 0
    private var debounceTask: Task<Void, Never>?

    // Weighted keyword clusters — co-occurrence increases score
    private let highCluster: Set<String> = [
        "end it", "can't go on", "no point", "don't want to be here", "want to die",
        "better off without me", "end my life", "give up on life"
    ]
    private let moderateCluster: Set<String> = [
        "hopeless", "tired of everything", "can't anymore", "nobody cares",
        "what's the point", "don't see a way", "too much pain", "falling apart"
    ]
    private let mildCluster: Set<String> = [
        "grief", "despair", "exhausted", "overwhelmed", "darkness",
        "can't handle", "breaking down", "losing it"
    ]

    private init() {}

    // MARK: - Analyze (debounced 1.5s)

    func analyze(text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            guard !Task.isCancelled else { return }
            let level = detectLevel(text: text.lowercased())
            await MainActor.run {
                if level >= .moderate {
                    if !self.showCrisisBanner {
                        self.showCrisisBanner     = true
                        self.bannerShownAtLength  = text.count
                        self.charsTypedSinceBanner = 0
                    }
                } else {
                    self.showCrisisBanner = false
                }
            }
        }
    }

    /// Call whenever text length changes after banner is shown.
    /// Dismisses banner if user types 10+ more chars.
    func trackTyping(currentLength: Int) {
        guard showCrisisBanner else { return }
        charsTypedSinceBanner = max(0, currentLength - bannerShownAtLength)
        if charsTypedSinceBanner >= 10 {
            DispatchQueue.main.async { self.showCrisisBanner = false }
        }
    }

    func dismissBanner() {
        showCrisisBanner = false
    }

    // MARK: - Private

    private func detectLevel(text: String) -> CrisisLevel {
        for phrase in highCluster {
            if text.contains(phrase) { return .high }
        }
        var moderateHits = 0
        for phrase in moderateCluster {
            if text.contains(phrase) { moderateHits += 1 }
        }
        if moderateHits >= 1 { return .moderate }

        var mildHits = 0
        for phrase in mildCluster {
            if text.contains(phrase) { mildHits += 1 }
        }
        if mildHits >= 2 { return .moderate }
        if mildHits == 1 { return .mild }

        return .none
    }
}
