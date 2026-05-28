import EventKit
import SwiftUI
import UIKit

struct SmartMessageHostContext: Hashable {
    var spaceId: String?
    var threadId: String?
    var messageId: String
    var sourceSurface: String

    static func local(messageId: String, surface: String) -> SmartMessageHostContext {
        SmartMessageHostContext(spaceId: nil, threadId: nil, messageId: messageId, sourceSurface: surface)
    }
}

struct SmartMessageText: View {
    let text: String
    let context: SmartMessageHostContext
    var foregroundColor: Color = .primary

    @State private var activePrayerText: String?
    @State private var activeStudySession: SmartStudySession?
    @State private var activeSearchQuery: String?
    @State private var activeKnowledgeNode: SmartKnowledgeNode?
    @State private var activeScriptureReference: SmartScriptureSheetItem?
    @State private var alertMessage: String?
    @State private var copiedMessage = false
    @State private var isStartingStudy = false

    private var entities: [SmartDetectedEntity] {
        SmartMessageLocalDetector.detect(in: text)
    }

    private var actions: [SmartMessageAction] {
        var seen = Set<String>()
        return entities
            .flatMap { SmartMessageLocalDetector.actions(for: $0, context: context) }
            .filter { action in
                let key = "\(action.title)|\(action.subtitle)"
                return seen.insert(key).inserted
            }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if AMENFeatureFlags.shared.smartMessageIntelligenceEnabled {
                SmartMessageEntityHighlighter(text: text, entities: entities) { entity in
                    handle(entity: entity)
                }
                .foregroundStyle(foregroundColor)
                .contextMenu { contextualMenu }
            } else {
                Text(text)
                    .foregroundStyle(foregroundColor)
                    .textSelection(.enabled)
            }

            if AMENFeatureFlags.shared.smartMessageIntelligenceEnabled && !actions.isEmpty {
                SmartMessageActionMenu(
                    actions: actions,
                    onOpenScripture: openScripture,
                    onPrayerRequest: { action in activePrayerText = action.payload["extractedText"] ?? text },
                    onStudyMode: { action in Task { await startStudy(seed: action.payload["scriptureReference"] ?? action.payload["topic"] ?? text) } },
                    onSearchRelated: { query in activeSearchQuery = query.isEmpty ? text : query }
                )
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .accessibilityLabel("Smart message actions")
            }
        }
        .sheet(item: Binding(get: { prayerSheetBinding }, set: { _ in activePrayerText = nil })) { item in
            if let spaceId = context.spaceId, let threadId = context.threadId {
                NavigationStack {
                    PrayerRequestFromMessageView(
                        spaceId: spaceId,
                        threadId: threadId,
                        messageId: context.messageId,
                        extractedText: item.text
                    )
                }
            } else {
                SmartPrayerActionSheet(
                    extractedText: item.text,
                    onSave: { _ in alertMessage = "Prayer requests from private messages require a Space or selected-person flow." },
                    onPrayNow: { askBerean(action: .prayAboutThis, selectedText: item.text) },
                    onReminder: { requestReminder(for: item.text) },
                    onEncourage: { shareText(item.text) },
                    onPraiseReport: { askBerean(action: .turnIntoPrayer, selectedText: item.text) }
                )
            }
        }
        .sheet(item: $activeStudySession) { session in
            NavigationStack {
                SmartStudyModeView(
                    session: session,
                    relatedMessages: [text],
                    prayerRequests: entities.filter { $0.type == .prayerRequest }.map(\.sourceText),
                    onAskBerean: { askBerean(action: .askBerean, selectedText: $0) },
                    onSave: { alertMessage = "Study session saved." },
                    onShare: { shareText(session.title) },
                    onExport: { shareText(session.title) }
                )
            }
        }
        .sheet(item: Binding(get: { searchSheetBinding }, set: { _ in activeSearchQuery = nil })) { item in
            if let spaceId = context.spaceId {
                NavigationStack { AmenSpaceSemanticSearchView(spaceId: spaceId, initialQuery: item.text) }
            } else {
                NavigationStack { LocalSmartSearchFallbackView(query: item.text, text: text) }
            }
        }
        .sheet(item: $activeScriptureReference) { item in
            NavigationStack {
                SelahScriptureReaderView(
                    initialReference: item.reference,
                    provider: SelahCompositeBibleProvider(),
                    preferencesStore: SelahScriptureReaderPreferencesStore()
                )
            }
        }
        .sheet(item: $activeKnowledgeNode) { node in
            NavigationStack {
                AmenKnowledgeGraphView(
                    personalNodes: [node],
                    spaceNodes: [],
                    onAskBerean: { askBerean(action: .askBerean, selectedText: $0.summary) },
                    onSearchRelated: { activeSearchQuery = $0.title }
                )
            }
        }
        .alert("Smart Message", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage ?? "") }
    }

    @ViewBuilder
    private var contextualMenu: some View {
        if AMENFeatureFlags.shared.contextualBereanActionsEnabled {
            Button("Explain with Berean", systemImage: "text.bubble") { askBerean(action: .explain, selectedText: text) }
            Button("Find Scripture", systemImage: "books.vertical") { askBerean(action: .searchRelatedVerses, selectedText: text) }
            Button("Compare Context", systemImage: "rectangle.split.2x1") { askBerean(action: .compareScripture, selectedText: text) }
            Button("Create Reflection", systemImage: "square.and.pencil") { askBerean(action: .reflect, selectedText: text) }
            Button("Save to Notes", systemImage: "note.text") { askBerean(action: .saveToChurchNotes, selectedText: text) }
            Button("Pray Through This", systemImage: "hands.sparkles") { askBerean(action: .prayAboutThis, selectedText: text) }
        }
    }

    private func handle(entity: SmartDetectedEntity) {
        switch entity.type {
        case .scriptureReference:
            openScripture(entity.normalizedValue)
        case .dateTime, .event:
            requestCalendar(for: entity.sourceText)
        case .prayerRequest:
            activePrayerText = entity.sourceText
        case .topic, .question, .actionItem:
            activeSearchQuery = entity.normalizedValue
        default:
            askBerean(action: .askBerean, selectedText: entity.sourceText)
        }
    }

    private func openScripture(_ reference: String) {
        let normalized = reference
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        guard let parsed = SelahScriptureReferenceParser.parse(normalized) else {
            alertMessage = "Amen could not open \(reference). Try Ask Berean or search Scripture."
            return
        }
        activeScriptureReference = SmartScriptureSheetItem(reference: parsed)
    }

    private func askBerean(action: BereanContextAction, selectedText: String) {
        let payload = BereanContextPayload(
            selectedText: selectedText,
            surroundingText: text,
            sourceSurface: context.sourceSurface,
            sourceId: context.messageId,
            contentType: .message,
            scriptureReference: SmartMessageLocalDetector.detect(in: selectedText).first(where: { $0.type == .scriptureReference })?.normalizedValue,
            metadata: ["messageId": context.messageId]
        )
        BereanContextMenuManager.shared.activate(payload: payload, action: action)
    }

    private func startStudy(seed: String) async {
        guard let spaceId = context.spaceId, let threadId = context.threadId else {
            alertMessage = "Study Mode requires a Space thread."
            return
        }
        isStartingStudy = true
        defer { isStartingStudy = false }
        do {
            activeStudySession = try await AmenSmartMessageIntelligenceService.shared.startStudyMode(
                spaceId: spaceId,
                threadId: threadId,
                seedMessageIds: [context.messageId],
                title: seed
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func requestCalendar(for phrase: String) {
        Task {
            do {
                let granted = try await EKEventStore().requestWriteOnlyAccessToEvents()
                guard granted else {
                    alertMessage = "Calendar access was denied. You can enable calendar access in Settings."
                    return
                }
                UIPasteboard.general.string = phrase
                alertMessage = "Calendar access granted. Event text copied for review before saving."
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func requestReminder(for phrase: String) {
        Task {
            do {
                let granted = try await EKEventStore().requestFullAccessToReminders()
                guard granted else {
                    alertMessage = "Reminder access was denied. You can enable reminder access in Settings."
                    return
                }
                UIPasteboard.general.string = phrase
                alertMessage = "Reminder access granted. Reminder text copied for review before saving."
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func shareText(_ value: String) {
        UIPasteboard.general.string = value
        alertMessage = "Copied for sharing."
    }

    private var prayerSheetBinding: SmartMessageTextSheetItem? {
        activePrayerText.map { SmartMessageTextSheetItem(text: $0) }
    }

    private var searchSheetBinding: SmartMessageTextSheetItem? {
        activeSearchQuery.map { SmartMessageTextSheetItem(text: $0) }
    }
}

private struct SmartMessageTextSheetItem: Identifiable {
    let id = UUID()
    let text: String
}

private struct SmartScriptureSheetItem: Identifiable {
    var id: String { reference.displayString }
    let reference: SelahScriptureReference
}

struct LocalSmartSearchFallbackView: View {
    let query: String
    let text: String

    var body: some View {
        List {
            Section("Keyword Fallback") {
                Text("Vector search is not active for this surface. Showing local keyword context.")
                    .foregroundStyle(.secondary)
                Text(query)
                    .font(.headline)
                Text(text)
                    .font(.body)
            }
        }
        .navigationTitle("Search Related")
    }
}

enum SmartMessageLocalDetector {
    private static let cacheLock = NSLock()
    private static var detectionCache: [String: [SmartDetectedEntity]] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheLimit = 400
    private static let maxDetectionLength = 8_000

    static func detect(in text: String, respectFeatureFlags: Bool = true) -> [SmartDetectedEntity] {
        let flags = AMENFeatureFlags.shared
        guard !respectFeatureFlags || flags.smartMessageIntelligenceEnabled else { return [] }
        let searchableText = String(text.prefix(maxDetectionLength))
        let cacheKey = detectionCacheKey(for: searchableText, flags: flags, respectFeatureFlags: respectFeatureFlags)
        if let cached = cachedEntities(for: cacheKey) {
            return cached
        }

        var results: [SmartDetectedEntity] = []
        if !respectFeatureFlags || flags.scriptureDetectionEnabled {
            results.append(contentsOf: scriptures(in: searchableText))
        }
        if !respectFeatureFlags || flags.smartEventDetectionEnabled {
            results.append(contentsOf: matches(in: searchableText, pattern: #"\b(today|tomorrow|tonight|sunday|monday|tuesday|wednesday|thursday|friday|saturday|at\s+\d{1,2}(:\d{2})?\s*(am|pm))\b"#, type: .dateTime, normalized: { $0.lowercased() }))
        }
        if !respectFeatureFlags || flags.prayerIntelligenceEnabled {
            results.append(contentsOf: matches(in: searchableText, pattern: #"\b(please pray|pray for|need prayer|urgent prayer|praise report)[^.!?]*"#, type: .prayerRequest, normalized: { _ in "general prayer" }))
        }
        if !respectFeatureFlags || flags.topicExtractionEnabled {
            results.append(contentsOf: topics(in: searchableText))
            results.append(contentsOf: matches(in: searchableText, pattern: #"[^.!?]*\?"#, type: .question, normalized: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
        }
        store(results, for: cacheKey)
        return results
    }

    static func actions(for entity: SmartDetectedEntity, context: SmartMessageHostContext) -> [SmartMessageAction] {
        switch entity.type {
        case .scriptureReference:
            return actionSet(entity, [
                ("Open Scripture", "book", SmartMessageActionType.openScripture),
                ("Ask Berean", "sparkles", .askBerean),
                ("Add to Study", "book.closed", .startStudyMode),
                ("Save to Church Notes", "note.text", .saveToJournal)
            ], context: context)
        case .dateTime, .event:
            return actionSet(entity, [
                ("Add to Calendar", "calendar.badge.plus", .addToCalendar),
                ("Add Reminder", "bell.badge", .addReminder),
                ("Copy Event", "doc.on.doc", .addReminder),
                ("Share With Space", "square.and.arrow.up", .searchRelated)
            ], context: context)
        case .prayerRequest:
            return actionSet(entity, [
                ("Pray Now", "heart.text.square", .prayNow),
                ("Add to Prayer List", "hands.sparkles", .createPrayerRequest),
                ("Set Reminder", "bell", .addReminder),
                ("Send Encouragement", "paperplane", .askBerean)
            ], context: context)
        case .topic, .question, .actionItem:
            return actionSet(entity, [
                ("Search Related", "magnifyingglass", .searchRelated),
                ("Start Study", "book.closed", .startStudyMode),
                ("Follow Topic", "tag", .createTopic),
                ("Open Knowledge Graph", "circle.hexagongrid", .openKnowledgeGraph)
            ], context: context)
        default:
            return []
        }
    }

    private static func actionSet(_ entity: SmartDetectedEntity, _ items: [(String, String, SmartMessageActionType)], context: SmartMessageHostContext) -> [SmartMessageAction] {
        items.map { title, icon, type in
            SmartMessageAction(
                id: "\(entity.id)-\(type.rawValue)-\(context.messageId)",
                title: title,
                subtitle: entity.sourceText,
                iconSystemName: icon,
                actionType: type,
                payload: [
                    "sourceText": entity.sourceText,
                    "scriptureReference": entity.normalizedValue,
                    "topic": entity.normalizedValue,
                    "query": entity.normalizedValue,
                    "extractedText": entity.sourceText
                ],
                requiresConfirmation: [.addToCalendar, .addReminder, .createPrayerRequest, .startStudyMode, .saveToJournal].contains(type),
                privacyLevel: .private
            )
        }
    }

    private static func scriptures(in text: String) -> [SmartDetectedEntity] {
        matches(in: text, pattern: #"\b([1-3]\s*)?(John|Romans|Psalm|Psalms|Genesis|Exodus|Matthew|Mark|Luke|Acts|Corinthians|Galatians|Ephesians|Philippians|Colossians|Thessalonians|Timothy|Hebrews|James|Peter|Jude|Revelation)\s+\d{1,3}(:\d{1,3}([-–]\d{1,3})?)?\b"#, type: .scriptureReference) { $0.replacingOccurrences(of: "Psalms ", with: "Psalm ") }
    }

    private static func topics(in text: String) -> [SmartDetectedEntity] {
        let topics = ["grace", "anxiety", "forgiveness", "prayer", "fasting", "marriage", "discipleship", "leadership", "suffering", "worship"]
        return topics.flatMap { topic in
            matches(in: text, pattern: "\\b\(topic)\\b", type: .topic) { _ in topic }
        }
    }

    private static func matches(in text: String, pattern: String, type: SmartDetectedEntityType, normalized: (String) -> String) -> [SmartDetectedEntity] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let source = String(text[range])
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            return SmartDetectedEntity(
                id: "local-\(type.rawValue)-\(start)-\(source.hashValue)",
                type: type,
                sourceText: source,
                normalizedValue: normalized(source),
                confidence: 0.72,
                range: SmartTextRange(start: start, length: length),
                createdAt: Date()
            )
        }
    }

    private static func detectionCacheKey(for text: String, flags: AMENFeatureFlags, respectFeatureFlags: Bool) -> String {
        [
            String(text.hashValue),
            String(text.count),
            respectFeatureFlags ? String(flags.scriptureDetectionEnabled) : "scripture-test",
            respectFeatureFlags ? String(flags.smartEventDetectionEnabled) : "event-test",
            respectFeatureFlags ? String(flags.prayerIntelligenceEnabled) : "prayer-test",
            respectFeatureFlags ? String(flags.topicExtractionEnabled) : "topic-test"
        ].joined(separator: "|")
    }

    private static func cachedEntities(for key: String) -> [SmartDetectedEntity]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return detectionCache[key]
    }

    private static func store(_ entities: [SmartDetectedEntity], for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if detectionCache[key] == nil {
            cacheOrder.append(key)
        }
        detectionCache[key] = entities
        while cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            detectionCache.removeValue(forKey: evicted)
        }
    }
}
