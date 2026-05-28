//
//  AMENActivityIntelligenceEngine.swift
//  AMENAPP
//
//  Intelligence layer for the AMEN Activity System.
//  Handles: priority scoring, time bucketing, smart grouping,
//  copy generation, safety classification, and action assignment.
//
//  Product rule: not "what happened?" but "what matters right now?"
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Activity Priority

/// P0 = urgent/crisis, P1 = high-signal, P2 = medium, P3 = low, P4 = digest-only
enum ActivityPriority: Int, Comparable {
    case p0 = 0
    case p1 = 1
    case p2 = 2
    case p3 = 3
    case p4 = 4

    static func < (lhs: ActivityPriority, rhs: ActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Filter Category

enum ActivityFilterCategory: String, CaseIterable, Identifiable {
    case all        = "All"
    case important  = "Important"
    case prayer     = "Prayer"
    case community  = "Community"
    case scripture  = "Scripture"
    case church     = "Church"
    case berean     = "Berean"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all:        return "bell.fill"
        case .important:  return "exclamationmark.circle.fill"
        case .prayer:     return "hands.sparkles.fill"
        case .community:  return "person.2.fill"
        case .scripture:  return "book.fill"
        case .church:     return "building.columns.fill"
        case .berean:     return "sparkles"
        }
    }
}

// MARK: - Time Bucket

enum ActivityTimeBucket: String {
    case needsAttention = "Needs Your Attention"
    case today          = "Today"
    case yesterday      = "Yesterday"
    case lastSevenDays  = "Last 7 Days"
    case earlier        = "Earlier"
}

// MARK: - Safety Classification

enum NotificationSafetyClass: String {
    case normal
    case encouragement
    case sensitive
    case urgentPrayer
    case pastoralCare
    case crisis
    case argumentative
    case spam
}

// MARK: - Content Preview Type

enum ActivityContentPreview {
    case postImage(URL?)
    case prayerCard
    case verseCard(String)
    case churchLogo(URL?)
    case bereanInsight
    case churchNotes
    case none
}

// MARK: - Smart Action

struct ActivitySmartAction: Identifiable {
    let id = UUID()
    let label: String
    let systemIcon: String
    let style: ActionStyle

    enum ActionStyle { case primary, secondary }
}

// MARK: - Grouped Notification (Display Model)

struct GroupedNotification: Identifiable {
    let id: String
    let category: ActivityFilterCategory
    let priority: ActivityPriority
    let timeBucket: ActivityTimeBucket
    let safety: NotificationSafetyClass

    /// Plain text title — actor names for bolding derived from primaryActor/secondaryActors
    let title: String
    let subtitle: String?
    let contextLabel: String?

    let primaryActor: NotificationActor?
    let secondaryActors: [NotificationActor]
    let totalActorCount: Int

    let timestamp: Date
    let route: NotificationRoute
    let sourceNotificationIds: [String]

    let contentPreview: ActivityContentPreview
    let actions: [ActivitySmartAction]

    var isRead: Bool

    /// AttributedString version of title with primary actor names in semibold
    var attributedTitle: AttributedString {
        var attr = AttributedString(title)
        let boldNames = ([primaryActor] + secondaryActors).compactMap { $0?.name }
        for name in boldNames {
            var searchStart = attr.startIndex
            while searchStart < attr.endIndex,
                  let range = attr[searchStart...].range(of: name) {
                attr[range].font = .system(size: 15, weight: .semibold)
                searchStart = range.upperBound
            }
        }
        return attr
    }
}

// MARK: - Intelligence Engine

enum AMENActivityIntelligenceEngine {

    // MARK: - Main Entry Point

