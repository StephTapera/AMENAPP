// AmenMessageReadReceiptChip.swift
// AMENAPP
//
// Phase 12: Read receipt chip below outgoing messages.
// Real data only — no fake presence, no fake timestamps.

import SwiftUI

struct AmenMessageReadReceiptChip: View {
    let isDelivered: Bool
    let isRead: Bool
    let readByCount: Int        // > 1 in group chats
    let readerName: String?     // For 1:1 chats, show their name if available

    var body: some View {
        HStack(spacing: 4) {
            statusIcon
            statusLabel
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(isRead ? .blue : .secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRead {
            Image(systemName: "checkmark.circle.fill")
        } else if isDelivered {
            Image(systemName: "checkmark.circle")
        } else {
            Image(systemName: "checkmark")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if readByCount > 1 {
            Text("Seen by \(readByCount)")
        } else if isRead {
            if let name = readerName {
                Text("Seen by \(name)")
            } else {
                Text("Seen")
            }
        } else if isDelivered {
            Text("Delivered")
        }
        // No text for sent-only — icon alone is sufficient
    }

    private var accessibilityDescription: String {
        if readByCount > 1 {
            return "Seen by \(readByCount) people"
        } else if isRead {
            if let name = readerName {
                return "Seen by \(name)"
            }
            return "Message seen"
        } else if isDelivered {
            return "Message delivered"
        }
        return "Message sent"
    }
}
