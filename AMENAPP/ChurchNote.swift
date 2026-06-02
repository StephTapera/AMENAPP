//
//  ChurchNote.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Church Note Model with Firebase integration
//

import Foundation
import FirebaseFirestore

// MARK: - Note Formatting Range

/// Represents a rich text formatting span within note content.
struct NoteFormattingRange: Codable, Identifiable, Hashable {
    var id: String
    var start: Int
    var length: Int
    var style: NoteTextStyle

    init(start: Int, length: Int, style: NoteTextStyle) {
        self.id = UUID().uuidString
        self.start = start
        self.length = length
        self.style = style
    }
}

enum NoteTextStyle: String, Codable, Hashable, CaseIterable {
    case bold
    case italic
    case highlight
    case redAccent
    case scribble
    case heading

    var displayName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .highlight: return "Highlight"
        case .redAccent: return "Accent"
        case .scribble: return "Scribble"
        case .heading: return "Heading"
        }
    }

    var icon: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .highlight: return "highlighter"
        case .redAccent: return "paintbrush.pointed"
        case .scribble: return "scribble.variable"
        case .heading: return "textformat.size"
        }
    }
}

// MARK: - Note Semantic Block

/// Semantic blocks that can be inserted into notes.
enum NoteSemanticBlock: String, CaseIterable {
    case takeaway
    case prayer
    case actionStep
    case pastorQuote
    case reflection
    case scripture

    var displayName: String {
        switch self {
        case .takeaway: return "Takeaway"
        case .prayer: return "Prayer"
        case .actionStep: return "Action"
        case .pastorQuote: return "Quote"
        case .reflection: return "Reflection"
        case .scripture: return "Scripture"
        }
    }

    var icon: String {
        switch self {
        case .takeaway: return "lightbulb.fill"
        case .prayer: return "hands.sparkles.fill"
        case .actionStep: return "checkmark.circle.fill"
        case .pastorQuote: return "quote.opening"
        case .reflection: return "heart.text.clipboard.fill"
        case .scripture: return "book.fill"
        }
    }

    var prefix: String {
        switch self {
        case .takeaway: return "\n\n💡 Key Takeaway: "
        case .prayer: return "\n\n🙏 Prayer: "
        case .actionStep: return "\n\n✅ Action Step: "
        case .pastorQuote: return "\n\n💬 Pastor Quote: "
        case .reflection: return "\n\n✨ Reflection: "
        case .scripture: return "\n\n📖 Scripture: "
        }
    }
}

// MARK: - Scripture Theme Suggestion

/// Maps common sermon themes to suggested scripture references.
struct ScriptureThemeSuggestion {
    let theme: String
    let reference: String
    let shortText: String

    static let suggestions: [ScriptureThemeSuggestion] = [
        .init(theme: "grace", reference: "Ephesians 2:8", shortText: "For by grace you have been saved through faith"),
        .init(theme: "faith", reference: "Hebrews 11:1", shortText: "Faith is the substance of things hoped for"),
        .init(theme: "anxiety", reference: "Philippians 4:6", shortText: "Do not be anxious about anything"),
        .init(theme: "worry", reference: "Philippians 4:6", shortText: "Do not be anxious about anything"),
        .init(theme: "waiting", reference: "Isaiah 40:31", shortText: "They who wait for the Lord shall renew their strength"),
        .init(theme: "love", reference: "1 Corinthians 13:4", shortText: "Love is patient, love is kind"),
        .init(theme: "strength", reference: "Philippians 4:13", shortText: "I can do all things through Christ"),
        .init(theme: "fear", reference: "Isaiah 41:10", shortText: "Fear not, for I am with you"),
        .init(theme: "peace", reference: "John 14:27", shortText: "Peace I leave with you; my peace I give you"),
        .init(theme: "forgiveness", reference: "Colossians 3:13", shortText: "Forgive as the Lord forgave you"),
        .init(theme: "hope", reference: "Romans 15:13", shortText: "May the God of hope fill you with all joy"),
        .init(theme: "trust", reference: "Proverbs 3:5", shortText: "Trust in the Lord with all your heart"),
        .init(theme: "purpose", reference: "Jeremiah 29:11", shortText: "For I know the plans I have for you"),
        .init(theme: "joy", reference: "Nehemiah 8:10", shortText: "The joy of the Lord is your strength"),
        .init(theme: "wisdom", reference: "James 1:5", shortText: "If any of you lacks wisdom, let him ask God"),
        .init(theme: "comfort", reference: "2 Corinthians 1:3-4", shortText: "The God of all comfort"),
        .init(theme: "perseverance", reference: "James 1:12", shortText: "Blessed is the one who perseveres under trial"),
        .init(theme: "healing", reference: "Psalm 147:3", shortText: "He heals the brokenhearted"),
        .init(theme: "provision", reference: "Matthew 6:33", shortText: "Seek first his kingdom"),
        .init(theme: "identity", reference: "2 Corinthians 5:17", shortText: "If anyone is in Christ, the new creation has come"),
    ]

