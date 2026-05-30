//
//  DevotionalRhythmService.swift
//  AMENAPP
//
//  Tracks devotional cadence: streaks, frequency, and tone/topic patterns.
//  Records a SpiritualRhythmEntry to Firestore each time a devotional is
//  completed, then computes a SpiritualRhythmSnapshot for the UI.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class DevotionalRhythmService: ObservableObject {
    static let shared = DevotionalRhythmService()

    @Published var snapshot: SpiritualRhythmSnapshot = .empty
    @Published var isLoading = false

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private var userId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private init() { // DevotionalRhythmService – devotional cadence only (distinct from CalmControl's SpiritualRhythmService)
        startListening()
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Real-time Listener

    private func startListening() {
        guard !userId.isEmpty else { return }
        listener?.remove()
        listener = db
            .collection("users/\(userId)/devotionalRhythm")
            .order(by: "completedAt", descending: true)
            .limit(to: 90)   // 90-day window
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let entries = docs.compactMap {
                    try? Firestore.Decoder().decode(SpiritualRhythmEntry.self, from: $0.data())
                }
                self?.snapshot = Self.buildSnapshot(from: entries)
            }
    }

    // MARK: - Record Entry

    /// Call this after a devotional is successfully generated and viewed.
    func recordCompletion(devotional: DevotionalResponse) async {
        guard !userId.isEmpty else { return }
        let entry = SpiritualRhythmEntry(
            userId: userId,
            devotionalId: devotional.id,
            topic: devotional.topicTags.first ?? "general",
            tone: devotional.tone
        )
        do {
            let data = try Firestore.Encoder().encode(entry)
            try await db
                .collection("users/\(userId)/devotionalRhythm")
                .addDocument(data: data)
        } catch {
            print("[ERROR] DevotionalRhythmService.recordCompletion: failed to persist rhythm entry — \(error)")
        }
    }

    // MARK: - Snapshot Computation

    static func buildSnapshot(from entries: [SpiritualRhythmEntry]) -> SpiritualRhythmSnapshot {
        guard !entries.isEmpty else { return .empty }

        let total = entries.count
        let lastCompleted = entries.first?.completedAt

        // Streak: consecutive days up to today
        let currentStreak = computeStreak(entries: entries)
        let longestStreak = computeLongestStreak(entries: entries)

        // Most used tone
        let toneFreq = Dictionary(
            entries.map { ($0.tone, 1) },
            uniquingKeysWith: +
        )
        let mostUsedToneRaw = toneFreq.max(by: { $0.value < $1.value })?.key
        let mostUsedTone = mostUsedToneRaw.flatMap { DevotionalTone(rawValue: $0) }

        // Top topics
        let topicFreq = Dictionary(
            entries.map { ($0.topic, 1) },
            uniquingKeysWith: +
        )
        let topTopics = topicFreq
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)

        return SpiritualRhythmSnapshot(
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            totalDevotionalsCompleted: total,
            mostUsedTone: mostUsedTone,
            topTopics: Array(topTopics),
            lastCompletedAt: lastCompleted
        )
    }

    private static func computeStreak(entries: [SpiritualRhythmEntry]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Unique days the user completed a devotional, sorted descending
        let days = Set(entries.map {
            calendar.startOfDay(for: $0.completedAt)
        }).sorted(by: >)

        guard let first = days.first else { return 0 }

        // If last completion was not today or yesterday, streak is broken
        let daysSinceFirst = calendar.dateComponents([.day], from: first, to: today).day ?? 0
        if daysSinceFirst > 1 { return 0 }

        var streak = 1
        for i in 1..<days.count {
            let diff = calendar.dateComponents([.day], from: days[i], to: days[i - 1]).day ?? 0
            if diff == 1 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private static func computeLongestStreak(entries: [SpiritualRhythmEntry]) -> Int {
        let calendar = Calendar.current
        let days = Set(entries.map {
            calendar.startOfDay(for: $0.completedAt)
        }).sorted()

        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for i in 1..<days.count {
            let diff = calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}

// MARK: - Empty Snapshot

extension SpiritualRhythmSnapshot {
    static let empty = SpiritualRhythmSnapshot(
        currentStreakDays: 0,
        longestStreakDays: 0,
        totalDevotionalsCompleted: 0,
        mostUsedTone: nil,
        topTopics: [],
        lastCompletedAt: nil
    )
}
