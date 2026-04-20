// BereanContextResolver.swift
// AMENAPP
//
// Lightweight intelligence layer that determines what the Berean landing surface
// should show. Reads context (mode, last session, time of day, origin) and
// outputs smart UI content for BereanHomeView.
//
// Pure logic — no UI, no network calls, no async work.
// Everything resolves synchronously from local state.

import Foundation
import SwiftUI

// MARK: - Origin

/// Where the user came from before opening Berean.
enum BereanOrigin: Equatable {
    case home
    case verse(ref: String)
    case churchNotes(title: String?)
    case prayer
    case post(title: String?)
    case unknown
}

// MARK: - Intent Type

/// The likely task intent Berean inferred from context or early typing.
enum BereanIntentType: Equatable {
    case scripture
    case prayer
    case notes
    case context
    case reflection
    case general
}

// MARK: - Smart Chip

struct BereanSmartChip: Identifiable {
    let id: String          // stable: derived from text
    let text: String
    let icon: String
    let intentType: BereanIntentType

    init(text: String, icon: String, intentType: BereanIntentType) {
        self.id = text
        self.text = text
        self.icon = icon
        self.intentType = intentType
    }
}

extension BereanSmartChip: Equatable {
    static func == (lhs: BereanSmartChip, rhs: BereanSmartChip) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Resume Item

struct BereanResumeItem: Identifiable, Equatable {
    let id: String
    let label: String
    let sublabel: String?
    let sessionId: UUID?
}

// MARK: - BereanContextResolver

@MainActor
final class BereanContextResolver: ObservableObject {

    @Published private(set) var smartPrompt: String    = ""
    @Published private(set) var smartSubprompt: String = ""
    @Published private(set) var resumeItem: BereanResumeItem? = nil
    @Published private(set) var chips: [BereanSmartChip] = []
    @Published private(set) var composerPlaceholder: String = "Ask Berean"
    @Published private(set) var likelyIntentType: BereanIntentType = .general

    // Current context
    private var activeMode: BereanHomeMode = .ask
    private var origin: BereanOrigin = .home
    private var lastSession: BereanChatSession? = nil

    // MARK: - Resolve (call on appear + mode change)

    func resolve(
        mode: BereanHomeMode,
        origin: BereanOrigin = .home,
        lastSession: BereanChatSession? = nil
    ) {
        self.activeMode  = mode
        self.origin      = origin
        self.lastSession = lastSession

        updatePrompt()
        updateResumeItem()
        updateChips()
        updatePlaceholder()
    }

    // MARK: - Update from composer input (call on every keystroke)

    func updateFromInput(_ text: String) {
        guard !text.isEmpty else {
            updateChips()
            updatePlaceholder()
            return
        }

        let lower = text.lowercased()

        if looksLikeScriptureRef(lower) {
            likelyIntentType = .scripture
            setChips(scriptureChips())
            composerPlaceholder = "Explain or explore this passage"
        } else if lower.hasPrefix("pray") || lower.contains("prayer") {
            likelyIntentType = .prayer
            setChips(prayerChips())
            composerPlaceholder = "What do you want prayer help with?"
        } else if lower.contains("summarize") || lower.contains("notes") || lower.contains("sermon") {
            likelyIntentType = .notes
            setChips(notesChips())
            composerPlaceholder = "Summarize, clarify, or organize"
        } else if lower.contains("what does") || lower.contains("explain") || lower.contains("mean") {
            likelyIntentType = .context
            setChips(contextChips())
            composerPlaceholder = "Ask for explanation or context"
        } else if lower.contains("reflect") || lower.contains("struggling") || lower.contains("feel") {
            likelyIntentType = .reflection
            setChips(reflectionChips())
            composerPlaceholder = "Reflect, process, or find peace"
        }
    }

    // MARK: - Private: Prompt

