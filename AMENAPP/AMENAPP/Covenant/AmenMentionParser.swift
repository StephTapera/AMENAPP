import Foundation

// MARK: - Mention Parser
// Parses @mention tokens from message text and builds MentionEntity arrays.
// Supports: @user, @creator, @room, @everyone (admin/mod/creator only),
// @paid (admin/mod/creator only), @tierName (admin/mod/creator only).

struct AmenMentionParser {

    // Regex: matches @word (alphanumeric + underscores + hyphens, 1–32 chars)
    private static let mentionRegex: NSRegularExpression = {
        // Pattern is a compile-time constant and is always valid.
        try! NSRegularExpression(pattern: #"@([a-zA-Z0-9_\-]{1,32})"#, options: [])
    }()

    // MARK: - Parse text → [RawMention]

    struct RawMention {
        let token: String        // the matched @token text
        let handle: String       // token without @
        let range: NSRange
    }

    static func extractRawMentions(from text: String) -> [RawMention] {
        let ns = text as NSString
        let matches = mentionRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let fullRange   = match.range(at: 0)
            let handleRange = match.range(at: 1)
            let token  = ns.substring(with: fullRange)
            let handle = ns.substring(with: handleRange)
            return RawMention(token: token, handle: handle, range: fullRange)
        }
    }

    // MARK: - Resolve to MentionEntities

    /// Resolves raw mentions against a lookup table.
    /// - Parameters:
    ///   - raw: Raw mentions extracted from text
    ///   - userLookup: handle → (userId, displayName)
    ///   - roomLookup: handle → (roomId, displayName)
    ///   - tierNames: set of tier names the author is allowed to broadcast to
    ///   - authorRole: role of the message author (determines @everyone/@paid/@tier rights)
    static func resolve(
        _ raw: [RawMention],
        userLookup: [String: (id: String, display: String)],
        roomLookup: [String: (id: String, display: String)],
        tierNames: Set<String>,
        authorRole: CovenantMembership.MemberRole
    ) -> [MentionEntity] {
        let canBroadcast = authorRole == .creator || authorRole == .admin || authorRole == .moderator

        return raw.compactMap { mention in
            let handle = mention.handle.lowercased()

            // Broadcast mention types (restricted)
            if handle == "everyone" {
                guard canBroadcast else { return nil }
                return MentionEntity(
                    type: .everyone,
                    entityId: "everyone",
                    display: "@everyone",
                    range: .init(location: mention.range.location, length: mention.range.length)
                )
            }
            if handle == "paid" {
                guard canBroadcast else { return nil }
                return MentionEntity(
                    type: .paid,
                    entityId: "paid",
                    display: "@paid",
                    range: .init(location: mention.range.location, length: mention.range.length)
                )
            }
            // Tier mention
            if tierNames.contains(handle) {
                guard canBroadcast else { return nil }
                return MentionEntity(
                    type: .tier,
                    entityId: handle,
                    display: "@\(handle)",
                    range: .init(location: mention.range.location, length: mention.range.length)
                )
            }
            // Room mention
            if let room = roomLookup[handle] {
                return MentionEntity(
                    type: .room,
                    entityId: room.id,
                    display: "@\(room.display)",
                    range: .init(location: mention.range.location, length: mention.range.length)
                )
            }
            // User/Creator mention
            if let user = userLookup[handle] {
                return MentionEntity(
                    type: .user,
                    entityId: user.id,
                    display: "@\(user.display)",
                    range: .init(location: mention.range.location, length: mention.range.length)
                )
            }
            // Unknown handle — skip
            return nil
        }
    }

    // MARK: - Count mass-mention targets

    /// Returns how many unique user IDs a set of mentions would notify.
    /// Used server-side to enforce rate limits, mirrored here for UI validation.
    static func estimatedTargetCount(
        mentions: [MentionEntity],
        memberCount: Int
    ) -> Int {
        var total = 0
        for mention in mentions {
            switch mention.type {
            case .everyone: total += memberCount
            case .paid:     total += memberCount  // conservative estimate
            case .tier:     total += 50            // assume avg tier size
            case .user, .creator, .room: total += 1
            }
        }
        return total
    }

    // MARK: - Rate limit check

    static let maxMentionsPerMessage = 5
    static let maxBroadcastsPerHour  = 3

    static func exceededMentionCap(_ mentions: [MentionEntity]) -> Bool {
        mentions.count > maxMentionsPerMessage
    }
}
