// SmartComposerIntentService.swift
// AMENAPP — MusicContentLayer
//
// Local keyword-based post intent classifier + SwiftUI suggestion UI.
// No network calls; fully deterministic for v1.
// Accessible: Dynamic Type, Reduced Motion, Reduced Transparency, VoiceOver.

import SwiftUI

// MARK: - PostIntentResult

struct PostIntentResult: Sendable {
    let intent: PostIntentType
    let confidence: Double              // 0.0–1.0
    let suggestedTags: [String]
    let safetyFlags: [String]
    let shouldSuggestChurchNote: Bool
    let shouldSuggestWorshipPlaylist: Bool
    let shouldSuggestPulseUpdate: Bool
}

// MARK: - PostIntentType display extensions
// (Core enum is defined in MusicContentContracts.swift)

extension PostIntentType {
    var displayLabel: String {
        switch self {
        case .songShare:             return "Song Share"
        case .albumShare:            return "Album Share"
        case .sermonNote:            return "Sermon Note"
        case .churchNote:            return "Church Note"
        case .prayerRequest:         return "Prayer Request"
        case .testimony:             return "Testimony"
        case .eventAnnouncement:     return "Event"
        case .scriptureQuote:        return "Scripture"
        case .devotional:            return "Devotional"
        case .resourceShare:         return "Resource"
        case .question:              return "Question"
        case .poll:                  return "Poll"
        case .worshipRelease:        return "Worship Release"
        case .orgUpdate:             return "Ministry Update"
        case .communityDiscussion:   return "Discussion"
        }
    }

    var intentIcon: String {
        switch self {
        case .songShare, .albumShare, .worshipRelease: return "music.note"
        case .sermonNote, .churchNote:                 return "mic.fill"
        case .prayerRequest:                           return "hands.and.sparkles.fill"
        case .testimony:                               return "star.fill"
        case .eventAnnouncement:                       return "calendar"
        case .scriptureQuote:                          return "book.fill"
        case .devotional:                              return "sunrise.fill"
        case .resourceShare:                           return "link"
        case .question:                                return "questionmark.circle.fill"
        case .poll:                                    return "chart.bar.fill"
        case .orgUpdate:                               return "building.columns.fill"
        case .communityDiscussion:                     return "bubble.left.and.bubble.right.fill"
        }
    }

    var suggestedAttachmentType: String? {
        switch self {
        case .songShare:         return "song"
        case .albumShare:        return "album"
        case .sermonNote:        return "sermon_clip"
        case .churchNote:        return "sermon_clip"
        case .worshipRelease:    return "worship_set"
        case .devotional:        return "devotional_audio"
        case .resourceShare:     return "podcast_episode"
        default:                 return nil
        }
    }

    var suggestedAudience: String {
        switch self {
        case .prayerRequest:       return "Your Church"
        case .sermonNote:          return "Your Church"
        case .churchNote:          return "Your Church"
        case .testimony:           return "Community"
        case .eventAnnouncement:   return "Public"
        case .orgUpdate:           return "Your Church"
        default:                   return "Public"
        }
    }
}

// MARK: - SmartComposerIntentService

final class SmartComposerIntentService: Sendable {

    // MARK: Classification