    private func updatePrompt() {
        let hour = Calendar.current.component(.hour, from: Date())

        switch origin {
        case .verse(let ref):
            smartPrompt    = "What do you want to understand about \(ref)?"
            smartSubprompt = "Explain, explore context, or cross-reference."

        case .churchNotes(let title):
            let t = title ?? "your notes"
            smartPrompt    = "Want to turn \(t) into something clearer?"
            smartSubprompt = "Summarize, extract themes, or build a prayer."

        case .prayer:
            smartPrompt    = "What do you want prayer help with today?"
            smartSubprompt = "A prayer, reflection, or encouragement."

        case .post(let title):
            let t = title ?? "this post"
            smartPrompt    = "Want Berean to help you respond to \(t)?"
            smartSubprompt = "Ask for context, reflection, or a scripture angle."

        default:
            switch activeMode {
            case .study:
                switch hour {
                case 0..<12:
                    smartPrompt    = "What Scripture would you like to begin with?"
                    smartSubprompt = "Explore a passage, word study, or commentary."
                case 12..<17:
                    smartPrompt    = "What would you like to study or understand?"
                    smartSubprompt = "Ask about a passage, theme, or doctrine."
                default:
                    smartPrompt    = "Want to close the day with Scripture?"
                    smartSubprompt = "Explore, reflect, or read with context."
                }

            case .pray:
                if hour < 12 {
                    smartPrompt    = "Start your morning in prayer?"
                    smartSubprompt = "Write a prayer, reflect on Scripture, or find calm."
                } else {
                    smartPrompt    = "What do you want to bring to prayer today?"
                    smartSubprompt = "A concern, a scripture, or a quiet moment."
                }

            case .reflect:
                if hour >= 17 {
                    smartPrompt    = "Want to reflect, pray, or process today?"
                    smartSubprompt = "Berean will hold space without rushing."
                } else {
                    smartPrompt    = "What's on your heart or mind right now?"
                    smartSubprompt = "A question, a burden, or something to process."
                }

            case .explore:
                smartPrompt    = "What would you like to explore in Scripture?"
                smartSubprompt = "Historical context, themes, cross-references, or background."

            default:
                switch hour {
                case 0..<12:
                    smartPrompt    = "What would you like to begin with today?"
                    smartSubprompt = "Ask Berean about Scripture, prayer, or context."
                case 12..<17:
                    smartPrompt    = "What do you want help understanding?"
                    smartSubprompt = "Bring a passage, a question, or a hard decision."
                default:
                    smartPrompt    = "Want to reflect, pray, or process today?"
                    smartSubprompt = "Berean is here — ask anything."
                }
            }
        }
    }

    // MARK: - Private: Resume

    private func updateResumeItem() {
        guard let session = lastSession else { resumeItem = nil; return }

        let age = Date().timeIntervalSince(session.lastUpdatedAt)
        // Only surface if session is < 4 hours old and has messages
        guard age < 4 * 3600, !session.messages.isEmpty else { resumeItem = nil; return }

        let label: String
        if session.title.isEmpty || session.title.hasPrefix("Chat —") {
            if let lastUser = session.lastUserMessage?.content, !lastUser.isEmpty {
                let preview = String(lastUser.prefix(40))
                let ellipsis = lastUser.count > 40 ? "…" : ""
                label = "Resume: \"\(preview)\(ellipsis)\""
            } else {
                label = "Resume your last conversation"
            }
        } else {
            label = "Resume \(session.title)"
        }

        resumeItem = BereanResumeItem(
            id: session.id.uuidString,
            label: label,
            sublabel: session.relativeTimestamp,
            sessionId: session.id
        )
    }

    // MARK: - Private: Chips

    private func updateChips() {
        switch origin {
        case .verse:       setChips(scriptureChips()); likelyIntentType = .scripture
        case .churchNotes: setChips(notesChips());     likelyIntentType = .notes
        case .prayer:      setChips(prayerChips());    likelyIntentType = .prayer
        default:
            switch activeMode {
            case .study:   setChips(scriptureChips());  likelyIntentType = .scripture
            case .pray:    setChips(prayerChips());     likelyIntentType = .prayer
            case .reflect: setChips(reflectionChips()); likelyIntentType = .reflection
            case .explore: setChips(contextChips());    likelyIntentType = .context
            default:       setChips(generalChips());    likelyIntentType = .general
            }
        }
    }

    private func updatePlaceholder() {
        switch likelyIntentType {
        case .scripture:  composerPlaceholder = "Ask about a verse or passage"
        case .prayer:     composerPlaceholder = "What do you want to pray about?"
        case .notes:      composerPlaceholder = "Paste notes or describe your sermon"
        case .context:    composerPlaceholder = "Ask for explanation or background"
        case .reflection: composerPlaceholder = "What's on your heart right now?"
        case .general:    composerPlaceholder = "Ask Berean about Scripture, prayer, or context"
        }
    }

