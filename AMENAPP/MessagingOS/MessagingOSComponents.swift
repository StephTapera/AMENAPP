// MessagingOSComponents.swift
// AMENAPP — MessagingOS
// Supporting types for the Messaging OS layer.

import Foundation

// MARK: - Attachment Type

enum MessageAttachmentType: String, CaseIterable, Identifiable {
    case camera, photoLibrary, files, voiceNote
    case prayerRequest, churchNote, event, poll
    case resource, location, scripture, gif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .camera:        return "Camera"
        case .photoLibrary:  return "Photos"
        case .files:         return "Files"
        case .voiceNote:     return "Voice Note"
        case .prayerRequest: return "Prayer Request"
        case .churchNote:    return "Church Note"
        case .event:         return "Event"
        case .poll:          return "Poll"
        case .resource:      return "Resource"
        case .location:      return "Location"
        case .scripture:     return "Scripture"
        case .gif:           return "GIF"
        }
    }

    var icon: String {
        switch self {
        case .camera:        return "camera.fill"
        case .photoLibrary:  return "photo.on.rectangle"
        case .files:         return "folder.fill"
        case .voiceNote:     return "waveform"
        case .prayerRequest: return "hands.sparkles.fill"
        case .churchNote:    return "note.text"
        case .event:         return "calendar.badge.plus"
        case .poll:          return "chart.bar.fill"
        case .resource:      return "books.vertical.fill"
        case .location:      return "location.fill"
        case .scripture:     return "book.fill"
        case .gif:           return "play.rectangle.fill"
        }
    }

    var sourceType: ContentSourceType {
        switch self {
        case .prayerRequest: return .prayerRequest
        case .churchNote:    return .churchNote
        case .event:         return .event
        case .resource:      return .resource
        case .scripture:     return .churchNote
        default:             return .message
        }
    }
}

// MARK: - Long Press Action

enum MessageLongPressAction: String, CaseIterable, Identifiable {
    case reply, pray, saveToNotes, shareToSpace, sendToMentor
    case followUp, scheduleReminder, translate, askBerean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reply:            return "Reply"
        case .pray:             return "Pray for This"
        case .saveToNotes:      return "Save to Notes"
        case .shareToSpace:     return "Share to Space"
        case .sendToMentor:     return "Send to Mentor"
        case .followUp:         return "Follow Up"
        case .scheduleReminder: return "Schedule Reminder"
        case .translate:        return "Translate"
        case .askBerean:        return "Ask Berean"
        }
    }

    var icon: String {
        switch self {
        case .reply:            return "arrowshape.turn.up.left.fill"
        case .pray:             return "hands.sparkles.fill"
        case .saveToNotes:      return "note.text.badge.plus"
        case .shareToSpace:     return "rectangle.3.group.fill"
        case .sendToMentor:     return "person.badge.key.fill"
        case .followUp:         return "arrow.triangle.2.circlepath"
        case .scheduleReminder: return "bell.badge.fill"
        case .translate:        return "character.bubble.fill"
        case .askBerean:        return "sparkles"
        }
    }

    // Actions that produce a ContentCard that may cross audience boundaries
    var producesContentCard: Bool {
        switch self {
        case .saveToNotes, .shareToSpace, .sendToMentor: return true
        default: return false
        }
    }

    var targetAction: ContentAction? {
        switch self {
        case .saveToNotes:  return .saveToChurchNotes
        case .shareToSpace: return .discussInSpace
        case .sendToMentor: return .sendToMentor
        default:            return nil
        }
    }
}

// MARK: - ContentCard from message helper

extension ContentCard {
    static func fromMessage(
        messageId: String,
        body: String,
        senderId: String,
        isDM: Bool,
        isAnonymous: Bool
    ) -> ContentCard {
        ContentCard(
            id: messageId,
            title: String(body.prefix(60)),
            body: body,
            sourceType: .message,
            sourceSurface: isDM ? .directMessage : .space,
            sourceId: messageId,
            originalAudience: isDM ? .private : .spaceMembers,
            creatorId: senderId,
            creatorDisplayName: isAnonymous ? nil : "Member",
            sensitivityScore: isDM ? 0.8 : 0.3,
            hasPrayerContent: body.localizedCaseInsensitiveContains("pray"),
            hasChildContent: false,
            hasLocationData: false,
            hasMinors: false,
            isAnonymous: isAnonymous,
            isPaidContent: false,
            isDM: isDM,
            isChurchInternal: false,
            createdAt: Date(),
            expiresAt: nil,
            moderationState: .safe,
            discussionStatus: .none,
            attributionRules: ContentAttributionRules(
                requiresAttribution: !isAnonymous,
                allowsAnonymous: true,
                allowsQuoteOnly: false,
                expiresAfterDays: 30
            )
        )
    }
}
