// AccountabilityLayer.swift
// AMENAPP
//
// Accountability Layer: Private but Real
//
// Features:
//   - Keep things private OR share with trusted people
//   - "Send this to my mentor" functionality
//   - "Check in with me in 3 days" scheduling
//   - Accountability streaks (not social pressure)
//   - AI suggests accountability when needed
//
// Entry points:
//   AccountabilityLayer.shared.addPartner(_ userId:) async
//   AccountabilityLayer.shared.shareWithPartner(_ content:partnerId:) async
//   AccountabilityLayer.shared.scheduleCheckIn(topic:days:) async
//   AccountabilityLayer.shared.getStreakInfo() -> AccountabilityStreak

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - Models

/// An accountability partner relationship
struct AccountabilityPartner: Identifiable, Codable {
    let id: String
    let userId: String
    let partnerId: String
    let partnerName: String
    let partnerProfileImageURL: String?
    let createdAt: Date
    var isActive: Bool
    var sharedTopics: [String]      // What they're accountable for
    var lastCheckIn: Date?
    var checkInStreak: Int
}

/// A shared accountability item
struct AccountabilityItem: Identifiable, Codable {
    let id: String
    let userId: String
    let partnerId: String?          // nil = private
    let content: String
    let category: AccountabilityCategory
    let createdAt: Date
    var checkIns: [AccountabilityCheckIn]
    var status: AccountabilityStatus
    var isPrivate: Bool

    var isActive: Bool { status == .active }
}

enum AccountabilityCategory: String, Codable {
    case spiritualDiscipline = "spiritual_discipline"
    case habit = "habit"
    case prayer = "prayer"
    case study = "study"
    case service = "service"
    case recovery = "recovery"
    case relationship = "relationship"
    case general = "general"

    var displayName: String {
        switch self {
        case .spiritualDiscipline: return "Spiritual Discipline"
        case .habit: return "Habit"
        case .prayer: return "Prayer"
        case .study: return "Study"
        case .service: return "Service"
        case .recovery: return "Recovery"
        case .relationship: return "Relationship"
        case .general: return "General"
        }
    }
}

enum AccountabilityStatus: String, Codable {
    case active = "active"
    case paused = "paused"
    case completed = "completed"
    case abandoned = "abandoned"
}

/// A check-in response
struct AccountabilityCheckIn: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let response: String            // How they're doing
    let honesty: HonestyLevel      // Self-reported
    let mood: String?
}

enum HonestyLevel: String, Codable {
    case struggling = "struggling"
    case maintaining = "maintaining"
    case growing = "growing"
    case thriving = "thriving"
}

/// Streak information
struct AccountabilityStreak {
    let currentStreak: Int
    let longestStreak: Int
    let totalCheckIns: Int
    let lastCheckInDate: Date?
    let nextCheckInDue: Date?
}

// MARK: - AccountabilityLayer

@MainActor
final class AccountabilityLayer: ObservableObject {

    static let shared = AccountabilityLayer()

    @Published var partners: [AccountabilityPartner] = []
    @Published var activeItems: [AccountabilityItem] = []
    @Published var pendingCheckIns: [AccountabilityItem] = []
    @Published var streak: AccountabilityStreak
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {
        streak = AccountabilityStreak(
            currentStreak: 0,
            longestStreak: 0,
            totalCheckIns: 0,
            lastCheckInDate: nil,
            nextCheckInDue: nil
        )
        startListening()
    }

    // MARK: - Partner Management

    /// Add an accountability partner
    func addPartner(partnerId: String, partnerName: String, profileURL: String? = nil) async -> AccountabilityPartner? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        // Check if already partners
        if partners.contains(where: { $0.partnerId == partnerId }) { return nil }

        let partner = AccountabilityPartner(
            id: UUID().uuidString,
            userId: uid,
            partnerId: partnerId,
            partnerName: partnerName,
            partnerProfileImageURL: profileURL,
            createdAt: Date(),
            isActive: true,
            sharedTopics: [],
            lastCheckIn: nil,
            checkInStreak: 0
        )

