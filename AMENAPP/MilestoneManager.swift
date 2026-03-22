//
//  MilestoneManager.swift
//  AMENAPP
//
//  Manages which milestone to show and deduplication via Firestore
//  Shows one milestone at a time, queues rest for next session
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - UserStats (wire to your existing model)
struct UserStats {
    var totalPosts: Int
    var currentStreak: Int
    var testimonyReach: Int
    var prayerResponses: Int
    var followerCount: Int
}

// MARK: - Milestone Manager
@MainActor
class MilestoneManager: ObservableObject {
    static let shared = MilestoneManager()
    
    @Published var activeMilestone: AMENMilestone?
    @Published var showSheet = false

    private let db = Firestore.firestore()
    private var shownMilestoneIds: Set<String> = []

    private init() {}
    
    func checkMilestones(for userId: String, stats: UserStats) async {
        var candidates: [AMENMilestone] = []

        // First post milestone
        if stats.totalPosts == 1 {
            candidates.append(firstPostMilestone())
        }
        
        // Streak milestones
        if stats.currentStreak == 7 || stats.currentStreak == 14 || stats.currentStreak == 30 {
            candidates.append(streakMilestone(days: stats.currentStreak))
        }
        
        // Testimony reach milestones
        if [50, 100, 500, 1000].contains(stats.testimonyReach) {
            candidates.append(testimonyMilestone(count: stats.testimonyReach))
        }
        
        // Prayer response milestones
        if [5, 10, 25, 50, 100].contains(stats.prayerResponses) {
            candidates.append(prayerMilestone(count: stats.prayerResponses))
        }
        
        // Community growth milestones
        if [100, 500, 1000, 5000].contains(stats.followerCount) {
            candidates.append(communityMilestone(count: stats.followerCount))
        }

        // Show first unseen milestone
        for milestone in candidates {
            let alreadySeen = await hasSeenMilestone(userId: userId, milestoneId: milestone.id)
            if !alreadySeen && !shownMilestoneIds.contains(milestone.id) {
                shownMilestoneIds.insert(milestone.id)
                activeMilestone = milestone
                withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) {
                    showSheet = true
                }
                await markMilestoneSeen(userId: userId, milestoneId: milestone.id)

                // #5 Fix: For prayer milestones also write a Firestore notification
                // so the milestone appears in the notifications feed + drives badge.
                if milestone.id.hasPrefix("prayer_") {
                    await writePrayerMilestoneNotification(userId: userId, milestone: milestone)
                }

                break
            }
        }
    }

    func dismiss() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
            showSheet = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.activeMilestone = nil
        }
    }

    // MARK: - Firestore deduplication
    private func hasSeenMilestone(userId: String, milestoneId: String) async -> Bool {
        do {
            let doc = try await db
                .collection("users").document(userId)
                .collection("seenMilestones").document(milestoneId)
                .getDocument()
            return doc.exists
        } catch {
            dlog("⚠️ Error checking milestone seen status: \(error)")
            return false
        }
    }

    // #5: Write prayer_milestone notification to Firestore so it surfaces in
    // the Notifications feed and increments the badge counter.
    private func writePrayerMilestoneNotification(userId: String, milestone: AMENMilestone) async {
        do {
            let countString = milestone.id.replacingOccurrences(of: "prayer_", with: "")
            let count = Int(countString) ?? 0
            try await db
                .collection("users").document(userId)
                .collection("notifications")
                .addDocument(data: [
                    "type":      "prayer_milestone",
                    "milestone": count,
                    "badgeLabel": milestone.badgeLabel,
                    "title":     milestone.title,
                    "read":      false,
                    "createdAt": FieldValue.serverTimestamp(),
                ])
            dlog("✅ Prayer milestone notification written: \(milestone.id)")
        } catch {
            dlog("⚠️ Failed to write prayer milestone notification: \(error)")
        }
    }

    private func markMilestoneSeen(userId: String, milestoneId: String) async {
        do {
            try await db
                .collection("users").document(userId)
                .collection("seenMilestones").document(milestoneId)
                .setData(["seenAt": FieldValue.serverTimestamp()])
            dlog("✅ Milestone marked as seen: \(milestoneId)")
        } catch {
            dlog("❌ Error marking milestone seen: \(error)")
        }
    }

    // MARK: - Milestone Definitions

    func firstPostMilestone() -> AMENMilestone {
        AMENMilestone(
            id: "first_post",
            badgeIcon: "leaf.fill",
            badgeLabel: "First Post",
            badgeColor: .orange,
            title: "Your first post is live",
            body: "You just put your voice into the community. Posts like yours are what make AMEN worth opening.",
            primaryLabel: "See my post",
            secondaryLabel: "Dismiss",
            primaryAction: {
                dlog("🎉 First post milestone - navigate to post")
                // TODO: Navigate to user's first post
            },
            secondaryAction: {
                dlog("👋 First post milestone dismissed")
            }
        )
    }

    func streakMilestone(days: Int) -> AMENMilestone {
        AMENMilestone(
            id: "streak_\(days)",
            badgeIcon: "flame.fill",
            badgeLabel: "\(days) day streak",
            badgeColor: .orange,
            title: "\(days) days of showing up",
            body: "You've posted every day for \(days) days. Consistency is a spiritual discipline — don't break the chain.",
            primaryLabel: "Keep it going",
            secondaryLabel: "Dismiss",
            primaryAction: {
                dlog("🔥 Streak milestone \(days) - keep going")
            },
            secondaryAction: {
                dlog("👋 Streak milestone dismissed")
            }
        )
    }

    func testimonyMilestone(count: Int) -> AMENMilestone {
        let formattedCount = count >= 1000 ? "\(count / 1000)K" : "\(count)"
        return AMENMilestone(
            id: "testimony_\(count)",
            badgeIcon: "heart.fill",
            badgeLabel: "\(formattedCount) hearts",
            badgeColor: .purple,
            title: "Your testimony is reaching people",
            body: "\(formattedCount) people engaged with your story. Someone out there needed exactly what you shared.",
            primaryLabel: "See who responded",
            secondaryLabel: "Dismiss",
            primaryAction: {
                dlog("💜 Testimony milestone \(count) - view responses")
                // TODO: Navigate to testimony engagements
            },
            secondaryAction: {
                dlog("👋 Testimony milestone dismissed")
            }
        )
    }

    func prayerMilestone(count: Int) -> AMENMilestone {
        AMENMilestone(
            id: "prayer_\(count)",
            badgeIcon: "hands.sparkles.fill",
            badgeLabel: "\(count) praying",
            badgeColor: .green,
            title: "\(count) people are praying for you",
            body: "Your prayer request is being carried by the community right now. You are not alone in this.",
            primaryLabel: "See their prayers",
            secondaryLabel: "Dismiss",
            primaryAction: {
                dlog("🙏 Prayer milestone \(count) - view prayers")
                // TODO: Navigate to prayer responses
            },
            secondaryAction: {
                dlog("👋 Prayer milestone dismissed")
            }
        )
    }

    func communityMilestone(count: Int) -> AMENMilestone {
        let label = count >= 1000 ? "\(count / 1000)K followers" : "\(count) followers"
        let shortLabel = label.components(separatedBy: " ").first ?? "\(count)"
        return AMENMilestone(
            id: "followers_\(count)",
            badgeIcon: "person.2.fill",
            badgeLabel: label,
            badgeColor: .blue,
            title: "\(shortLabel) people follow your journey",
            body: "Your community is growing. A platform is forming around your voice — use it with intention and love.",
            primaryLabel: "View my community",
            secondaryLabel: "Dismiss",
            primaryAction: {
                dlog("👥 Community milestone \(count) - view followers")
                // TODO: Navigate to followers list
            },
            secondaryAction: {
                dlog("👋 Community milestone dismissed")
            }
        )
    }
}