    /// Find suggestions matching keywords in the given text.
    static func suggest(for text: String, limit: Int = 3) -> [ScriptureThemeSuggestion] {
        let lower = text.lowercased()
        return suggestions
            .filter { lower.contains($0.theme) }
            .prefix(limit)
            .map { $0 }
    }
}

enum MusicProvider: String, Codable, CaseIterable, Hashable {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

enum MusicEntityType: String, Codable, CaseIterable, Hashable {
    case song
    case album
    case playlist
    case artist
}

enum MusicAttachmentAvailabilityState: String, Hashable {
    case readyToOpen
    case viewOnly
    case accountRequired
    case unavailable

    var helperText: String {
        switch self {
        case .readyToOpen: return "Open in app"
        case .viewOnly: return "View link"
        case .accountRequired: return "Account may be required"
        case .unavailable: return "Track unavailable"
        }
    }
}

/// A normalized worship music attachment saved inside a Church Note.
/// Backward-compatible with older Apple Music / Spotify fields already stored in Firestore.
struct WorshipSongReference: Codable, Identifiable, Hashable {
    var id: String
    var provider: MusicProvider
    var entityType: MusicEntityType
    var providerID: String
    var title: String
    var artist: String
    var subtitle: String?
    var storefront: String?
    var musicKitID: String?
    var deepLinkURL: String?
    var webURL: String?
    var canonicalURL: String?
    var appURL: String?
    var artworkURL: String?
    var artworkColors: MusicArtworkColors?
    var previewURL: String?
    var explicit: Bool?
    var durationMs: Int?
    var mayRequireSubscription: Bool?
    var requiresSubscription: Bool?
    var requiresAppInstall: Bool?
    var metadataVersion: Int?
    var addedAt: Date
    var resolvedAt: Date?

    var albumArtURL: String? { artworkURL }
    var appleMusicURL: String? { provider == .appleMusic ? webURL : nil }
    var spotifyTrackID: String? { provider == .spotify ? providerID : nil }
    var spotifyTrackURL: String? { provider == .spotify ? deepLinkURL : nil }

    var availabilityState: MusicAttachmentAvailabilityState {
        if deepLinkURL == nil && webURL == nil {
            return .unavailable
        }
        if requiresSubscription == true || requiresAppInstall == true {
            return .accountRequired
        }
        if deepLinkURL == nil {
            return .viewOnly
        }
        return .readyToOpen
    }

    var providerBadgeText: String { provider.displayName }