    private func setChips(_ newChips: [BereanSmartChip]) {
        guard chips != newChips else { return }
        chips = newChips
    }

    // MARK: - Chip Sets

    private func scriptureChips() -> [BereanSmartChip] {[
        BereanSmartChip(text: "Explain Simply",       icon: "text.quote",             intentType: .scripture),
        BereanSmartChip(text: "Explore Context",      icon: "globe",                  intentType: .context),
        BereanSmartChip(text: "Cross-reference",      icon: "link",                   intentType: .scripture),
        BereanSmartChip(text: "Search Scripture",     icon: "magnifyingglass",        intentType: .scripture),
    ]}

    private func prayerChips() -> [BereanSmartChip] {[
        BereanSmartChip(text: "Build a Prayer",       icon: "hands.sparkles",         intentType: .prayer),
        BereanSmartChip(text: "Pray with Scripture",  icon: "book.pages",             intentType: .prayer),
        BereanSmartChip(text: "Calm My Thoughts",     icon: "wind",                   intentType: .reflection),
        BereanSmartChip(text: "Reflect Gently",       icon: "sparkles",               intentType: .reflection),
    ]}

    private func notesChips() -> [BereanSmartChip] {[
        BereanSmartChip(text: "Summarize Notes",      icon: "doc.text",               intentType: .notes),
        BereanSmartChip(text: "Extract Themes",       icon: "list.bullet",            intentType: .notes),
        BereanSmartChip(text: "Build a Prayer",       icon: "hands.sparkles",         intentType: .prayer),
        BereanSmartChip(text: "Turn into Post",       icon: "square.and.pencil",      intentType: .notes),
    ]}

    private func contextChips() -> [BereanSmartChip] {[
        BereanSmartChip(text: "Explore Context",      icon: "globe",                  intentType: .context),
        BereanSmartChip(text: "Compare Translations", icon: "arrow.left.arrow.right", intentType: .scripture),
        BereanSmartChip(text: "Clarify Meaning",      icon: "questionmark.circle",    intentType: .context),
        BereanSmartChip(text: "Cross-reference",      icon: "link",                   intentType: .scripture),
    ]}

    private func reflectionChips() -> [BereanSmartChip] {[
        BereanSmartChip(text: "Reflect Gently",       icon: "sparkles",               intentType: .reflection),
        BereanSmartChip(text: "Calm My Thoughts",     icon: "wind",                   intentType: .reflection),
        BereanSmartChip(text: "Build a Prayer",       icon: "hands.sparkles",         intentType: .prayer),
        BereanSmartChip(text: "Find a Verse",         icon: "book",                   intentType: .scripture),
    ]}

    private func generalChips() -> [BereanSmartChip] {[
        BereanSmartChip(text: "Search Scripture",     icon: "magnifyingglass",        intentType: .scripture),
        BereanSmartChip(text: "Explain Simply",       icon: "text.quote",             intentType: .scripture),
        BereanSmartChip(text: "Build a Prayer",       icon: "hands.sparkles",         intentType: .prayer),
        BereanSmartChip(text: "Explore Context",      icon: "globe",                  intentType: .context),
    ]}

    // MARK: - Helpers

    private func looksLikeScriptureRef(_ text: String) -> Bool {
        let books = ["genesis","exodus","leviticus","numbers","deuteronomy","joshua",
                     "judges","ruth","samuel","kings","chronicles","ezra","nehemiah",
                     "esther","job","psalm","psalms","proverbs","ecclesiastes","song",
                     "isaiah","jeremiah","lamentations","ezekiel","daniel","hosea",
                     "joel","amos","obadiah","jonah","micah","nahum","habakkuk",
                     "zephaniah","haggai","zechariah","malachi","matthew","mark",
                     "luke","john","acts","romans","corinthians","galatians",
                     "ephesians","philippians","colossians","thessalonians","timothy",
                     "titus","philemon","hebrews","james","peter","jude","revelation",
                     "gen","exo","lev","num","deut","josh","judg","psa","prov",
                     "eccl","isa","jer","ezek","dan","mal","matt","rom","cor",
                     "gal","eph","phil","col","thess","tim","heb","jas","pet","rev"]
        return books.contains(where: { text.hasPrefix($0) })
    }
}