        do {
            try db.collection("users").document(uid)
                .collection("accountabilityPartners").document(partner.id)
                .setData(from: partner)

            partners.append(partner)
            return partner
        } catch {
            return nil
        }
    }

    // MARK: - Accountability Items

    /// Create a new accountability item
    func createItem(
        content: String,
        category: AccountabilityCategory = .general,
        partnerId: String? = nil,
        isPrivate: Bool = true
    ) async -> AccountabilityItem? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        let item = AccountabilityItem(
            id: UUID().uuidString,
            userId: uid,
            partnerId: partnerId,
            content: content,
            category: category,
            createdAt: Date(),
            checkIns: [],
            status: .active,
            isPrivate: isPrivate
        )

        do {
            try db.collection("users").document(uid)
                .collection("accountabilityItems").document(item.id)
                .setData(from: item)

            activeItems.insert(item, at: 0)
            return item
        } catch {
            return nil
        }
    }

    /// Share content with an accountability partner
    func shareWithPartner(content: String, partnerId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let shareData: [String: Any] = [
            "fromUserId": uid,
            "toUserId": partnerId,
            "content": content,
            "timestamp": Timestamp(date: Date()),
            "type": "accountability_share"
        ]

        // Save to partner's notifications
        try? await db.collection("users").document(partnerId)
            .collection("accountabilityShares")
            .addDocument(data: shareData)
    }

    // MARK: - Check-Ins

    /// Record a check-in for an accountability item
    func checkIn(itemId: String, response: String, honesty: HonestyLevel, mood: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let checkIn = AccountabilityCheckIn(
            id: UUID().uuidString,
            timestamp: Date(),
            response: response,
            honesty: honesty,
            mood: mood
        )

        let ref = db.collection("users").document(uid)
            .collection("accountabilityItems").document(itemId)

        do {
            try await ref.updateData([
                "checkIns": FieldValue.arrayUnion([
                    try Firestore.Encoder().encode(checkIn)
                ])
            ])

            if let idx = activeItems.firstIndex(where: { $0.id == itemId }) {
                activeItems[idx].checkIns.append(checkIn)
            }

            updateStreak()
        } catch {
            dlog("❌ [Accountability] Check-in failed: \(error)")
        }
    }

    /// Schedule a future check-in notification
    func scheduleCheckIn(topic: String, daysFromNow: Int, itemId: String? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = "Accountability Check-In"
        content.body = "How are you doing with: \(topic)?"
        content.sound = .default
        content.userInfo = [
            "type": "accountability_check_in",
            "topic": topic,
            "itemId": itemId ?? ""
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(daysFromNow * 86400),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "accountability_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Streak Management

    func getStreakInfo() -> AccountabilityStreak {
        return streak
    }

    private func updateStreak() {
        let allCheckIns = activeItems.flatMap { $0.checkIns }
        let sorted = allCheckIns.sorted { $0.timestamp > $1.timestamp }

        var current = 0
        var checkDate = Date()
        let calendar = Calendar.current

        for _ in 0..<365 {
            let hasCheckIn = sorted.contains { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }
            if hasCheckIn {
                current += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }

        let longest = max(current, UserDefaults.standard.integer(forKey: "accountability_longest_streak"))
        if current > longest {
            UserDefaults.standard.set(current, forKey: "accountability_longest_streak")
        }

        streak = AccountabilityStreak(
            currentStreak: current,
            longestStreak: max(current, longest),
            totalCheckIns: allCheckIns.count,
            lastCheckInDate: sorted.first?.timestamp,
            nextCheckInDue: calendar.date(byAdding: .day, value: 1, to: Date())
        )
    }

    // MARK: - Listening

    private func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        listener = db.collection("users").document(uid)
            .collection("accountabilityItems")
            .whereField("status", isEqualTo: AccountabilityStatus.active.rawValue)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.activeItems = docs.compactMap { try? $0.data(as: AccountabilityItem.self) }
                    self.updateStreak()
                }
            }
    }
}
