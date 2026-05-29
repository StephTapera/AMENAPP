// AmenSpotlightService.swift
// AMENAPP
//
// CoreSpotlight integration for AMEN faith content.
// Indexes prayers, church notes, Berean conversations, and daily verses
// so they appear in iOS Spotlight search and can deep-link back into the app.
//
// WIRING REQUIRED in AMENAPPApp.swift:
// Handle onContinueUserActivity to route Spotlight results via
//   AmenSpotlightService.shared.handleSpotlightResult(_:)

import Foundation
import CoreSpotlight
import MobileCoreServices
import NaturalLanguage

@MainActor
final class AmenSpotlightService {

    // MARK: - Singleton

    static let shared = AmenSpotlightService()
    private init() {}

    // MARK: - Domain Identifiers

    static let domainPrayer        = "com.amen.prayer"
    static let domainChurchNote    = "com.amen.churchnote"
    static let domainBerean        = "com.amen.berean"
    static let domainVerse         = "com.amen.verse"

    // MARK: - Index Prayer

    /// Indexes a prayer entry in CoreSpotlight so users can search "prayer" on device.
    func indexPrayer(id: String, title: String, body: String, date: Date) async {
        let domain = AmenSpotlightService.domainPrayer
        let uniqueId = "\(domain).\(id)"

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = title.isEmpty ? "Prayer" : title
        attributeSet.contentDescription = String(body.prefix(300))
        attributeSet.keywords = buildKeywords(
            base: ["prayer", "amen", "faith", "intercession"],
            text: body
        )
        attributeSet.contentCreationDate = date

        let activity = NSUserActivity(activityType: "com.amen.view")
        activity.userInfo = ["type": domain, "id": id]
        activity.title = attributeSet.title
        attributeSet.relatedUniqueIdentifier = uniqueId

        let item = CSSearchableItem(
            uniqueIdentifier: uniqueId,
            domainIdentifier: domain,
            attributeSet: attributeSet
        )

        await index([item], context: "prayer(\(id))")
    }

    // MARK: - Index Church Note

    /// Indexes a church note so users can search sermon/note content from Spotlight.
    func indexChurchNote(id: String, title: String, content: String, date: Date) async {
        let domain = AmenSpotlightService.domainChurchNote
        let uniqueId = "\(domain).\(id)"

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = title.isEmpty ? "Church Notes" : title
        attributeSet.contentDescription = String(content.prefix(300))
        attributeSet.keywords = buildKeywords(
            base: ["church", "notes", "sermon", "amen", "faith"],
            text: content
        )
        attributeSet.contentCreationDate = date

        let activity = NSUserActivity(activityType: "com.amen.view")
        activity.userInfo = ["type": domain, "id": id]
        activity.title = attributeSet.title
        attributeSet.relatedUniqueIdentifier = uniqueId

        let item = CSSearchableItem(
            uniqueIdentifier: uniqueId,
            domainIdentifier: domain,
            attributeSet: attributeSet
        )

        await index([item], context: "churchNote(\(id))")
    }

    // MARK: - Index Berean Conversation

    /// Indexes a Berean AI session preview so users can resurface past scripture conversations.
    func indexBereanConversation(sessionId: String, preview: String, date: Date) async {
        let domain = AmenSpotlightService.domainBerean
        let uniqueId = "\(domain).\(sessionId)"

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = "Berean Study Session"
        attributeSet.contentDescription = String(preview.prefix(300))
        attributeSet.keywords = buildKeywords(
            base: ["berean", "scripture", "bible", "amen", "study", "ai"],
            text: preview
        )
        attributeSet.contentCreationDate = date

        let activity = NSUserActivity(activityType: "com.amen.view")
        activity.userInfo = ["type": domain, "id": sessionId]
        activity.title = attributeSet.title
        attributeSet.relatedUniqueIdentifier = uniqueId

        let item = CSSearchableItem(
            uniqueIdentifier: uniqueId,
            domainIdentifier: domain,
            attributeSet: attributeSet
        )

        await index([item], context: "berean(\(sessionId))")
    }

    // MARK: - Index Daily Verse

    /// Indexes the daily verse so users can search scripture references from Spotlight.
    func indexDailyVerse(reference: String, text: String, translation: String) async {
        let domain = AmenSpotlightService.domainVerse
        // Use a stable id derived from the reference so re-indexing the same verse is idempotent.
        let stableId = reference
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: "-")
        let uniqueId = "\(domain).\(stableId)"

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = "\(reference) (\(translation))"
        attributeSet.contentDescription = String(text.prefix(300))
        attributeSet.keywords = buildKeywords(
            base: ["verse", "scripture", "bible", "amen", "daily", translation, reference],
            text: text
        )
        attributeSet.contentCreationDate = Date()

