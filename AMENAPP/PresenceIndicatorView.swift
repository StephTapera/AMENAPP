//
//  PresenceIndicatorView.swift
//  AMENAPP
//
//  Compact presence indicator: green dot for "Active now", relative time for recent activity.
//  Reads from RealtimeDatabaseService.onlineUsers and the user's lastSeen from RTDB.
//
//  Privacy rules (Instagram pattern):
//  - If the viewer has disabled their own activity status, they cannot see others' status.
//  - If the target user has disabled their activity status, their presence is not shown.
//  - Both checks must pass for presence to render.
//

import SwiftUI
import FirebaseDatabase
import FirebaseFirestore

struct PresenceIndicatorView: View {
    let userId: String

    /// Display mode: .dot shows just the green dot, .text shows "Active now" / "Active 2h ago"
    enum DisplayMode {
        case dot
        case text
        case dotAndText
    }

    var mode: DisplayMode = .dotAndText

    @ObservedObject private var realtimeDB = RealtimeDatabaseService.shared
    @State private var lastSeenDate: Date?
    @State private var hasLoaded = false
    /// Whether the target user allows showing activity status.
    @State private var targetAllowsPresence = true

    /// Whether the current viewer has their own activity status enabled.
    /// Instagram rule: if you hide yours, you can't see others'.
    private var viewerAllowsPresence: Bool {
        MessageSettingsService.shared.settings.showActivityStatus
    }

    private var isOnline: Bool {
        realtimeDB.onlineUsers.contains(userId)
    }

    /// Master gate: both viewer and target must allow presence.
    private var shouldShowPresence: Bool {
        viewerAllowsPresence && targetAllowsPresence
    }

    var body: some View {
        Group {
            if shouldShowPresence {
                if isOnline {
                    onlineView
                } else if let lastSeen = lastSeenDate {
                    recentlyActiveView(lastSeen)
                }
            }
            // If privacy blocks or no data, render nothing
        }
        .task(id: userId) {
            guard !hasLoaded else { return }
            await loadPresenceData()
            hasLoaded = true
        }
    }

    // MARK: - Online View

    @ViewBuilder
    private var onlineView: some View {
        switch mode {
        case .dot:
            greenDot
        case .text:
            Text("Active now")
                .font(.system(size: 11))
                .foregroundColor(Color.green)
        case .dotAndText:
            HStack(spacing: 4) {
                greenDot
                Text("Active now")
                    .font(.system(size: 11))
                    .foregroundColor(.black.opacity(0.5))
            }
        }
    }

    // MARK: - Recently Active View

    @ViewBuilder
    private func recentlyActiveView(_ lastSeen: Date) -> some View {
        let interval = Date().timeIntervalSince(lastSeen)
        // Only show if within 24 hours
        if interval < 86400 {
            switch mode {
            case .dot:
                // Gray dot for recently active
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            case .text:
                Text("Active \(relativeTimeString(interval))")
                    .font(.system(size: 11))
                    .foregroundColor(.black.opacity(0.4))
            case .dotAndText:
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text("Active \(relativeTimeString(interval))")
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Components

    private var greenDot: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
            )
    }

    // MARK: - Helpers

    /// Load both the target user's privacy preference and their last-seen timestamp.
    private func loadPresenceData() async {
        // 1. Check target user's showActivityStatus from Firestore
        do {
            let doc = try await Firestore.firestore()
                .collection(FirebaseManager.CollectionPath.users)
                .document(userId)
                .getDocument()
            if let data = doc.data() {
                targetAllowsPresence = data["showActivityStatus"] as? Bool ?? true
            }
        } catch {
            dlog("PresenceIndicatorView: failed to fetch user privacy for \(userId): \(error)")
        }

        guard shouldShowPresence else { return }

        // 2. Fetch lastSeen from RTDB
        let ref = Database.database().reference().child("presence").child(userId).child("lastSeen")
        do {
            let snapshot = try await ref.getData()
            if let timestamp = snapshot.value as? Double {
                lastSeenDate = Date(timeIntervalSince1970: timestamp / 1000.0)
            }
        } catch {
            dlog("PresenceIndicatorView: failed to fetch lastSeen for \(userId): \(error)")
        }
    }

    private func relativeTimeString(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return ""
    }
}
