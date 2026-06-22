//
//  ScheduledMessage.swift
//  AMENAPP
//
//  Model for Schedule Reply feature.
//  Stored under users/{uid}/scheduledMessages/{idempotencyKey}
//  A Cloud Function watches this collection and dispatches when scheduledAt arrives.
//

import Foundation
import FirebaseFirestore

// MARK: - Scheduled Message Status

enum ScheduledMessageStatus: String, Codable, CaseIterable {
    case scheduled  // waiting to send
    case sending    // dispatcher picked it up
    case sent       // delivered to conversation
    case failed     // send failed, needs retry
    case canceled   // user canceled before send
}

// MARK: - Scheduled Message Model

struct ScheduledMessage: Identifiable, Codable {
    @DocumentID var firestoreId: String?

    /// Stable local ID — also used as the Firestore document ID (idempotency key).
    var localId: String = UUID().uuidString

    var id: String { firestoreId ?? localId }

    let conversationId: String
    let senderId: String
    let senderName: String
    let text: String

    /// When the Cloud Function should dispatch this message.
    let scheduledAt: Date
    let createdAt: Date

    var status: ScheduledMessageStatus
    var editCount: Int = 0
    var failureReason: String?

    // Reply context snapshot (frozen at schedule time)
    var replyToMessageId: String?
    var replyToText: String?
    var replyToAuthorName: String?

    // Prevents duplicate dispatches if Cloud Function retries
    let idempotencyKey: String

    // MARK: - Computed helpers

    var isEditable: Bool {
        status == .scheduled && scheduledAt > Date().addingTimeInterval(30) // 30-sec window before lock
    }

    var isCancelable: Bool {
        status == .scheduled
    }

    var scheduledAtFormatted: String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        if cal.isDateInToday(scheduledAt) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if cal.isDateInTomorrow(scheduledAt) {
            formatter.dateFormat = "'Tomorrow at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        }
        return formatter.string(from: scheduledAt)
    }
}