    init(
        id: String = UUID().uuidString,
        provider: MusicProvider? = nil,
        entityType: MusicEntityType = .song,
        providerID: String? = nil,
        title: String,
        artist: String,
        subtitle: String? = nil,
        storefront: String? = nil,
        musicKitID: String? = nil,
        appleMusicURL: String? = nil,
        albumArtURL: String? = nil,
        artworkColors: MusicArtworkColors? = nil,
        spotifyTrackID: String? = nil,
        spotifyTrackURL: String? = nil,
        deepLinkURL: String? = nil,
        webURL: String? = nil,
        canonicalURL: String? = nil,
        appURL: String? = nil,
        previewURL: String? = nil,
        explicit: Bool? = nil,
        durationMs: Int? = nil,
        requiresAccount: Bool? = nil,
        mayRequireSubscription: Bool? = nil,
        requiresSubscription: Bool? = nil,
        requiresAppInstall: Bool? = nil,
        metadataVersion: Int? = nil,
        addedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        let resolvedProvider = provider
            ?? (spotifyTrackID != nil || spotifyTrackURL != nil ? .spotify : .appleMusic)
        let resolvedProviderID = providerID
            ?? spotifyTrackID
            ?? musicKitID
            ?? UUID().uuidString

        self.id = id
        self.provider = resolvedProvider
        self.entityType = entityType
        self.providerID = resolvedProviderID
        self.title = title
        self.artist = artist
        self.subtitle = subtitle
        self.storefront = storefront
        self.musicKitID = musicKitID
        self.deepLinkURL = deepLinkURL ?? appURL ?? spotifyTrackURL ?? appleMusicURL
        self.webURL = webURL ?? canonicalURL ?? appleMusicURL ?? Self.spotifyTrackWebURL(from: spotifyTrackID)
        self.canonicalURL = canonicalURL ?? self.webURL
        self.appURL = appURL ?? self.deepLinkURL
        self.artworkURL = albumArtURL
        self.artworkColors = artworkColors
        self.previewURL = previewURL
        self.explicit = explicit
        self.durationMs = durationMs
        self.mayRequireSubscription = mayRequireSubscription
        self.requiresSubscription = requiresSubscription ?? mayRequireSubscription ?? (resolvedProvider == .appleMusic ? true : nil)
        self.requiresAppInstall = requiresAppInstall ?? requiresAccount ?? (resolvedProvider == .spotify ? true : nil)
        self.metadataVersion = metadataVersion
        self.addedAt = addedAt
        self.resolvedAt = resolvedAt
    }

    init(
        id: String = UUID().uuidString,
        provider: MusicProvider,
        entityType: MusicEntityType = .song,
        providerID: String,
        storefront: String? = nil,
        title: String,
        artist: String,
        subtitle: String? = nil,
        albumArtURL: String? = nil,
        deepLinkURL: String? = nil,
        webURL: String? = nil,
        canonicalURL: String? = nil,
        appURL: String? = nil,
        artworkColors: MusicArtworkColors? = nil,
        explicit: Bool? = nil,
        durationMs: Int? = nil,
        requiresAccount: Bool? = nil,
        mayRequireSubscription: Bool? = nil,
        metadataVersion: Int? = nil,
        addedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.init(
            id: id,
            provider: provider,
            entityType: entityType,
            providerID: providerID,
            title: title,
            artist: artist,
            subtitle: subtitle,
            storefront: storefront,
            albumArtURL: albumArtURL,
            artworkColors: artworkColors,
            deepLinkURL: deepLinkURL,
            webURL: webURL,
            canonicalURL: canonicalURL,
            appURL: appURL,
            explicit: explicit,
            durationMs: durationMs,
            requiresAccount: requiresAccount,
            mayRequireSubscription: mayRequireSubscription,
            metadataVersion: metadataVersion,
            addedAt: addedAt,
            resolvedAt: resolvedAt
        )
    }

