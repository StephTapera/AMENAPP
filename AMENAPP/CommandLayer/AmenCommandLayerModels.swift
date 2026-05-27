import Foundation
import SwiftUI

enum AmenCommandLayerSurface: String, CaseIterable, Identifiable {
    case home
    case messages
    case churchNotes
    case spaces
    case berean
    case profile
    case createPost
    case events
    case media
    case discovery

    var id: String { rawValue }

    var placeholder: String {
        switch self {
        case .home:
            return "Ask Berean, pray, reflect, or create..."
        case .messages:
            return "Message, pray, attach, or summarize..."
        case .churchNotes:
            return "Ask Berean about this note..."
        case .spaces:
            return "Post, discuss, plan, or ask..."
        case .berean:
            return "Ask Berean, study, search, or save..."
        case .profile:
            return "Create, reflect, or update..."
        case .createPost:
            return "Write, attach, pray, or publish..."
        case .events:
            return "Plan, RSVP, invite, or ask..."
        case .media:
            return "Comment, save, study, or share..."
        case .discovery:
            return "Search, ask, save, or explore..."
        }
    }

    var navigationChips: [AmenContextualNavigationChip] {
        switch self {
        case .churchNotes:
            return [
                AmenContextualNavigationChip(id: "notes", title: "Notes", systemImage: "note.text"),
                AmenContextualNavigationChip(id: "prayer", title: "Prayer", systemImage: "hands.sparkles"),
                AmenContextualNavigationChip(id: "study", title: "Study", systemImage: "book.closed"),
                AmenContextualNavigationChip(id: "files", title: "Files", systemImage: "folder")
            ]
        case .spaces:
            return [
                AmenContextualNavigationChip(id: "feed", title: "Feed", systemImage: "rectangle.stack"),
                AmenContextualNavigationChip(id: "events", title: "Events", systemImage: "calendar"),
                AmenContextualNavigationChip(id: "notes", title: "Notes", systemImage: "note.text"),
                AmenContextualNavigationChip(id: "prayer", title: "Prayer", systemImage: "hands.sparkles")
            ]
        default:
            return [
                AmenContextualNavigationChip(id: "home", title: "Home", systemImage: "house"),
                AmenContextualNavigationChip(id: "messages", title: "Messages", systemImage: "bubble.left.and.bubble.right"),
                AmenContextualNavigationChip(id: "calendar", title: "Calendar", systemImage: "calendar"),
                AmenContextualNavigationChip(id: "notes", title: "Notes", systemImage: "note.text"),
                AmenContextualNavigationChip(id: "spaces", title: "Spaces", systemImage: "person.3")
            ]
        }
    }
}

enum AmenCommandLayerActionID: String, CaseIterable, Identifiable {
    case prayerRequest
    case testimony
    case churchNote
    case reflection
    case createImage
    case deepStudy
    case webSearch
    case addFiles
    case aiMeetingNotes
    case startSpace
    case rsvpEvent
    case camera
    case photos
    case askBerean
    case openCommandPalette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prayerRequest: return "Prayer Request"
        case .testimony: return "Testimony"
        case .churchNote: return "Church Note"
        case .reflection: return "Reflection"
        case .createImage: return "Create Image"
        case .deepStudy: return "Deep Study"
        case .webSearch: return "Web Search"
        case .addFiles: return "Add Files"
        case .aiMeetingNotes: return "AI Meeting Notes"
        case .startSpace: return "Start Space"
        case .rsvpEvent: return "RSVP/Event"
        case .camera: return "Camera"
        case .photos: return "Photos"
        case .askBerean: return "Ask Berean"
        case .openCommandPalette: return "Command Palette"
        }
    }

    var subtitle: String {
        switch self {
        case .prayerRequest: return "Create a private or public prayer post"
        case .testimony: return "Share a guided testimony draft"
        case .churchNote: return "Start a note from sermon, class, or meeting"
        case .reflection: return "Capture a scripture or journal reflection"
        case .createImage: return "Generate a faith-safe visual when enabled"
        case .deepStudy: return "Open Berean research mode"
        case .webSearch: return "Use verified external lookup when enabled"
        case .addFiles: return "Attach files through existing media flows"
        case .aiMeetingNotes: return "Summarize ministry, school, or team notes"
        case .startSpace: return "Open community and space creation flows"
        case .rsvpEvent: return "Open event and RSVP flows"
        case .camera: return "Capture media with permission"
        case .photos: return "Choose photos with permission"
        case .askBerean: return "Ask Berean with this surface context"
        case .openCommandPalette: return "Search all available commands"
        }
    }

    var systemImage: String {
        switch self {
        case .prayerRequest: return "hands.sparkles"
        case .testimony: return "star.bubble"
        case .churchNote: return "note.text"
        case .reflection: return "book.closed"
        case .createImage: return "photo.badge.sparkles"
        case .deepStudy: return "books.vertical"
        case .webSearch: return "magnifyingglass"
        case .addFiles: return "paperclip"
        case .aiMeetingNotes: return "waveform.and.magnifyingglass"
        case .startSpace: return "person.3"
        case .rsvpEvent: return "calendar.badge.plus"
        case .camera: return "camera"
        case .photos: return "photo.on.rectangle"
        case .askBerean: return "sparkles"
        case .openCommandPalette: return "command"
        }
    }

    var requiresPermission: Bool {
        switch self {
        case .camera, .photos, .addFiles, .aiMeetingNotes:
            return true
        default:
            return false
        }
    }
}

