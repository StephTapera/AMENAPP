//
//  EditPostSystem.swift
//  AMENAPP
//
//  Meaning-aware edit infrastructure for post editing.
//

import Foundation
import SwiftUI

enum EditRestrictionReason: String, Codable, Hashable {
    case windowExpired = "window_expired"
    case postLocked = "post_locked"
    case unauthorized = "unauthorized"
    case staleVersion = "stale_version"
    case unavailable = "unavailable"
    case typeTransitionInvalid = "type_transition_invalid"
}

enum EditPolicyType: String, Codable, Hashable {
    case standard = "standard"
    case prayer = "prayer"
    case testimony = "testimony"
    case locked = "locked"
}

struct EditEligibility: Codable, Equatable, Hashable {
    var canEdit: Bool
    var editWindowExpiresAt: Date?
    var editPolicyType: EditPolicyType
    var editRestrictionReason: EditRestrictionReason?

    static let unavailable = EditEligibility(
        canEdit: false,
        editWindowExpiresAt: nil,
        editPolicyType: .locked,
        editRestrictionReason: .unavailable
    )
}

struct EditWindowPolicyState: Codable, Equatable, Hashable {
    var category: Post.PostCategory
    var duration: TimeInterval
    var policyType: EditPolicyType

    static func forCategory(_ category: Post.PostCategory) -> EditWindowPolicyState {
        switch category {
        case .openTable, .tip, .funFact:
            return .init(category: category, duration: 15 * 60, policyType: .standard)
        case .prayer:
            return .init(category: category, duration: 30 * 60, policyType: .prayer)
        case .testimonies:
            return .init(category: category, duration: 60 * 60, policyType: .testimony)
        }
    }

    func expiryDate(createdAt: Date) -> Date {
        createdAt.addingTimeInterval(duration)
    }
}

struct EditPostDirtyFields: OptionSet, Hashable {
    let rawValue: Int

    static let text = EditPostDirtyFields(rawValue: 1 << 0)
    static let media = EditPostDirtyFields(rawValue: 1 << 1)
    static let topic = EditPostDirtyFields(rawValue: 1 << 2)
    static let type = EditPostDirtyFields(rawValue: 1 << 3)

    var isDirty: Bool { !isEmpty }
}

struct EditPostMediaDraftItem: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var remoteURL: String?
    var localImageData: Data?
    var orderIndex: Int

    var isLocalOnly: Bool { remoteURL == nil && localImageData != nil }

    static func fromPost(_ post: Post) -> [EditPostMediaDraftItem] {
        (post.imageURLs ?? []).enumerated().map { index, url in
            EditPostMediaDraftItem(id: url, remoteURL: url, localImageData: nil, orderIndex: index)
        }
    }
}

struct EditPostDraftSnapshot: Codable, Equatable {
    var postId: String
    var baseEditVersion: Int
    var text: String
    var topicTag: String?
    var category: Post.PostCategory
    var media: [EditPostMediaDraftItem]
    var savedAt: Date
}

struct PostEditSessionDraftKey: Hashable {
    let userId: String
    let postId: String
}

final class EditPostDraftRecovery {
    static let shared = EditPostDraftRecovery()

    private let defaults = UserDefaults.standard
    private let prefix = "amen.editDraft."

    private init() {}

    func loadDraft(for key: PostEditSessionDraftKey) -> EditPostDraftSnapshot? {
        guard let data = defaults.data(forKey: storageKey(for: key)) else { return nil }
        return try? JSONDecoder().decode(EditPostDraftSnapshot.self, from: data)
    }

    func saveDraft(_ draft: EditPostDraftSnapshot, for key: PostEditSessionDraftKey) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: storageKey(for: key))
    }

    func clearDraft(for key: PostEditSessionDraftKey) {
        defaults.removeObject(forKey: storageKey(for: key))
    }

    private func storageKey(for key: PostEditSessionDraftKey) -> String {
        prefix + key.userId + "." + key.postId
    }
}