    private static func spotifyTrackWebURL(from trackID: String?) -> String? {
        guard let trackID, !trackID.isEmpty else { return nil }
        return "https://open.spotify.com/track/\(trackID)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case entityType
        case providerID
        case title
        case artist
        case subtitle
        case storefront
        case musicKitID
        case deepLinkURL
        case webURL
        case canonicalURL
        case appURL
        case artworkURL
        case artworkColors
        case previewURL
        case explicit
        case durationMs
        case mayRequireSubscription
        case requiresSubscription
        case requiresAppInstall
        case metadataVersion
        case addedAt
        case resolvedAt
        case appleMusicURL
        case albumArtURL
        case spotifyTrackID
        case spotifyTrackURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let legacySpotifyTrackID = try c.decodeIfPresent(String.self, forKey: .spotifyTrackID)
        let legacySpotifyTrackURL = try c.decodeIfPresent(String.self, forKey: .spotifyTrackURL)
        let legacyAppleMusicURL = try c.decodeIfPresent(String.self, forKey: .appleMusicURL)
        let legacyAlbumArtURL = try c.decodeIfPresent(String.self, forKey: .albumArtURL)
        let decodedProvider = try c.decodeIfPresent(MusicProvider.self, forKey: .provider)
            ?? (legacySpotifyTrackID != nil || legacySpotifyTrackURL != nil ? .spotify : .appleMusic)

        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        provider = decodedProvider
        entityType = try c.decodeIfPresent(MusicEntityType.self, forKey: .entityType) ?? .song
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        storefront = try c.decodeIfPresent(String.self, forKey: .storefront)
        musicKitID = try c.decodeIfPresent(String.self, forKey: .musicKitID)
        appURL = try c.decodeIfPresent(String.self, forKey: .appURL)
        deepLinkURL = try c.decodeIfPresent(String.self, forKey: .deepLinkURL) ?? appURL ?? legacySpotifyTrackURL ?? legacyAppleMusicURL
        let decodedCanonicalURL = try c.decodeIfPresent(String.self, forKey: .canonicalURL)
        webURL = try c.decodeIfPresent(String.self, forKey: .webURL)
            ?? decodedCanonicalURL
            ?? legacyAppleMusicURL
            ?? Self.spotifyTrackWebURL(from: legacySpotifyTrackID)
        canonicalURL = decodedCanonicalURL ?? webURL
        artworkURL = try c.decodeIfPresent(String.self, forKey: .artworkURL) ?? legacyAlbumArtURL
        artworkColors = try c.decodeIfPresent(MusicArtworkColors.self, forKey: .artworkColors)
        previewURL = try c.decodeIfPresent(String.self, forKey: .previewURL)
        explicit = try c.decodeIfPresent(Bool.self, forKey: .explicit)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        mayRequireSubscription = try c.decodeIfPresent(Bool.self, forKey: .mayRequireSubscription)
        requiresSubscription = try c.decodeIfPresent(Bool.self, forKey: .requiresSubscription)
            ?? mayRequireSubscription
        requiresAppInstall = try c.decodeIfPresent(Bool.self, forKey: .requiresAppInstall)
        metadataVersion = try c.decodeIfPresent(Int.self, forKey: .metadataVersion)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        providerID = try c.decodeIfPresent(String.self, forKey: .providerID)
            ?? legacySpotifyTrackID
            ?? musicKitID
            ?? UUID().uuidString
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(provider, forKey: .provider)
        try c.encode(entityType, forKey: .entityType)
        try c.encode(providerID, forKey: .providerID)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(storefront, forKey: .storefront)
        try c.encodeIfPresent(musicKitID, forKey: .musicKitID)
        try c.encodeIfPresent(deepLinkURL, forKey: .deepLinkURL)
        try c.encodeIfPresent(webURL, forKey: .webURL)
        try c.encodeIfPresent(canonicalURL, forKey: .canonicalURL)
        try c.encodeIfPresent(appURL, forKey: .appURL)
        try c.encodeIfPresent(artworkURL, forKey: .artworkURL)
        try c.encodeIfPresent(artworkColors, forKey: .artworkColors)
        try c.encodeIfPresent(previewURL, forKey: .previewURL)
        try c.encodeIfPresent(explicit, forKey: .explicit)
        try c.encodeIfPresent(durationMs, forKey: .durationMs)
        try c.encodeIfPresent(mayRequireSubscription, forKey: .mayRequireSubscription)
        try c.encodeIfPresent(requiresSubscription, forKey: .requiresSubscription)
        try c.encodeIfPresent(requiresAppInstall, forKey: .requiresAppInstall)
        try c.encodeIfPresent(metadataVersion, forKey: .metadataVersion)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encodeIfPresent(resolvedAt, forKey: .resolvedAt)

        // Legacy keys preserved for older surfaces and Firestore consumers.
        try c.encodeIfPresent(appleMusicURL, forKey: .appleMusicURL)
        try c.encodeIfPresent(albumArtURL, forKey: .albumArtURL)
        try c.encodeIfPresent(spotifyTrackID, forKey: .spotifyTrackID)
        try c.encodeIfPresent(spotifyTrackURL, forKey: .spotifyTrackURL)
    }
}

struct AfterServiceReflectionDraft: Hashable {
    var stoodOut: String
    var application: String
    var prayer: String
    var continueStudy: Bool

