// SmartComposerIntentService.swift
// AMENAPP — MusicContentLayer
//
// Keyword-based post intent classifier + composer suggestion chips.
// PostIntentType, ContentAttachment, ContentAttachmentType live in MusicContentContracts.swift.

import SwiftUI

// MARK: - Composer Suggestion Chip

struct ComposerSuggestionChip: Codable, Sendable, Identifiable {
    let id: String
    let label: String
    let sfSymbol: String
    let action: ComposerChipAction
}

enum ComposerChipAction: String, Codable, Sendable {
    case makeChurchNote, attachWorshipPlaylist, addPrayerPrompt
    case addScripture, makePulseUpdate, setMembersOnly, addEventDetails
}

// MARK: - Classification Result

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

    private static let sensitiveTerms = [
        "suicide", "self-harm", "kill myself", "want to die",
        "abuse", "molest", "trafficking", "exploit"
    ]

    func analyzeIntent(draftText: String, attachments: [ContentAttachment],
                       accountType: String, communityContext: String?) async {
        isAnalyzing = true; defer { isAnalyzing = false }
        try? await Task.sleep(nanoseconds: 400_000_000)
        let hasMusicAttachment = attachments.contains { $0.type == .song || $0.type == .album }
        let result = classify(draftText: draftText, hasAttachment: hasMusicAttachment, accountType: accountType)
        detectedIntent = result.intent
        confidence = result.confidence
        suggestedChips = chips(for: result.intent)
        safetyFlags = Self.sensitiveTerms.filter { draftText.lowercased().contains($0) }
    }

    func classify(draftText: String, hasAttachment: Bool, accountType: String) -> IntentClassificationResult {
        let lower = draftText.lowercased()
        // 1. Scripture reference — highest signal
        if draftText.range(of: #"[A-Za-z]+\s+\d+:\d+"#, options: .regularExpression) != nil {
            return result(.scriptureQuote, 0.75, ["scripture", "bible"], churchNote: true, worship: false)
        }
        // 2. Song / worship release
        let songHits = ["listening to","on repeat","worship song","gospel"].filter { lower.contains($0) }.count
            + (["🎵","🎶","🎸","🎹"].contains(where: { draftText.contains($0) }) ? 1 : 0)
        if songHits >= 1 || hasAttachment {
            let total = songHits + (hasAttachment ? 2 : 0)
            let releaseHits = ["new","release","album","out now"].filter { lower.contains($0) }.count
            if accountType == "church" && releaseHits >= 1 {
                return result(.worshipRelease, min(0.5 + Double(releaseHits)*0.15, 1.0), ["worship","music","release"], churchNote: true, worship: true)
            }
            return result(.songShare, min(0.4 + Double(total)*0.12, 1.0), ["music","worship"], churchNote: false, worship: true)
        }
        // 3. Prayer
        let prayerHits = ["pray","prayer","lord","jesus"].filter { lower.contains($0) }.count
        if prayerHits >= 1 {
            let boost: Double = (draftText.contains("❤️") || draftText.contains("🙏")) ? 0.2 : 0.0
            return result(.prayerRequest, min(0.35 + Double(prayerHits)*0.12 + boost, 1.0), ["prayer","faith"], churchNote: true, worship: false)
        }
        // 4. Sermon
        let sermonHits = ["sermon","preached","pastor","church notes"].filter { lower.contains($0) }.count
        if sermonHits >= 1 { return result(.sermonNote, min(0.5 + Double(sermonHits)*0.15, 1.0), ["sermon","church"], churchNote: true, worship: false) }
        // 5. Testimony
        let testimonyHits = ["testified","testimony","god did"].filter { lower.contains($0) }.count
        if testimonyHits >= 1 { return result(.testimony, min(0.5 + Double(testimonyHits)*0.15, 1.0), ["testimony"], churchNote: false, worship: false) }
        // 6. Event
        let eventHits = ["join us","event","sunday","service at"].filter { lower.contains($0) }.count
        if eventHits >= 1 { return result(.eventAnnouncement, min(0.45 + Double(eventHits)*0.15, 1.0), ["event","church"], churchNote: false, worship: false) }
        // 7. Worship release (church)
        if accountType == "church" {
            let r = ["new","release","album","out now"].filter { lower.contains($0) }.count
            if r >= 1 { return result(.worshipRelease, min(0.45 + Double(r)*0.15, 1.0), ["worship","music"], churchNote: true, worship: true) }
        }
        return result(.communityDiscussion, 0.1, [], churchNote: false, worship: false)
    }

    private func result(_ intent: PostIntentType, _ conf: Double, _ tags: [String],
                        churchNote: Bool, worship: Bool) -> IntentClassificationResult {
        IntentClassificationResult(intent: intent, confidence: conf, suggestedTags: tags,
                                   shouldSuggestChurchNote: churchNote, shouldSuggestWorshipPlaylist: worship)
    }

    private func chips(for intent: PostIntentType) -> [ComposerSuggestionChip] {
        switch intent {
        case .prayerRequest:
            return [chip("ap","Add Prayer","hands.sparkles",.addPrayerPrompt),
                    chip("mo","Members Only","person.badge.shield.checkmark",.setMembersOnly)]
        case .sermonNote:
            return [chip("cn","Church Note","note.text",.makeChurchNote),
                    chip("wp","Add Playlist","music.note.list",.attachWorshipPlaylist),
                    chip("pu","Pulse Update","bolt.heart",.makePulseUpdate)]
        case .scriptureQuote:
            return [chip("as","Add Scripture","book.closed",.addScripture),
                    chip("cn2","Church Note","note.text",.makeChurchNote)]
        case .songShare:
            return [chip("wp2","Add Playlist","music.note.list",.attachWorshipPlaylist),
                    chip("pu2","Pulse Update","bolt.heart",.makePulseUpdate)]
        case .worshipRelease:
            return [chip("wp3","Add Playlist","music.note.list",.attachWorshipPlaylist),
                    chip("pu3","Pulse Update","bolt.heart",.makePulseUpdate),
                    chip("cn3","Church Note","note.text",.makeChurchNote)]
        default: return []
        }
    }

    private func chip(_ id: String, _ label: String, _ symbol: String, _ action: ComposerChipAction) -> ComposerSuggestionChip {
        ComposerSuggestionChip(id: id, label: label, sfSymbol: symbol, action: action)
    }
}

// MARK: - IntentSuggestionPill

struct IntentSuggestionPill: View {
    let intent: PostIntentType
    let confidence: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: intent.sfSymbol).font(.caption.weight(.semibold))
            Text(intent.displayName).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, 12).frame(minHeight: 36)
        .background {
            Capsule(style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay { Capsule(style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 0.5) }
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

    var body: some View {
        if !chips.isEmpty || confidence > 0.3 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    IntentSuggestionPill(intent: intent, confidence: confidence)
                    ForEach(chips) { chip in
                        Button { onChipTap(chip.action) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: chip.sfSymbol).font(.caption.weight(.semibold))
                                Text(chip.label).font(.caption.weight(.semibold)).lineLimit(1)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .amenLiquidGlassCapsuleSurface(isSelected: false)
                        }
                        .buttonStyle(.plain).accessibilityLabel(chip.label)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    SmartComposerSuggestionsBar(
        chips: [ComposerSuggestionChip(id: "cn", label: "Church Note", sfSymbol: "note.text", action: .makeChurchNote)],
        intent: .sermonNote, confidence: 0.82, onChipTap: { _ in }
    ).padding().background(Color(.systemGroupedBackground))
}