    func classify(
        draftText: String,
        hasAttachment: Bool,
        accountType: String
    ) -> PostIntentResult {
        let lower = draftText.lowercased()

        // Score each intent
        var scores: [PostIntentType: Int] = [:]

        // Prayer
        let prayerKeywords = ["pray", "prayer", "praying", "lord", "god", "jesus", "savior",
                              "father", "holy spirit", "intercede", "amen", "bless", "healing",
                              "please pray", "keep us in prayer"]
        scores[.prayerRequest] = prayerKeywords.filter { lower.contains($0) }.count

        // Scripture
        let scripturePattern = #"\b[1-3]?\s*[A-Za-z]+\s+\d+:\d+"#
        let scriptureMatches = (try? NSRegularExpression(pattern: scripturePattern))
            .map { $0.numberOfMatches(in: draftText, range: NSRange(draftText.startIndex..., in: draftText)) } ?? 0
        scores[.scriptureQuote] = scriptureMatches * 2

        // Sermon / Church Note
        let sermonKeywords = ["sermon", "pastor", "preached", "preaching", "message", "church service",
                              "sunday service", "wednesday service", "bible study"]
        scores[.sermonNote] = sermonKeywords.filter { lower.contains($0) }.count

        let churchNoteKeywords = ["took notes", "my notes", "notes from", "church notes",
                                  "service notes", "today's message"]
        scores[.churchNote] = churchNoteKeywords.filter { lower.contains($0) }.count

        // Testimony
        let testimonyKeywords = ["testimony", "blessed", "miracle", "god is good", "god showed up",
                                 "breakthrough", "healed", "delivered", "grateful to god", "thankful to god"]
        scores[.testimony] = testimonyKeywords.filter { lower.contains($0) }.count

        // Song / Music
        let musicKeywords = ["🎵", "🎶", "🎤", "listening to", "song", "album", "music",
                             "worship song", "gospel", "hymn", "on repeat", "just dropped"]
        scores[.songShare] = musicKeywords.filter { lower.contains($0) }.count

        // Album
        let albumKeywords = ["album", "new album", "just released", "full album", "tracklist"]
        scores[.albumShare] = albumKeywords.filter { lower.contains($0) }.count

        // Worship Release
        let worshipReleaseKeywords = ["worship release", "new worship", "releasing", "out now", "available now"]
        scores[.worshipRelease] = worshipReleaseKeywords.filter { lower.contains($0) }.count

        // Event
        let eventKeywords = ["event", "join us", "sunday", "saturday", "come out", "you're invited",
                             "rsvp", "registration", "tonight", "this weekend"]
        scores[.eventAnnouncement] = eventKeywords.filter { lower.contains($0) }.count

        // Devotional
        let devotionalKeywords = ["devotional", "devotion", "quiet time", "morning prayer",
                                  "daily word", "daily bread", "reflection"]
        scores[.devotional] = devotionalKeywords.filter { lower.contains($0) }.count

        // Resource
        let resourceKeywords = ["check out", "resource", "article", "book recommendation",
                                "podcast", "link", "sharing this", "read this"]
        scores[.resourceShare] = resourceKeywords.filter { lower.contains($0) }.count

        // Question
        let questionKeywords = ["?", "what do you think", "anyone know", "how do you",
                                "can someone", "asking for", "need advice"]
        scores[.question] = questionKeywords.filter { lower.contains($0) }.count

        // Poll
        let pollKeywords = ["poll", "vote", "which one", "a or b", "a) ", "b) ", "option 1", "option 2"]
        scores[.poll] = pollKeywords.filter { lower.contains($0) }.count

        // Org Update
        let orgKeywords = ["ministry update", "organization update", "our church", "we are",
                           "our team", "ministry news", "church announcement"]
        scores[.orgUpdate] = orgKeywords.filter { lower.contains($0) }.count

        // Community Discussion
        let discussionKeywords = ["let's talk", "discussion", "thoughts on", "what are your thoughts",
                                  "community", "conversation", "thoughts?"]
        scores[.communityDiscussion] = discussionKeywords.filter { lower.contains($0) }.count

        // Pick highest score
        let best = scores.max(by: { $0.value < $1.value })
        let bestIntent = best?.key ?? .communityDiscussion
        let bestScore = best?.value ?? 0

        // Short text with no keywords → general
        let wordCount = draftText.split(separator: " ").count
        guard bestScore > 0, wordCount >= 2 else {
            return PostIntentResult(
                intent: .communityDiscussion,
                confidence: 0.0,
                suggestedTags: [],
                safetyFlags: [],
                shouldSuggestChurchNote: false,
                shouldSuggestWorshipPlaylist: false,
                shouldSuggestPulseUpdate: false
            )
        }

        // Confidence: scale by keyword hits relative to a cap of 4
        let confidence = min(Double(bestScore) / 4.0, 1.0)

        let tags = suggestedTags(for: bestIntent, text: lower)
        let shouldChurchNote = [PostIntentType.sermonNote, .churchNote, .scriptureQuote].contains(bestIntent)
        let shouldPlaylist = [PostIntentType.songShare, .albumShare, .worshipRelease, .devotional].contains(bestIntent)
        let shouldPulse = confidence >= 0.5

        return PostIntentResult(
            intent: bestIntent,
            confidence: confidence,
            suggestedTags: tags,
            safetyFlags: [],
            shouldSuggestChurchNote: shouldChurchNote,
            shouldSuggestWorshipPlaylist: shouldPlaylist,
            shouldSuggestPulseUpdate: shouldPulse
        )
    }

