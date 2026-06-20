//
//  ResourceGlassKit.swift
//  AMENAPP
//
//  Wave 1 — Contracts & adapters for the white Liquid Glass Resources home.
//
//  Design doctrine (see redesign prompt):
//   • White / warm-ivory background, black primary text, soft-gray secondary.
//   • Accent = warm tan + wine-red as SUBTLE highlights only — mapped to the closest
//     existing Amen tokens (tan == PulseInk.gold #D4A85C). No new color system.
//   • No-glass-on-glass: content cards are OPAQUE WHITE. Glass (.ultraThinMaterial) is
//     reserved for action pills, the hero overlay, the search bar, the mini-player,
//     and sheet overlays — implemented in ResourceGlassComponents.swift.
//   • Every contract field below is ADDITIVE and OPTIONAL. Missing metadata must never
//     break a card; adapters fill clean placeholders. Existing resources keep working.
//
//  NEW FILE — auto-included via PBXFileSystemSynchronizedRootGroup (AMENAPP/ root).
//  Gated by AMENFeatureFlags.resourcesGlassHomeEnabled (default OFF).
//

import SwiftUI

// MARK: - Tokens (mapped to existing Amen values — NOT a new color system)

enum RGInk {
    /// Warm ivory canvas (mirrors PulseInk.canvas — calm white background).
    static let canvasTop = Color(hex: "FFFEFA")
    static let canvasBottom = Color(hex: "F6F4EE")
    /// Warm tan accent — same value as PulseInk.gold. Subtle highlights only.
    static let tan = Color(hex: "D4A85C")
    /// Wine-red accent — subtle highlights only, never a fill or a loud state.
    static let wine = Color(hex: "8E3B46")
    /// Hairline soft-gray divider on white.
    static let hairline = Color.black.opacity(0.06)
    /// Opaque white content-card fill (no-glass-on-glass).
    static let card = Color(.systemBackground)

    static let cardCorner: CGFloat = 24
    static let heroCorner: CGFloat = 30
    static let chipCorner: CGFloat = 18
    static let rowCorner: CGFloat = 18
}

// MARK: - Enums

/// Resource medium. Drives the type icon + content label (sermon · study · …).
enum ResourceGlassType: String, CaseIterable {
    case sermon, study, devotional, podcast, book, guide, video, event, course, sermonNotes, plan, generic

    var icon: String {
        switch self {
        case .sermon:      return "mic.fill"
        case .study:       return "book.closed.fill"
        case .devotional:  return "sun.and.horizon.fill"
        case .podcast:     return "waveform"
        case .book:        return "books.vertical.fill"
        case .guide:       return "list.bullet.rectangle.fill"
        case .video:       return "play.rectangle.fill"
        case .event:       return "calendar"
        case .course:      return "graduationcap.fill"
        case .sermonNotes: return "note.text"
        case .plan:        return "checklist"
        case .generic:     return "doc.text.fill"
        }
    }

    /// Calm content label shown on cards where relevant.
    var label: String {
        switch self {
        case .sermon:      return "Sermon"
        case .study:       return "Study"
        case .devotional:  return "Devotional"
        case .podcast:     return "Podcast"
        case .book:        return "Book"
        case .guide:       return "Guide"
        case .video:       return "Video"
        case .event:       return "Event"
        case .course:      return "Course"
        case .sermonNotes: return "Sermon Notes"
        case .plan:        return "Reading Plan"
        case .generic:     return "Resource"
        }
    }
}

/// Where a resource came from. Used for the "From Your Church / Org" section + labels.
enum ResourceSourceType: String {
    case creator, church, org, user, saved, recommended

    var label: String {
        switch self {
        case .creator:     return "Creator"
        case .church:      return "Your Church"
        case .org:         return "Organization"
        case .user:        return "You"
        case .saved:       return "Saved"
        case .recommended: return "For You"
        }
    }
}

/// Server-enforced access tier. Client uses it only for a calm content label.
enum ResourceAccessLevel: String {
    case free, premium, paid, official

    var contentLabel: String? {
        switch self {
        case .free:     return nil
        case .premium:  return "Premium"
        case .paid:     return "Paid"
        case .official: return "Official"
        }
    }
}

// MARK: - View models