        let activity = NSUserActivity(activityType: "com.amen.view")
        activity.userInfo = ["type": domain, "id": stableId]
        activity.title = attributeSet.title
        attributeSet.relatedUniqueIdentifier = uniqueId

        let item = CSSearchableItem(
            uniqueIdentifier: uniqueId,
            domainIdentifier: domain,
            attributeSet: attributeSet
        )

        await index([item], context: "verse(\(reference))")
    }

    // MARK: - Remove Item

    /// Removes a single Spotlight entry by its full unique identifier (domain + "." + id).
    func removeItem(identifier: String) async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier])
            dlog("[AmenSpotlight] Removed item: \(identifier)")
        } catch {
            dlog("[AmenSpotlight] Failed to remove item \(identifier): \(error.localizedDescription)")
        }
    }

    // MARK: - Clear Domain

    /// Removes all Spotlight entries belonging to the given domain identifier.
    func clearDomain(_ domain: String) async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
            dlog("[AmenSpotlight] Cleared domain: \(domain)")
        } catch {
            dlog("[AmenSpotlight] Failed to clear domain \(domain): \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Spotlight Deep Link

    /// Call from AppDelegate / onContinueUserActivity when the user taps a Spotlight result.
    /// Returns the content type and id needed for in-app routing, or nil if the activity
    /// is not an AMEN Spotlight result.
    ///
    /// Example wiring in AMENAPPApp:
    /// ```swift
    /// .onContinueUserActivity("com.amen.view") { activity in
    ///     if let result = AmenSpotlightService.shared.handleSpotlightResult(activity) {
    ///         AmenIntentRouter.routeSpotlight(type: result.type, id: result.id)
    ///     }
    /// }
    /// ```
    func handleSpotlightResult(_ activity: NSUserActivity) -> (type: String, id: String)? {
        // Route both direct NSUserActivity launches and CSSearchableItemActionType taps.
        if activity.activityType == CSSearchableItemActionType {
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
                dlog("[AmenSpotlight] CSSearchableItemActionType missing identifier")
                return nil
            }
            // identifier format: "com.amen.<domain>.<id>"
            return parseIdentifier(identifier)
        }

        if activity.activityType == "com.amen.view" {
            guard
                let type = activity.userInfo?["type"] as? String,
                let id   = activity.userInfo?["id"]   as? String
            else {
                dlog("[AmenSpotlight] com.amen.view activity missing type/id")
                return nil
            }
            dlog("[AmenSpotlight] Routing: type=\(type) id=\(id)")
            return (type: type, id: id)
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Writes items to the default CSSearchableIndex, logging any errors.
    private func index(_ items: [CSSearchableItem], context: String) async {
        do {
            try await CSSearchableIndex.default().indexSearchableItems(items)
            dlog("[AmenSpotlight] Indexed \(items.count) item(s) — \(context)")
        } catch {
            dlog("[AmenSpotlight] Index failed (\(context)): \(error.localizedDescription)")
        }
    }

    /// Parses a full unique identifier (e.g. "com.amen.prayer.abc123") into (type, id).
    private func parseIdentifier(_ identifier: String) -> (type: String, id: String)? {
        // Known prefixes in length-descending order to avoid partial matches.
        let prefixes: [(domain: String, prefix: String)] = [
            (AmenSpotlightService.domainChurchNote, "\(AmenSpotlightService.domainChurchNote)."),
            (AmenSpotlightService.domainBerean,     "\(AmenSpotlightService.domainBerean)."),
            (AmenSpotlightService.domainPrayer,     "\(AmenSpotlightService.domainPrayer)."),
            (AmenSpotlightService.domainVerse,      "\(AmenSpotlightService.domainVerse).")
        ]
        for entry in prefixes {
            if identifier.hasPrefix(entry.prefix) {
                let id = String(identifier.dropFirst(entry.prefix.count))
                dlog("[AmenSpotlight] Parsed: type=\(entry.domain) id=\(id)")
                return (type: entry.domain, id: id)
            }
        }
        dlog("[AmenSpotlight] Unrecognized Spotlight identifier: \(identifier)")
        return nil
    }

    /// Builds a de-duplicated keywords array from a base set plus NL-extracted nouns from text.
    private func buildKeywords(base: [String], text: String) -> [String] {
        var keywords = base

        // Use NaturalLanguage to extract meaningful words from the content.
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            guard let tag = tag,
                  tag == .noun || tag == .verb,
                  range.lowerBound != range.upperBound else { return true }
            let word = String(text[range]).lowercased()
            if word.count > 3 {
                keywords.append(word)
            }
            return keywords.count < 20 // Cap at 20 total keywords
        }

        // De-duplicate while preserving order.
        var seen = Set<String>()
        return keywords.filter { seen.insert($0).inserted }
    }
}