    // MARK: Suggested Tags

    private func suggestedTags(for intent: PostIntentType, text: String) -> [String] {
        switch intent {
        case .prayerRequest:       return ["#prayer", "#faith", "#intercession"]
        case .sermonNote:          return ["#sermon", "#churchnotes", "#sunday"]
        case .churchNote:          return ["#churchnotes", "#sermon", "#worship"]
        case .testimony:           return ["#testimony", "#blessed", "#godisgreat"]
        case .songShare:           return ["#worship", "#music", "#christianmusic"]
        case .albumShare:          return ["#newmusic", "#album", "#christianmusic"]
        case .worshipRelease:      return ["#newrelease", "#worship", "#gospel"]
        case .eventAnnouncement:   return ["#event", "#community", "#church"]
        case .scriptureQuote:      return ["#scripture", "#bible", "#wordofgod"]
        case .devotional:          return ["#devotional", "#quiettime", "#faith"]
        case .resourceShare:       return ["#resource", "#faith", "#community"]
        case .question:            return ["#question", "#community", "#help"]
        case .poll:                return ["#poll", "#community"]
        case .orgUpdate:           return ["#ministry", "#church", "#update"]
        case .communityDiscussion: return ["#community", "#discussion", "#faith"]
        }
    }
}

// MARK: - IntentSuggestionPill

struct IntentSuggestionPill: View {
    let result: PostIntentResult?
    let onApply: (PostIntentType) -> Void
    var onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var isDismissed = false

    private var isVisible: Bool {
        guard let r = result else { return false }
        return r.confidence >= 0.3 && !isDismissed
    }

    var body: some View {
        Group {
            if let r = result, isVisible {
                pillContent(r)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.94))
                    )
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.36, dampingFraction: 0.72),
            value: isVisible
        )
        .opacity(isVisible ? 1 : 0)
    }

    @ViewBuilder
    private func pillContent(_ r: PostIntentResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: r.intent.intentIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(r.intent.displayLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button {
                onApply(r.intent)
            } label: {
                Text("Apply")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply \(r.intent.displayLabel) intent")

            Button {
                if reduceMotion {
                    isDismissed = true
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isDismissed = true
                    }
                }
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(pillBackground)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    contrast == .increased
                        ? Color.primary.opacity(0.5)
                        : Color.white.opacity(0.22),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Intent suggestion: \(r.intent.displayLabel)")
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.08)))
        }
    }
}

// MARK: - IntentSuggestionPanel

struct IntentSuggestionPanel: View {
    let result: PostIntentResult
    let onSuggestChurchNote: () -> Void
    let onSuggestPlaylist: () -> Void
    var onSuggestPulse: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: result.intent.intentIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Looks like a \(result.intent.displayLabel)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                if result.shouldSuggestChurchNote {
                    chipButton(label: "Make church note?", icon: "mic.fill", action: onSuggestChurchNote)
                }
                if result.shouldSuggestWorshipPlaylist {
                    chipButton(label: "Attach worship playlist?", icon: "music.note.list", action: onSuggestPlaylist)
                }
                if result.shouldSuggestPulseUpdate, let pulse = onSuggestPulse {
                    chipButton(label: "Add to Pulse?", icon: "bolt.fill", action: pulse)
                }
            }
        }
        .padding(14)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    contrast == .increased
                        ? Color.primary.opacity(0.4)
                        : Color.white.opacity(0.18),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func chipButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.12))
                )
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
        }
    }
}

// MARK: - Preview

#Preview("Intent Pill — Prayer") {
    let svc = SmartComposerIntentService()
    let result = svc.classify(
        draftText: "Please pray for my healing, Lord Jesus",
        hasAttachment: false,
        accountType: "standard"
    )
    return VStack(spacing: 20) {
        IntentSuggestionPill(result: result, onApply: { _ in })
        IntentSuggestionPanel(
            result: result,
            onSuggestChurchNote: {},
            onSuggestPlaylist: {},
            onSuggestPulse: {}
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