/// One render-ready resource. Carries the additive contract metadata as optionals so a
/// card never crashes on missing data — `accent`/`systemIcon` always have safe defaults.
struct ResourceGlassItem: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil          // author / speaker / source
    var systemIcon: String = "doc.text.fill"
    var accent: Color = RGInk.tan
    /// MEDIA-GATE: nil until approved → render a placeholder, never a raw ref.
    var imageRef: String? = nil
    var type: ResourceGlassType = .generic

    // ── Additive optional contract metadata ──
    var duration: String? = nil
    var progress: Double? = nil          // 0...1, nil = not started / unknown
    var lastOpenedAt: Date? = nil
    var savedAt: Date? = nil
    var sourceType: ResourceSourceType? = nil
    var bundleId: String? = nil
    var isOfficial: Bool = false
    var accessLevel: ResourceAccessLevel = .free
    var downloadable: Bool = false
    var aiEligible: Bool = false
    var recommendationReason: String? = nil
    var tags: [String] = []
    var scriptureReferences: [String] = []

    /// Optional media payload — preserves existing playback wiring (AMENResourceDetailView).
    var mediaEntry: AMENMediaEntry? = nil
}

/// A counted chip for bundles + the daily summary ("05 PDFs", "12 Notes").
struct ResourceCountChip: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

/// A stacked bundle (study kit, small-group pack, sermon-notes set, class materials).
struct ResourceGlassBundle: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    var systemIcon: String = "square.stack.3d.up.fill"
    var accent: Color = RGInk.tan
    var imageRef: String? = nil          // MEDIA-GATE
    var counts: [ResourceCountChip] = []
    var isOfficial: Bool = false
    var previewCount: Int = 0            // total items, for the fan badge
}

/// Natural-language daily summary line + stat pills (re-skinned from greeting/context).
struct ResourceDailySummary {
    let greeting: String                 // "Good morning, Steph."
    let line: String                     // "You have 2 studies, 1 saved sermon…"
    var stats: [ResourceCountChip] = []
}

/// The split hero "Recommended for your season."
struct ResourceHeroContent {
    let eyebrow: String                  // "Recommended for your season"
    let title: String
    var subtitle: String? = nil
    var chips: [String] = []             // 2–3 contextual chips (day, theme…)
    var imageRef: String? = nil          // MEDIA-GATE
    var accent: Color = RGInk.tan
    var reason: String? = nil            // "Why this?"
    var primary: ResourceGlassItem? = nil
}

// MARK: - Adapters (read existing data → fill safe placeholders)

enum ResourceGlassAdapters {

    /// Format a seconds duration as a calm label, or nil when unknown.
    static func formatDuration(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// Map a legacy `ResourceItem` (icon/title/description/category) into a glass item.
    static func item(from r: ResourceItem) -> ResourceGlassItem {
        ResourceGlassItem(
            id: r.id.uuidString,
            title: r.title,
            subtitle: r.description,
            systemIcon: r.icon,
            accent: r.iconColor,
            type: inferType(category: r.category, icon: r.icon),
            sourceType: inferSource(category: r.category),
            tags: [r.category]
        )
    }

    /// Map a sermon into a media-backed glass item (preserves playback via mediaEntry).
    static func item(from s: AMENSermon) -> ResourceGlassItem {
        ResourceGlassItem(
            id: "sermon_\(s.id)",
            title: s.title,
            subtitle: s.speaker.isEmpty ? s.church : s.speaker,
            systemIcon: ResourceGlassType.sermon.icon,
            accent: RGInk.tan,
            imageRef: s.thumbnailURL,
            type: .sermon,
            duration: formatDuration(s.durationSeconds),
            sourceType: .recommended,
            aiEligible: true,
            recommendationReason: s.topic.isEmpty ? nil : "Because you've explored \(s.topic)",
            scriptureReferences: s.scriptureReference.map { [$0] } ?? [],
            mediaEntry: .sermon(s)
        )
    }

    /// Map a podcast episode into a media-backed glass item.
    static func item(from p: AMENPodcastEpisode) -> ResourceGlassItem {
        ResourceGlassItem(
            id: "podcast_\(p.id)",
            title: p.title,
            subtitle: p.showName.isEmpty ? p.host : p.showName,
            systemIcon: ResourceGlassType.podcast.icon,
            accent: RGInk.wine,
            imageRef: p.thumbnailURL,
            type: .podcast,
            duration: formatDuration(p.durationSeconds),
            sourceType: .recommended,
            aiEligible: true,
            mediaEntry: .podcast(p)
        )
    }

    // ── Inference helpers (safe defaults) ──

    private static func inferType(category: String, icon: String) -> ResourceGlassType {
        let c = category.lowercased()
        if c.contains("learning") { return .study }
        if c.contains("community") { return .guide }
        if icon.contains("note") { return .sermonNotes }
        if icon.contains("walk") || icon.contains("figure") { return .devotional }
        return .generic
    }

    private static func inferSource(category: String) -> ResourceSourceType {
        category.lowercased().contains("community") ? .church : .recommended
    }
}