struct AmenCommandLayerAction: Identifiable, Equatable {
    let id: AmenCommandLayerActionID
    let isAvailable: Bool
    let unavailableReason: String?

    init(id: AmenCommandLayerActionID, isAvailable: Bool = true, unavailableReason: String? = nil) {
        self.id = id
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
    }
}

struct AmenContextualNavigationChip: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
}

enum AmenCommandLayerCatalog {
    static func actions(for surface: AmenCommandLayerSurface) -> [AmenCommandLayerAction] {
        switch surface {
        case .home:
            return [
                AmenCommandLayerAction(id: .askBerean),
                AmenCommandLayerAction(id: .prayerRequest),
                AmenCommandLayerAction(id: .reflection),
                AmenCommandLayerAction(id: .testimony),
                AmenCommandLayerAction(id: .churchNote),
                AmenCommandLayerAction(id: .deepStudy),
                AmenCommandLayerAction(id: .addFiles),
                AmenCommandLayerAction(id: .camera),
                AmenCommandLayerAction(id: .photos),
                AmenCommandLayerAction(id: .startSpace),
                AmenCommandLayerAction(id: .rsvpEvent),
                AmenCommandLayerAction(id: .createImage, isAvailable: false, unavailableReason: "Image generation is not enabled on Home yet."),
                AmenCommandLayerAction(id: .aiMeetingNotes, isAvailable: false, unavailableReason: "Meeting notes are not available from Home yet."),
                AmenCommandLayerAction(id: .webSearch, isAvailable: false, unavailableReason: "Web search must route through Berean verification first."),
                AmenCommandLayerAction(id: .openCommandPalette)
            ]
        case .messages:
            return [.askBerean, .prayerRequest, .addFiles, .aiMeetingNotes, .photos, .camera, .openCommandPalette].map(AmenCommandLayerAction.init)
        case .churchNotes:
            return [.askBerean, .churchNote, .reflection, .deepStudy, .aiMeetingNotes, .addFiles, .photos, .camera].map(AmenCommandLayerAction.init)
        case .spaces:
            return [.startSpace, .prayerRequest, .churchNote, .rsvpEvent, .deepStudy, .addFiles, .openCommandPalette].map(AmenCommandLayerAction.init)
        case .berean:
            return [.askBerean, .deepStudy, .webSearch, .reflection, .churchNote, .addFiles].map(AmenCommandLayerAction.init)
        case .profile:
            return [.reflection, .testimony, .prayerRequest, .photos, .openCommandPalette].map(AmenCommandLayerAction.init)
        case .createPost:
            return [.prayerRequest, .testimony, .reflection, .churchNote, .addFiles, .camera, .photos].map(AmenCommandLayerAction.init)
        case .events:
            return [.rsvpEvent, .startSpace, .aiMeetingNotes, .addFiles, .openCommandPalette].map(AmenCommandLayerAction.init)
        case .media:
            return [.askBerean, .reflection, .churchNote, .deepStudy, .addFiles, .openCommandPalette].map(AmenCommandLayerAction.init)
        case .discovery:
            return [.webSearch, .askBerean, .deepStudy, .startSpace, .openCommandPalette].map(AmenCommandLayerAction.init)
        }
    }
}

private extension AmenCommandLayerAction {
    init(_ id: AmenCommandLayerActionID) {
        self.init(id: id)
    }
}
