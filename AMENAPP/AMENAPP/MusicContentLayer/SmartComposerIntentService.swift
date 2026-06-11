// SmartComposerIntentService.swift
// AMENAPP — MusicContentLayer
//
// Keyword-based post intent classifier + composer suggestion chips.
// No external API in v1 — all classification is local.

import SwiftUI

// MARK: - Post Intent Type

enum PostIntentType: String, Codable, Sendable, CaseIterable {
    case prayerRequest
    case sermonNote
    case testimony
    case eventAnnouncement
    case scriptureQuote
    case songShare
    case worshipRelease
    case communityDiscussion

    var displayName: String {
        switch self {
        case .prayerRequest:       return "Prayer Request"
        case .sermonNote:          return "Sermon Note"
        case .testimony:           return "Testimony"
        case .eventAnnouncement:   return "Event Announcement"
        case .scriptureQuote:      return "Scripture Quote"
        case .songShare:           return "Song Share"
        case .worshipRelease:      return "Worship Release"
        case .communityDiscussion: return "Community Discussion"
        }
    }

    var sfSymbol: String {
        switch self {
        case .prayerRequest:       return "hands.sparkles"
        case .sermonNote:          return "note.text"
        case .testimony:           return "person.wave.2"
        case .eventAnnouncement:   return "calendar.badge.plus"
        case .scriptureQuote:      return "book.closed"
        case .songShare:           return "music.note"
        case .worshipRelease:      return "music.mic"
        case .communityDiscussion: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Composer Suggestion Chip

struct ComposerSuggestionChip: Codable, Sendable, Identifiable {
    let id: String
    let label: String
    let sfSymbol: String
    let action: ComposerChipAction
}

enum ComposerChipAction: String, Codable, Sendable {
    case makeChurchNote
    case attachWorshipPlaylist
    case addPrayerPrompt
    case addScripture
    case makePulseUpdate
    case setMembersOnly
    case addEventDetails
}

// MARK: - Content Attachment

/// A generic attachment that can be linked to a post during composition.
struct ContentAttachment: Codable, Sendable, Identifiable {
    let id: String
    let type: ContentAttachmentType
    let title: String
    let subtitle: String?
    let artworkURL: URL?
}

enum ContentAttachmentType: String, Codable, Sendable {
    case song
    case album
    case playlist
    case video
    case image
    case document
    case link
}

// MARK: - Classification Result

/// The synchronous result returned by `classify(draftText:hasAttachment:accountType:)`.
/// Exposed so tests can call the method directly without async overhead.
struct IntentClassificationResult: Sendable {
    let intent: PostIntentType
    let confidence: Double
    let suggestedTags: [String]
    let shouldSuggestChurchNote: Bool
    let shouldSuggestWorshipPlaylist: Bool
}

// MARK: - Service

@MainActor final class SmartComposerIntentService: ObservableObject {

    @Published private(set) var detectedIntent: PostIntentType = .communityDiscussion
    @Published private(set) var confidence: Double = 0.0
    @Published private(set) var suggestedChips: [ComposerSuggestionChip] = []
    @Published private(set) var safetyFlags: [String] = []
    @Published private(set) var isAnalyzing = false

    // MARK: - Sensitive term list (hardcoded, v1)

    private static let sensitiveTerms: [String] = [
        "suicide", "self-harm", "kill myself", "want to die",
        "abuse", "molest", "trafficking", "exploit"
    ]

    // MARK: - Async entry point used by the composer UI

    func analyzeIntent(
        draftText: String,
        attachments: [ContentAttachment],
        accountType: String,
        communityContext: String?
    ) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Simulate a brief analysis delay so the UI can show a loading state.
        try? await Task.sleep(nanoseconds: 400_000_000)

        let hasMusicAttachment = attachments.contains(where: {
            $0.type == .song || $0.type == .album
        })

        let result = classify(
            draftText: draftText,
            hasAttachment: hasMusicAttachment,
            accountType: accountType
        )

        detectedIntent = result.intent
        confidence = result.confidence
        suggestedChips = chips(for: result.intent)
        safetyFlags = detectSafetyFlags(in: draftText)
    }

    // MARK: - Synchronous classifier (also called directly by tests)

    func classify(
        draftText: String,
        hasAttachment: Bool,
        accountType: String
    ) -> IntentClassificationResult {
        let lower = draftText.lowercased()

        // 1. Scripture reference — check early; high signal
        let scripturePattern = #"[A-Za-z]+\s+\d+:\d+"#
        if draftText.range(of: scripturePattern, options: .regularExpression) != nil {
            return makeResult(
                intent: .scriptureQuote, confidence: 0.75,
                tags: ["scripture", "bible", "faith"],
                churchNote: true, worshipPlaylist: false
            )
        }

        // 2. Song share by emoji/keyword — also catches music attachments
        let songKeywords = ["listening to", "on repeat", "worship song", "gospel"]
        let songEmoji = draftText.contains("🎵") || draftText.contains("🎶")
            || draftText.contains("🎸") || draftText.contains("🎹")
        let songHits = songKeywords.filter { lower.contains($0) }.count + (songEmoji ? 1 : 0)
        if songHits >= 1 || hasAttachment {
            let totalSongSignals = songHits + (hasAttachment ? 2 : 0)
            // Worship release wins for church accounts with release keywords
            let releaseKeywords = ["new", "release", "album", "out now"]
            let releaseHits = releaseKeywords.filter { lower.contains($0) }.count
            if accountType == "church" && releaseHits >= 1 {
                return makeResult(
                    intent: .worshipRelease,
                    confidence: min(0.5 + Double(releaseHits) * 0.15, 1.0),
                    tags: ["worship", "music", "release"],
                    churchNote: true, worshipPlaylist: true
                )
            }
            return makeResult(
                intent: .songShare,
                confidence: min(0.4 + Double(totalSongSignals) * 0.12, 1.0),
                tags: ["music", "worship"],
                churchNote: false, worshipPlaylist: true
            )
        }

        // 3. Prayer — with or without emoji
        let prayerKeywords = ["pray", "prayer", "lord", "jesus"]
        let prayerEmoji = draftText.contains("❤️") || draftText.contains("🙏")
        let prayerHits = prayerKeywords.filter { lower.contains($0) }.count
        if prayerHits >= 1 {
            let boost: Double = prayerEmoji ? 0.2 : 0.0
            return makeResult(
                intent: .prayerRequest,
                confidence: min(0.35 + Double(prayerHits) * 0.12 + boost, 1.0),
                tags: ["prayer", "faith"],
                churchNote: true, worshipPlaylist: false
            )
        }

        // 4. Sermon note
        let sermonKeywords = ["sermon", "preached", "pastor", "church notes"]
        let sermonHits = sermonKeywords.filter { lower.contains($0) }.count
        if sermonHits >= 1 {
            return makeResult(
                intent: .sermonNote,
                confidence: min(0.5 + Double(sermonHits) * 0.15, 1.0),
                tags: ["sermon", "church", "notes"],
                churchNote: true, worshipPlaylist: false
            )
        }

        // 5. Testimony
        let testimonyKeywords = ["testified", "testimony", "god did"]
        let testimonyHits = testimonyKeywords.filter { lower.contains($0) }.count
        if testimonyHits >= 1 {
            return makeResult(
                intent: .testimony,
                confidence: min(0.5 + Double(testimonyHits) * 0.15, 1.0),
                tags: ["testimony", "faith"],
                churchNote: false, worshipPlaylist: false
            )
        }

        // 6. Event announcement
        let eventKeywords = ["join us", "event", "sunday", "service at"]
        let eventHits = eventKeywords.filter { lower.contains($0) }.count
        if eventHits >= 1 {
            return makeResult(
                intent: .eventAnnouncement,
                confidence: min(0.45 + Double(eventHits) * 0.15, 1.0),
                tags: ["event", "church", "community"],
                churchNote: false, worshipPlaylist: false
            )
        }

        // 7. Worship release for church accounts without a music attachment
        if accountType == "church" {
            let releaseKeywords = ["new", "release", "album", "out now"]
            let releaseHits = releaseKeywords.filter { lower.contains($0) }.count
            if releaseHits >= 1 {
                return makeResult(
                    intent: .worshipRelease,
                    confidence: min(0.45 + Double(releaseHits) * 0.15, 1.0),
                    tags: ["worship", "music", "release"],
                    churchNote: true, worshipPlaylist: true
                )
            }
        }

        // 8. Default — low confidence community discussion
        return makeResult(
            intent: .communityDiscussion, confidence: 0.1,
            tags: [],
            churchNote: false, worshipPlaylist: false
        )
    }

    // MARK: - Private helpers

    private func makeResult(
        intent: PostIntentType,
        confidence: Double,
        tags: [String],
        churchNote: Bool,
        worshipPlaylist: Bool
    ) -> IntentClassificationResult {
        IntentClassificationResult(
            intent: intent,
            confidence: confidence,
            suggestedTags: tags,
            shouldSuggestChurchNote: churchNote,
            shouldSuggestWorshipPlaylist: worshipPlaylist
        )
    }

    private func chips(for intent: PostIntentType) -> [ComposerSuggestionChip] {
        switch intent {
        case .prayerRequest:
            return [
                ComposerSuggestionChip(id: "addPrayerPrompt",
                                       label: "Add Prayer",
                                       sfSymbol: "hands.sparkles",
                                       action: .addPrayerPrompt),
                ComposerSuggestionChip(id: "setMembersOnly",
                                       label: "Members Only",
                                       sfSymbol: "person.badge.shield.checkmark",
                                       action: .setMembersOnly)
            ]
        case .sermonNote:
            return [
                ComposerSuggestionChip(id: "makeChurchNote",
                                       label: "Church Note",
                                       sfSymbol: "note.text",
                                       action: .makeChurchNote),
                ComposerSuggestionChip(id: "attachWorshipPlaylist",
                                       label: "Add Playlist",
                                       sfSymbol: "music.note.list",
                                       action: .attachWorshipPlaylist),
                ComposerSuggestionChip(id: "makePulseUpdate",
                                       label: "Pulse Update",
                                       sfSymbol: "bolt.heart",
                                       action: .makePulseUpdate)
            ]
        case .scriptureQuote:
            return [
                ComposerSuggestionChip(id: "addScripture",
                                       label: "Add Scripture",
                                       sfSymbol: "book.closed",
                                       action: .addScripture),
                ComposerSuggestionChip(id: "makeChurchNote",
                                       label: "Church Note",
                                       sfSymbol: "note.text",
                                       action: .makeChurchNote)
            ]
        case .songShare:
            return [
                ComposerSuggestionChip(id: "attachWorshipPlaylist",
                                       label: "Add Playlist",
                                       sfSymbol: "music.note.list",
                                       action: .attachWorshipPlaylist),
                ComposerSuggestionChip(id: "makePulseUpdate",
                                       label: "Pulse Update",
                                       sfSymbol: "bolt.heart",
                                       action: .makePulseUpdate)
            ]
        case .worshipRelease:
            return [
                ComposerSuggestionChip(id: "attachWorshipPlaylist",
                                       label: "Add Playlist",
                                       sfSymbol: "music.note.list",
                                       action: .attachWorshipPlaylist),
                ComposerSuggestionChip(id: "makePulseUpdate",
                                       label: "Pulse Update",
                                       sfSymbol: "bolt.heart",
                                       action: .makePulseUpdate),
                ComposerSuggestionChip(id: "makeChurchNote",
                                       label: "Church Note",
                                       sfSymbol: "note.text",
                                       action: .makeChurchNote)
            ]
        case .testimony, .eventAnnouncement, .communityDiscussion:
            return []
        }
    }

    private func detectSafetyFlags(in text: String) -> [String] {
        let lower = text.lowercased()
        return Self.sensitiveTerms.filter { lower.contains($0) }
    }
}

// MARK: - IntentSuggestionPill

struct IntentSuggestionPill: View {
    let intent: PostIntentType
    let confidence: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: intent.sfSymbol)
                .font(.caption.weight(.semibold))
            Text(intent.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background {
            Capsule(style: .continuous)
                .fill(reduceTransparency ? Color(.systemBackground) : AnyShapeStyle(.ultraThinMaterial))
                .overlay {
                    if !reduceTransparency {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    }
                }
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        .opacity(0.6 + confidence * 0.4)
        .accessibilityLabel("\(intent.displayName), \(Int(confidence * 100))% confidence")
    }
}

// MARK: - SmartComposerSuggestionsBar

struct SmartComposerSuggestionsBar: View {
    let chips: [ComposerSuggestionChip]
    let intent: PostIntentType
    let confidence: Double
    let onChipTap: (ComposerChipAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldShow: Bool { !chips.isEmpty || confidence > 0.3 }

    var body: some View {
        if shouldShow {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    IntentSuggestionPill(intent: intent, confidence: confidence)

                    ForEach(chips) { chip in
                        Button {
                            onChipTap(chip.action)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: chip.sfSymbol)
                                    .font(.caption.weight(.semibold))
                                Text(chip.label)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .amenLiquidGlassCapsuleSurface(isSelected: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(chip.label)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
        }
    }
}

// MARK: - Preview

#Preview("SmartComposerSuggestionsBar — Sermon Note") {
    @Previewable @State var tappedAction: ComposerChipAction? = nil

    VStack(spacing: 12) {
        SmartComposerSuggestionsBar(
            chips: [
                ComposerSuggestionChip(id: "makeChurchNote",
                                       label: "Church Note",
                                       sfSymbol: "note.text",
                                       action: .makeChurchNote),
                ComposerSuggestionChip(id: "attachWorshipPlaylist",
                                       label: "Add Playlist",
                                       sfSymbol: "music.note.list",
                                       action: .attachWorshipPlaylist),
                ComposerSuggestionChip(id: "makePulseUpdate",
                                       label: "Pulse Update",
                                       sfSymbol: "bolt.heart",
                                       action: .makePulseUpdate)
            ],
            intent: .sermonNote,
            confidence: 0.82,
            onChipTap: { action in tappedAction = action }
        )

        if let action = tappedAction {
            Text("Tapped: \(action.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.vertical)
    .background(Color(.systemGroupedBackground))
}
