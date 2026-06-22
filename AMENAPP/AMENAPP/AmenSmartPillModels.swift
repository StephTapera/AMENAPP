// AmenSmartPillModels.swift
// AMENAPP
//
// Data models for the Messaging Intelligence smart pill system (Phase 4A).

import Foundation

enum AmenSmartPillType: String, CaseIterable {
    case translate
    case catchMeUp
    case saveToSelah
    case addToChurchNotes
    case saveToNotes
    case remindMe
    case extractActions
    case voiceTranscript
    case mediaActions
    case summarize
    case replyKindly
    case toneCheck
    case markAsPrayerRequest
    case makePrivate
    case safetyReview
    case threadInfo
    case shareMessage
    case addToStudy

    var label: String {
        switch self {
        case .translate:        return "Translate"
        case .catchMeUp:        return "Catch Me Up"
        case .saveToSelah:      return "Save to Selah"
        case .addToChurchNotes: return "Add to Notes"
        case .saveToNotes:      return "Save"
        case .remindMe:         return "Remind Me"
        case .extractActions:   return "Extract Actions"
        case .voiceTranscript:  return "Transcript"
        case .mediaActions:     return "Actions"
        case .summarize:        return "Summarize"
        case .replyKindly:      return "Reply Kindly"
        case .toneCheck:        return "Tone Check"
        case .markAsPrayerRequest: return "Prayer Request"
        case .makePrivate:      return "Make Private"
        case .safetyReview:     return "Review"
        case .threadInfo:       return "Thread Info"
        case .shareMessage:     return "Share"
        case .addToStudy:       return "Add to Study"
        }
    }

    var systemImage: String {
        switch self {
        case .translate:        return "globe"
        case .catchMeUp:        return "arrow.up.doc"
        case .saveToSelah:      return "bookmark"
        case .addToChurchNotes: return "note.text"
        case .saveToNotes:      return "square.and.pencil"
        case .remindMe:         return "bell"
        case .extractActions:   return "checklist"
        case .voiceTranscript:  return "waveform"
        case .mediaActions:     return "photo"
        case .summarize:        return "text.quote"
        case .replyKindly:      return "heart.text.square"
        case .toneCheck:        return "text.bubble"
        case .markAsPrayerRequest: return "hands.sparkles"
        case .makePrivate:      return "lock"
        case .safetyReview:     return "shield"
        case .threadInfo:       return "bubble.left.and.bubble.right"
        case .shareMessage:     return "square.and.arrow.up"
        case .addToStudy:       return "books.vertical"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .translate:        return "Translates this message to your language"
        case .catchMeUp:        return "Summarizes messages you missed"
        case .saveToSelah:      return "Saves this message to your Selah library"
        case .addToChurchNotes: return "Adds this message to your church notes"
        case .saveToNotes:      return "Saves this message to notes"
        case .remindMe:         return "Sets a reminder for this message"
        case .extractActions:   return "Extracts action items from this message"
        case .voiceTranscript:  return "Shows transcript of this voice message"
        case .mediaActions:     return "Shows available actions for this media"
        case .summarize:        return "Summarizes this conversation"
        case .replyKindly:      return "Helps draft a kind reply when reply support is available"
        case .toneCheck:        return "Checks message tone when tone review is available"
        case .markAsPrayerRequest: return "Marks this message as a prayer request when permissions allow"
        case .makePrivate:      return "Keeps this message private when privacy controls are available"
        case .safetyReview:     return "Shows safety information"
        case .threadInfo:       return "Shows thread information"
        case .shareMessage:     return "Shares this message"
        case .addToStudy:       return "Adds to a Bible study"
        }
    }
}

enum AmenSmartPillState: Equatable {
    case idle
    case loading
    case active
    case succeeded(String)
    case failed(String)
    case unavailable(String)
    case disabled
    case permissionDenied(String)
    case moderationBlocked(String)
    case featureFlagOff
    case error(String)

    var canExecute: Bool {
        switch self {
        case .idle, .active, .succeeded:
            return true
        case .loading, .failed, .unavailable, .disabled, .permissionDenied, .moderationBlocked, .featureFlagOff, .error:
            return false
        }
    }

    var accessibilityStatus: String? {
        switch self {
        case .loading:
            return "Loading"
        case .failed(let message), .unavailable(let message), .permissionDenied(let message), .moderationBlocked(let message), .error(let message):
            return message
        case .disabled:
            return "Disabled"
        case .featureFlagOff:
            return "Unavailable"
        case .idle, .active, .succeeded:
            return nil
        }
    }
}

struct AmenSmartPillDescriptor: Identifiable, Equatable {
    let id: UUID
    let type: AmenSmartPillType
    var state: AmenSmartPillState

    init(type: AmenSmartPillType, state: AmenSmartPillState = .idle) {
        self.id = UUID()
        self.type = type
        self.state = state
    }
}