struct EditPostDiffResult: Equatable {
    var dirtyFields: EditPostDirtyFields
    var addedMediaCount: Int
    var removedMediaCount: Int
    var reorderedMedia: Bool
    var textDeltaRatio: Double
    var namedEntityShiftScore: Double
    var semanticChangeScore: Double
}

enum EditFieldValidationIssue: Equatable {
    case emptyText
    case textTooLong
    case mediaRequired
    case invalidTypeTransition
}

struct EditPostValidationResult: Equatable {
    var issues: [EditFieldValidationIssue]

    var canSave: Bool { issues.isEmpty }
}

struct EditIntelligenceResult: Equatable {
    var primaryType: PostEditType
    var secondaryTypes: [PostEditType]
    var meaningChangeLevel: MeaningChangeLevel
    var semanticChangeScore: Double
    var threadIntegrityRisk: ThreadIntegrityRiskLevel
    var recommendUpdateInstead: Bool
    var notices: [String]
    var evidenceSuggestion: String?
    var transparencyLevel: EditTransparencyLevel
}

enum EditSaveMode: Equatable {
    case edit
    case updateInstead
}

struct EditPostRequest {
    var postId: String
    var expectedVersion: Int
    var editedText: String
    var topicTag: String?
    var category: Post.PostCategory
    var media: [EditPostMediaDraftItem]
    var clientEditSessionStartedAt: Date
    var intelligence: EditIntelligenceResult
    var saveMode: EditSaveMode
}

struct EditPostResult {
    var updatedPost: Post
    var editMetadata: PostEditMetadata?
    var eligibility: EditEligibility
    var notices: [String]
    var updateCreated: PostUpdateItem?
}

enum PostEditServiceError: LocalizedError, Equatable {
    case editWindowExpired(Date?)
    case staleVersion
    case postUnavailable
    case unauthorized
    case moderationBlocked(String)
    case invalidTypeTransition
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .editWindowExpired:
            return "The edit window for this post has closed."
        case .staleVersion:
            return "This post changed while you were editing. Refresh and try again."
        case .postUnavailable:
            return "This post is no longer available."
        case .unauthorized:
            return "You can only edit your own posts."
        case .moderationBlocked(let message):
            return message
        case .invalidTypeTransition:
            return "That post type change is not supported."
        case .saveFailed(let message):
            return message
        }
    }
}