    static func process(_ notifications: [AppNotification]) -> [GroupedNotification] {
        let groups = groupByTarget(notifications)
        let classified = groups.map { classify($0) }
        return classified.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.timestamp > $1.timestamp
        }
    }

    // MARK: - Time Bucket

    static func bucket(for date: Date, priority: ActivityPriority) -> ActivityTimeBucket {
        if priority <= .p1 { return .needsAttention }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        if let cutoff = cal.date(byAdding: .day, value: -7, to: Date()), date > cutoff {
            return .lastSevenDays
        }
        return .earlier
    }

    // MARK: - Group Key

    static func groupKey(for n: AppNotification) -> String {
        if let gid = n.groupId, !gid.isEmpty { return gid }
        switch n.type {
        case .prayerSupported, .prayerAnswered, .prayerReminder:
            if let id = n.prayerId { return "prayer:\(id):engagement" }
        case .comment, .reply, .mention, .amen, .repost:
            if let id = n.postId { return "post:\(id):activity" }
        case .churchNoteShared, .churchNoteReplied:
            if let id = n.noteId { return "note:\(id):activity" }
        case .follow, .followRequestAccepted:
            let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withFullDate]
            return "follows:\(fmt.string(from: n.createdAt.dateValue()))"
        case .actionThreadInvite, .actionThreadUpdate, .actionThreadReminder:
            if let id = n.postId { return "thread:\(id)" }
        default:
            break
        }
        return n.id ?? UUID().uuidString
    }

    // MARK: - Grouping

    private static func groupByTarget(_ notifications: [AppNotification]) -> [[AppNotification]] {
        var buckets: [String: [AppNotification]] = [:]
        for n in notifications {
            buckets[groupKey(for: n), default: []].append(n)
        }
        return Array(buckets.values)
    }

    // MARK: - Classify Group

    private static func classify(_ group: [AppNotification]) -> GroupedNotification {
        let primary = group.max(by: { $0.type.trustRank < $1.type.trustRank }) ?? group[0]
        let priority  = scorePriority(group)
        let category  = mapCategory(primary)
        let safety    = classifySafety(group)
        let actors    = rankActors(group)
        let timestamp = group.compactMap { ($0.updatedAt ?? $0.createdAt).dateValue() }.max()
                        ?? primary.createdAt.dateValue()
        let timeBucket = Self.bucket(for: timestamp, priority: priority)
        let title      = buildTitle(group: group, primary: primary)
        let subtitle   = buildSubtitle(group: group, primary: primary, safety: safety)
        let ctxLabel   = buildContextLabel(group: group)
        let preview    = buildPreview(primary: primary, safety: safety)
        let actions    = buildActions(group: group)

        return GroupedNotification(
            id:                    groupKey(for: primary),
            category:              category,
            priority:              priority,
            timeBucket:            timeBucket,
            safety:                safety,
            title:                 title,
            subtitle:              subtitle,
            contextLabel:          ctxLabel,
            primaryActor:          actors.first,
            secondaryActors:       Array(actors.dropFirst().prefix(2)),
            totalActorCount:       uniqueActorCount(group),
            timestamp:             timestamp,
            route:                 NotificationRouteResolver.resolve(primary),
            sourceNotificationIds: group.compactMap { $0.id },
            contentPreview:        preview,
            actions:               actions,
            isRead:                group.allSatisfy { $0.read }
        )
    }

    // MARK: - Priority Scoring

    private static func scorePriority(_ group: [AppNotification]) -> ActivityPriority {
        let types = Set(group.map { $0.type })
        if types.contains(.actionThreadInvite)                          { return .p1 }
        if types.contains(.reply) || types.contains(.churchNoteReplied) { return .p1 }
        if types.contains(.prayerSupported) || types.contains(.prayerAnswered) { return .p1 }
        if types.contains(.comment) || types.contains(.mention)         { return .p2 }
        if types.contains(.churchNoteShared)                            { return .p2 }
        if types.contains(.amen) || types.contains(.follow) || types.contains(.repost) { return .p3 }
        return .p4
    }

    // MARK: - Category Mapping

    private static func mapCategory(_ n: AppNotification) -> ActivityFilterCategory {
        switch n.type {
        case .prayerSupported, .prayerAnswered, .prayerReminder:              return .prayer
        case .churchNoteShared, .churchNoteReplied:                            return .church
        case .actionThreadInvite, .actionThreadUpdate, .actionThreadReminder: return .community
        default:                                                               return .community
        }
    }

    // MARK: - Safety Classification

    private static func classifySafety(_ group: [AppNotification]) -> NotificationSafetyClass {
        let types = Set(group.map { $0.type })
        if types.contains(.actionThreadInvite)                               { return .pastoralCare }
        if types.contains(.prayerSupported) || types.contains(.prayerAnswered) { return .sensitive }
        return .normal
    }

    // MARK: - Actor Ranking (pastor > church > following > recency)

    private static func rankActors(_ group: [AppNotification]) -> [NotificationActor] {
        var seen   = Set<String>()
        var result = [NotificationActor]()
        let sorted = group.sorted { $0.type.trustRank > $1.type.trustRank }
        for n in sorted {
            if let actors = n.actors {
                for a in actors where !seen.contains(a.id) {
                    seen.insert(a.id); result.append(a)
                }
            }
            if let actorId = n.actorId, !seen.contains(actorId) {
                seen.insert(actorId)
                result.append(NotificationActor(
                    id:              actorId,
                    name:            n.actorName ?? "Someone",
                    username:        n.actorUsername ?? "",
                    profileImageURL: n.actorProfileImageURL
                ))
            }
        }
        return result
    }

    static func uniqueActorCount(_ group: [AppNotification]) -> Int {
        var seen = Set<String>()
        for n in group {
            n.actors?.forEach { seen.insert($0.id) }
            if let id = n.actorId { seen.insert(id) }
        }
        return max(seen.count, 1)
    }

    // MARK: - Smart Copy Generation

    static func buildTitle(group: [AppNotification], primary: AppNotification) -> String {
        let actors = rankActors(group)
        let count  = uniqueActorCount(group)
        let first  = actors.first?.name ?? "Someone"
        let second = actors.dropFirst().first?.name
        let types  = Set(group.map { $0.type })

        // Prayer engagement
        if types.contains(.prayerSupported) || types.contains(.prayerAnswered) {
            switch count {
            case 1:  return "\(first) prayed for your request"
            case 2:  return "\(first) and \(second ?? "someone") prayed for your request"
            default: return "\(first) and \(count - 1) others prayed for your request"
            }
        }

        // Mixed prayer target
        if primary.prayerId != nil {
            return count == 1
                ? "\(first) engaged with your prayer request"
                : "\(first) and \(count - 1) others engaged with your prayer request"
        }

        // Comments / replies / mentions
        if types.contains(.comment) || types.contains(.reply) || types.contains(.mention) {
            switch count {
            case 1:  return "\(first) \(primary.type.actionText)"
            case 2:  return "\(first) and \(second ?? "another") commented on your post"
            default: return "\(first) and \(count - 1) others commented on your post"
            }
        }

        // Amens / reactions (quiet group)
        if types.isSubset(of: [.amen, .repost]) {
            return count == 1
                ? "\(first) \(primary.type.actionText)"
                : "\(first) and \(count - 1) others reacted to your post"
        }

        // Default
        return count == 1
            ? "\(first) \(primary.type.actionText)"
            : "\(first) and \(count - 1) others interacted with your content"
    }

    static func buildSubtitle(
        group: [AppNotification],
        primary: AppNotification,
        safety: NotificationSafetyClass
    ) -> String? {
        // Privacy guard: never expose prayer text
        if safety == .sensitive || safety == .urgentPrayer || safety == .pastoralCare {
            let prayed   = group.filter { $0.type == .prayerSupported }.count
            let amens    = group.filter { $0.type == .amen }.count
            let comments = group.filter { [.comment, .reply].contains($0.type) }.count
            var parts = [String]()
            if prayed   > 0 { parts.append("\(prayed) prayed") }
            if amens    > 0 { parts.append("\(amens) encouraged") }
            if comments > 0 { parts.append("\(comments) commented") }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        }
        // Comment snippet preview
        if let text = primary.commentText, !text.isEmpty {
            let preview = String(text.prefix(80))
            return preview.count < text.count ? "\"\(preview)…\"" : "\"\(preview)\""
        }
        return nil
    }

    static func buildContextLabel(group: [AppNotification]) -> String? {
        let types = Set(group.map { $0.type })
        if types.contains(.prayerSupported) || types.contains(.prayerAnswered) { return "Prayer" }
        if types.contains(.churchNoteShared) || types.contains(.churchNoteReplied) { return "Church Notes" }
        if types.contains(.actionThreadInvite)  { return "Pastoral Care" }
        if types.contains(.reply)               { return "Reply" }
        if types.contains(.mention)             { return "Mention" }
        return nil
    }

    // MARK: - Content Preview

    private static func buildPreview(
        primary: AppNotification,
        safety: NotificationSafetyClass
    ) -> ActivityContentPreview {
        if safety == .sensitive || safety == .urgentPrayer || safety == .pastoralCare {
            return .prayerCard
        }
        switch primary.type {
        case .prayerSupported, .prayerAnswered, .prayerReminder:              return .prayerCard
        case .churchNoteShared, .churchNoteReplied:                            return .churchNotes
        case .actionThreadInvite, .actionThreadUpdate, .actionThreadReminder: return .churchNotes
        default:                                                               return .none
        }
    }

    // MARK: - Smart Actions

    private static func buildActions(group: [AppNotification]) -> [ActivitySmartAction] {
        let types = Set(group.map { $0.type })
        var result = [ActivitySmartAction]()
        if types.contains(.prayerSupported) || types.contains(.prayerAnswered) {
            result.append(.init(label: "Send Update",  systemIcon: "arrow.up.message.fill",        style: .primary))
        }
        if types.contains(.reply) || types.contains(.comment) {
            result.append(.init(label: "Reply",        systemIcon: "arrowshape.turn.up.left.fill",  style: .primary))
        }
        if types.contains(.churchNoteShared) {
            result.append(.init(label: "Open Notes",   systemIcon: "note.text",                     style: .secondary))
        }
        if types.contains(.actionThreadInvite) {
            result.append(.init(label: "View",         systemIcon: "arrow.right.circle.fill",        style: .primary))
        }
        return result
    }
}