    func applying(
        to note: ChurchNote,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ChurchNote {
        var updated = note
        updated.permission = .privateNote
        updated.sharedWith = []
        updated.growthReflection = trimmedOptional(stoodOut)
        updated.actionStepThisWeek = trimmedOptional(application)
        updated.prayerFromSermon = trimmedOptional(prayer)
        updated.shouldRevisit = continueStudy
        updated.revisitDate = continueStudy ? calendar.date(byAdding: .day, value: 7, to: now) : nil
        updated.updatedAt = now
        return updated
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum NotePermission: String, Codable {
    case privateNote = "private"
    case shared = "shared"
    case publicNote = "public"
}

enum NoteSortOption: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case titleAZ = "Title A-Z"
    case titleZA = "Title Z-A"
    case church = "Church"
}

struct ChurchNote: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var sermonTitle: String?
    var churchName: String?
    var churchId: String?  // Firestore church document ID for querying
    var pastor: String?
    var date: Date
    var content: String
    var scripture: String?
    var keyPoints: [String]
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // P0-2: Optimistic concurrency control
    var version: Int // Version number for conflict detection
    
    // New features
    var folderId: String? // For organizing notes into folders
    var permission: NotePermission // Privacy setting
    var sharedWith: [String] // UserIDs of people note is shared with
    var scriptureReferences: [String] // Array of scripture references
    var shareLinkId: String? // Unique ID for deep linking and sharing
    var worshipSongs: [WorshipSongReference] // Songs linked to this note
    var visitPlanId: String? // Link back to visit plan (bidirectional)
    var claudeTags: [String] // AI-detected spiritual theme tags

    // Feature 1: Rich Text
    var richContentJSON: String?  // JSON-encoded RichTextDocument

    // Feature 3: Checklists
    var checklists: [ChecklistItem] // Checklist items for this note

    // Feature 4: Audio
    var audioRecordingURL: String?  // Remote URL of WAV recording
    var hasTranscript: Bool         // true once transcription is available

    // Feature 6: Inter-Note Linking
    var linkedNoteIds: [String]     // IDs of notes this note is linked to

    // Feature 7: Attachments
    var attachmentCount: Int        // Cached count of attachments

    // Personal Growth Fields
    var actionStepThisWeek: String?     // Concrete action from sermon
    var prayerFromSermon: String?        // Prayer captured during service
    var shouldRevisit: Bool              // User toggle for revisit reminder
    var revisitDate: Date?               // When to revisit this note
    var growthReflection: String?        // "What God is teaching me"

    // Semantic blocks (expressive formatting)
    var blocks: [ChurchNoteBlock]  // Semantic blocks (takeaway, prayer, quote, etc.)

    // Formatting metadata
    var formattingRanges: [NoteFormattingRange]  // Rich text formatting spans

    // Coding keys for Firestore
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case title
        case sermonTitle
        case churchName
        case churchId
        case pastor
        case date
        case content
        case scripture
        case keyPoints
        case tags
        case isFavorite
        case createdAt
        case updatedAt
        case version
        case folderId
        case permission
        case sharedWith
        case scriptureReferences
        case shareLinkId
        case worshipSongs
        case visitPlanId
        case claudeTags
        case richContentJSON
        case checklists
        case audioRecordingURL
        case hasTranscript
        case linkedNoteIds
        case attachmentCount
        case actionStepThisWeek
        case prayerFromSermon
        case shouldRevisit
        case revisitDate
        case growthReflection
        case blocks
        case formattingRanges
    }
    