enum EditPostDiffEngine {
    static func diff(
        original: Post,
        text: String,
        topicTag: String?,
        category: Post.PostCategory,
        media: [EditPostMediaDraftItem]
    ) -> EditPostDiffResult {
        let normalizedOriginal = normalizeText(original.content)
        let normalizedEdited = normalizeText(text)

        var dirty: EditPostDirtyFields = []
        if normalizedOriginal != normalizedEdited { dirty.insert(.text) }
        if original.topicTag?.trimmingCharacters(in: .whitespacesAndNewlines) != topicTag?.trimmingCharacters(in: .whitespacesAndNewlines) {
            dirty.insert(.topic)
        }
        if original.category != category {
            dirty.insert(.type)
        }

        let originalURLs = original.imageURLs ?? []
        let editedRemoteURLs = media.compactMap(\.remoteURL)
        let addedMediaCount = media.filter(\.isLocalOnly).count
        let removedMediaCount = max(originalURLs.count - editedRemoteURLs.count, 0)
        let reordered = originalURLs != editedRemoteURLs && Set(originalURLs) == Set(editedRemoteURLs)
        if addedMediaCount > 0 || removedMediaCount > 0 || reordered {
            dirty.insert(.media)
        }

        let originalTokens = Set(normalizedOriginal.split(separator: " ").map(String.init))
        let editedTokens = Set(normalizedEdited.split(separator: " ").map(String.init))
        let unionCount = max(originalTokens.union(editedTokens).count, 1)
        let changedTokens = originalTokens.symmetricDifference(editedTokens).count
        let textDeltaRatio = Double(changedTokens) / Double(unionCount)

        let originalEntities = extractEntities(from: original.content)
        let editedEntities = extractEntities(from: text)
        let entityUnion = max(originalEntities.union(editedEntities).count, 1)
        let entityShift = Double(originalEntities.symmetricDifference(editedEntities).count) / Double(entityUnion)

        let semanticChangeScore = min(1.0, (textDeltaRatio * 0.7) + (entityShift * 0.3) + (dirty.contains(.type) ? 0.35 : 0))

        return EditPostDiffResult(
            dirtyFields: dirty,
            addedMediaCount: addedMediaCount,
            removedMediaCount: removedMediaCount,
            reorderedMedia: reordered,
            textDeltaRatio: textDeltaRatio,
            namedEntityShiftScore: entityShift,
            semanticChangeScore: semanticChangeScore
        )
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[\\p{P}\\p{S}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractEntities(from text: String) -> Set<String> {
        let tokens = text.split(separator: " ").map(String.init)
        return Set(tokens.filter { token in
            guard token.count > 2 else { return false }
            return token.first?.isUppercase == true || token.contains("http") || token.contains(":")
        }.map { $0.lowercased() })
    }
}

enum EditIntelligenceEngine {
    static func analyze(
        original: Post,
        text: String,
        topicTag: String?,
        category: Post.PostCategory,
        media: [EditPostMediaDraftItem]
    ) -> EditIntelligenceResult {
        let diff = EditPostDiffEngine.diff(original: original, text: text, topicTag: topicTag, category: category, media: media)
        let normalizedOriginal = original.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEdited = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var primary: PostEditType = .clarityImprovement
        var secondary: [PostEditType] = []

        if diff.dirtyFields == .text, diff.textDeltaRatio < 0.08, diff.namedEntityShiftScore < 0.05 {
            primary = .typoFix
        } else if diff.dirtyFields.contains(.media) && diff.dirtyFields.subtracting(.media).isEmpty {
            primary = .mediaUpdate
        } else if diff.dirtyFields.contains(.type) {
            primary = .typeChange
            secondary.append(.substantiveChange)
        } else if diff.dirtyFields.contains(.topic) {
            primary = .topicChange
        } else if normalizedOriginal.contains("update") || normalizedEdited.contains("update") {
            primary = .contextUpdate
        }

        if primary != .typoFix && normalizedOriginal != normalizedEdited {
            if textContainsCorrectionCue(normalizedEdited) {
                secondary.append(.correction)
            }
            if diff.semanticChangeScore > 0.45 {
                secondary.append(.substantiveChange)
            } else if diff.textDeltaRatio < 0.2 {
                secondary.append(.clarityImprovement)
            } else {
                secondary.append(.toneAdjustment)
            }
        }
        if diff.dirtyFields.contains(.media) && primary != .mediaUpdate {
            secondary.append(.mediaUpdate)
        }
        if diff.dirtyFields.contains(.topic) && primary != .topicChange {
            secondary.append(.topicChange)
        }

        let meaningLevel: MeaningChangeLevel = {
            switch diff.semanticChangeScore {
            case ..<0.08: return .noMeaningChange
            case ..<0.25: return .lowChange
            case ..<0.55: return .mediumChange
            default: return .highChange
            }
        }()

        let engagementWeight = original.commentCount + original.repostCount + (original.prayerEchoCount ?? 0)
        let risk: ThreadIntegrityRiskLevel = {
            if meaningLevel == .noMeaningChange || primary == .typoFix { return .safeToEditSilently }
            if engagementWeight == 0 { return .minorContextShift }
            if meaningLevel == .highChange || original.repostCount > 0 { return .majorThreadIntegrityRisk }
            return .potentialReplyMisalignment
        }()

        var notices: [String] = []
        if primary == .typoFix {
            notices.append("Typo fix detected.")
        }
        if meaningLevel == .mediumChange || meaningLevel == .highChange {
            notices.append("This changes the meaning of your post.")
        }
        if risk == .potentialReplyMisalignment || risk == .majorThreadIntegrityRisk {
            notices.append("Some earlier replies may read differently after this edit.")
        }
        if category != original.category {
            notices.append("This edit changes the post from \(original.category.displayName) to \(category.displayName).")
        }
        if diff.dirtyFields.contains(.media) && media.first?.remoteURL != original.imageURLs?.first {
            notices.append("Changing the lead image can change how the post is read in feeds.")
        }

        let recommendUpdateInstead = (meaningLevel == .highChange && engagementWeight > 0) || risk == .majorThreadIntegrityRisk
        if recommendUpdateInstead {
            notices.append("This may be better posted as an update.")
        }

        let evidenceSuggestion: String? = {
            if looksLikeSourceText(text) {
                return "This looks like a source, verse, or citation. Add it to the evidence field too."
            }
            return nil
        }()

        let transparency: EditTransparencyLevel = {
            if secondary.contains(.correction) { return .corrected }
            if primary == .mediaUpdate { return .mediaChanged }
            if primary == .contextUpdate { return .updatedContext }
            if meaningLevel == .mediumChange || meaningLevel == .highChange { return .substantiveEdit }
            if primary == .typoFix { return .typoFix }
            return .clarified
        }()

        return EditIntelligenceResult(
            primaryType: primary,
            secondaryTypes: Array(Set(secondary)).filter { $0 != primary },
            meaningChangeLevel: meaningLevel,
            semanticChangeScore: diff.semanticChangeScore,
            threadIntegrityRisk: risk,
            recommendUpdateInstead: recommendUpdateInstead,
            notices: notices,
            evidenceSuggestion: evidenceSuggestion,
            transparencyLevel: transparency
        )
    }

    static func validate(
        original: Post,
        text: String,
        category: Post.PostCategory,
        media: [EditPostMediaDraftItem]
    ) -> EditPostValidationResult {
        var issues: [EditFieldValidationIssue] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { issues.append(.emptyText) }
        if trimmed.count > 500 { issues.append(.textTooLong) }
        if !isValidTransition(from: original.category, to: category) {
            issues.append(.invalidTypeTransition)
        }
        return EditPostValidationResult(issues: issues)
    }

    static func helperText(for category: Post.PostCategory, text: String) -> String {
        if looksLikeSourceText(text) {
            return "This sounds like a factual claim. Add a source or verse if you can."
        }
        switch category {
        case .openTable:
            return "Refine the original meaning without making replies harder to understand."
        case .prayer:
            return "If your request has materially changed, consider adding context instead of overwriting it."
        case .testimonies:
            return "Clarify what happened without losing the original witness of the post."
        case .tip, .funFact:
            return "Keep the edit clear and faithful to what readers already engaged with."
        }
    }

    static func isValidTransition(from: Post.PostCategory, to: Post.PostCategory) -> Bool {
        switch (from, to) {
        case (_, _) where from == to:
            return true
        case (.openTable, .prayer), (.openTable, .testimonies), (.prayer, .testimonies), (.testimonies, .prayer):
            return true
        case (.openTable, .tip), (.openTable, .funFact), (.tip, .openTable), (.funFact, .openTable):
            return true
        default:
            return false
        }
    }

    static func looksLikeSourceText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("http://")
            || lowered.contains("https://")
            || lowered.contains("john ")
            || lowered.contains("romans ")
            || lowered.contains(":")
            || lowered.contains("source:")
    }

    private static func textContainsCorrectionCue(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("correction")
            || lowered.contains("to clarify")
            || lowered.contains("i was wrong")
            || lowered.contains("updated")
    }
}
