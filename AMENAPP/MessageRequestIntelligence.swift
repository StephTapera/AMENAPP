//
//  MessageRequestIntelligence.swift
//  AMENAPP
//
//  Wraps InteractionPolicyEngine DM eligibility decisions with human-readable explanations.
//  Categorizes incoming message requests by trust level for intelligent inbox segmentation.
//

import Foundation

// MARK: - Trust Level

enum MessageRequestTrustLevel: String, CaseIterable, Comparable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case spam = "SPAM"

    static func < (lhs: MessageRequestTrustLevel, rhs: MessageRequestTrustLevel) -> Bool {
        let order: [MessageRequestTrustLevel] = [.spam, .low, .medium, .high]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }
}

// MARK: - Explanation

struct MessageRequestExplanation {
    let trustLevel: MessageRequestTrustLevel
    let headline: String
    let detail: String
    let reasonCode: DMReasonCode
    let route: DMRoute
}

// MARK: - Service

@MainActor
final class MessageRequestIntelligence {

    static let shared = MessageRequestIntelligence()
    private init() {}

    /// Explain why a message was routed to a particular inbox.
    func explain(result: DMEligibilityResult) -> MessageRequestExplanation {
        let trustLevel = assessTrustLevel(result)
        let headline = headlineFor(result.reasonCode, route: result.route)
        let detail = detailFor(result.reasonCode, route: result.route)

        return MessageRequestExplanation(
            trustLevel: trustLevel,
            headline: headline,
            detail: detail,
            reasonCode: result.reasonCode,
            route: result.route
        )
    }

    /// Categorize a message request's trust level from a DM eligibility result.
    func assessTrustLevel(_ result: DMEligibilityResult) -> MessageRequestTrustLevel {
        switch result.route {
        case .direct:
            return .high
        case .requests:
            switch result.reasonCode {
            case .targetPrivateNotConnected, .targetMessagesFollowersOnly:
                return .medium
            case .rateLimited:
                return .low
            default:
                return .medium
            }
        case .hiddenRequests:
            return result.reasonCode == .senderFlaggedRisky ? .spam : .low
        case .deny:
            return .spam
        }
    }

    // MARK: - Private

    private func headlineFor(_ reason: DMReasonCode, route: DMRoute) -> String {
        switch reason {
        case .mutualOrAllowed:
            return "You're connected"
        case .existingThread:
            return "Existing conversation"
        case .targetPrivateNotConnected:
            return "Private account"
        case .targetMessagesFollowersOnly:
            return "Messages followers only"
        case .targetMessagesNoOne:
            return "Messages turned off"
        case .targetIsTeenRestricted:
            return "Age-restricted messaging"
        case .senderFlaggedRisky:
            return "Filtered for safety"
        case .blocked:
            return "Blocked"
        case .restricted:
            return "Restricted"
        case .rateLimited:
            return "Sending too fast"
        }
    }

    private func detailFor(_ reason: DMReasonCode, route: DMRoute) -> String {
        switch reason {
        case .mutualOrAllowed:
            return "You follow each other or their settings allow your messages."
        case .existingThread:
            return "You have an existing accepted conversation."
        case .targetPrivateNotConnected:
            return "This is a private account. Your message was sent as a request."
        case .targetMessagesFollowersOnly:
            return "This person only accepts messages from people they follow."
        case .targetMessagesNoOne:
            return "This person has turned off messages from everyone."
        case .targetIsTeenRestricted:
            return "Messaging is restricted due to age safety settings."
        case .senderFlaggedRisky:
            return "This message was filtered for safety review."
        case .blocked:
            return "You can't message this person."
        case .restricted:
            return "This account has restricted interactions."
        case .rateLimited:
            return "You're sending messages too quickly. Please wait before trying again."
        }
    }
}