    // Initializer with defaults
    init(
        id: String? = nil,
        userId: String,
        title: String,
        sermonTitle: String? = nil,
        churchName: String? = nil,
        churchId: String? = nil,
        pastor: String? = nil,
        date: Date = Date(),
        content: String,
        scripture: String? = nil,
        keyPoints: [String] = [],
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        version: Int = 0,
        folderId: String? = nil,
        permission: NotePermission = .privateNote,
        sharedWith: [String] = [],
        scriptureReferences: [String] = [],
        shareLinkId: String? = nil,
        worshipSongs: [WorshipSongReference] = [],
        visitPlanId: String? = nil,
        claudeTags: [String] = [],
        richContentJSON: String? = nil,
        checklists: [ChecklistItem] = [],
        audioRecordingURL: String? = nil,
        hasTranscript: Bool = false,
        linkedNoteIds: [String] = [],
        attachmentCount: Int = 0,
        actionStepThisWeek: String? = nil,
        prayerFromSermon: String? = nil,
        shouldRevisit: Bool = false,
        revisitDate: Date? = nil,
        growthReflection: String? = nil,
        blocks: [ChurchNoteBlock] = [],
        formattingRanges: [NoteFormattingRange] = []
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.sermonTitle = sermonTitle
        self.churchName = churchName
        self.churchId = churchId
        self.pastor = pastor
        self.date = date
        self.content = content
        self.scripture = scripture
        self.keyPoints = keyPoints
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.folderId = folderId
        self.permission = permission
        self.sharedWith = sharedWith
        self.scriptureReferences = scriptureReferences
        // Generate share link ID if not provided
        self.shareLinkId = shareLinkId ?? UUID().uuidString
        self.worshipSongs = worshipSongs
        self.visitPlanId = visitPlanId
        self.claudeTags = claudeTags
        self.richContentJSON = richContentJSON
        self.checklists = checklists
        self.audioRecordingURL = audioRecordingURL
        self.hasTranscript = hasTranscript
        self.linkedNoteIds = linkedNoteIds
        self.attachmentCount = attachmentCount
        self.actionStepThisWeek = actionStepThisWeek
        self.prayerFromSermon = prayerFromSermon
        self.shouldRevisit = shouldRevisit
        self.revisitDate = revisitDate
        self.growthReflection = growthReflection
        self.blocks = blocks
        self.formattingRanges = formattingRanges
    }
    
    // Custom Decodable init to handle older Firestore documents that were created
    // before newer fields (version, permission, sharedWith, etc.) were added.
    // Using decodeIfPresent with safe defaults prevents "keyNotFound" crashes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decodeIfPresent(String.self, forKey: .id)
        userId             = try c.decode(String.self, forKey: .userId)
        title              = try c.decode(String.self, forKey: .title)
        sermonTitle        = try c.decodeIfPresent(String.self, forKey: .sermonTitle)
        churchName         = try c.decodeIfPresent(String.self, forKey: .churchName)
        churchId           = try c.decodeIfPresent(String.self, forKey: .churchId)
        pastor             = try c.decodeIfPresent(String.self, forKey: .pastor)
        date               = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        content            = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        scripture          = try c.decodeIfPresent(String.self, forKey: .scripture)
        keyPoints          = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        tags               = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite         = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt          = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt          = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        version            = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        folderId           = try c.decodeIfPresent(String.self, forKey: .folderId)
        permission         = try c.decodeIfPresent(NotePermission.self, forKey: .permission) ?? .privateNote
        sharedWith         = try c.decodeIfPresent([String].self, forKey: .sharedWith) ?? []
        scriptureReferences = try c.decodeIfPresent([String].self, forKey: .scriptureReferences) ?? []
        shareLinkId        = try c.decodeIfPresent(String.self, forKey: .shareLinkId) ?? UUID().uuidString
        worshipSongs       = try c.decodeIfPresent([WorshipSongReference].self, forKey: .worshipSongs) ?? []
        visitPlanId        = try c.decodeIfPresent(String.self, forKey: .visitPlanId)
        claudeTags         = try c.decodeIfPresent([String].self, forKey: .claudeTags) ?? []
        richContentJSON    = try c.decodeIfPresent(String.self, forKey: .richContentJSON)
        checklists         = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklists) ?? []
        audioRecordingURL  = try c.decodeIfPresent(String.self, forKey: .audioRecordingURL)
        hasTranscript      = try c.decodeIfPresent(Bool.self, forKey: .hasTranscript) ?? false
        linkedNoteIds      = try c.decodeIfPresent([String].self, forKey: .linkedNoteIds) ?? []
        attachmentCount    = try c.decodeIfPresent(Int.self, forKey: .attachmentCount) ?? 0
        actionStepThisWeek = try c.decodeIfPresent(String.self, forKey: .actionStepThisWeek)
        prayerFromSermon   = try c.decodeIfPresent(String.self, forKey: .prayerFromSermon)
        shouldRevisit      = try c.decodeIfPresent(Bool.self, forKey: .shouldRevisit) ?? false
        revisitDate        = try c.decodeIfPresent(Date.self, forKey: .revisitDate)
        growthReflection   = try c.decodeIfPresent(String.self, forKey: .growthReflection)
        blocks             = try c.decodeIfPresent([ChurchNoteBlock].self, forKey: .blocks) ?? []
        formattingRanges   = try c.decodeIfPresent([NoteFormattingRange].self, forKey: .formattingRanges) ?? []
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ChurchNote, rhs: ChurchNote) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Preview Helpers
extension ChurchNote {
    static var preview: ChurchNote {
        ChurchNote(
            userId: "preview-user",
            title: "The Power of Prayer",
            sermonTitle: "Mountain Moving Faith",
            churchName: "Grace Community Church",
            pastor: "Pastor John Smith",
            date: Date(),
            content: "Today's sermon was incredibly powerful. Pastor John spoke about the importance of prayer and how it can move mountains in our lives. Key takeaways:\n\n1. Prayer is not just asking, it's also listening\n2. Faith without works is dead\n3. God's timing is perfect\n\nI was particularly moved by the story about the widow's persistence. It reminded me that I need to be more consistent in my prayer life.",
            scripture: "Matthew 17:20",
            keyPoints: [
                "Prayer is conversation with God",
                "Faith requires action",
                "Persistence in prayer"
            ],
            tags: ["prayer", "faith", "sermon"],
            isFavorite: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    static var previews: [ChurchNote] {
        [
            ChurchNote(
                userId: "preview-user",
                title: "The Power of Prayer",
                sermonTitle: "Mountain Moving Faith",
                churchName: "Grace Community Church",
                pastor: "Pastor John Smith",
                date: Date(),
                content: "Today's sermon was incredibly powerful. Key takeaways about prayer and faith.",
                scripture: "Matthew 17:20",
                keyPoints: ["Prayer", "Faith", "Action"],
                tags: ["prayer", "faith"],
                isFavorite: true
            ),
            ChurchNote(
                userId: "preview-user",
                title: "God's Love Never Fails",
                sermonTitle: "Unconditional Love",
                churchName: "Hope Fellowship",
                pastor: "Pastor Sarah Johnson",
                date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
                content: "Powerful message about God's unfailing love for us.",
                scripture: "Romans 8:38-39",
                keyPoints: ["God's love", "Grace", "Forgiveness"],
                tags: ["love", "grace"],
                isFavorite: false
            ),
            ChurchNote(
                userId: "preview-user",
                title: "Walking by Faith",
                sermonTitle: "Trust in the Lord",
                churchName: "New Life Church",
                pastor: "Pastor Michael Brown",
                date: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
                content: "Learning to trust God even when we can't see the path ahead.",
                scripture: "2 Corinthians 5:7",
                keyPoints: ["Faith", "Trust", "Obedience"],
                tags: ["faith", "trust"],
                isFavorite: true
            )
        ]
    }
}
