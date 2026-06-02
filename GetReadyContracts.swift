import Foundation

struct GetReadyHeroMotion: Equatable {
    var progress: Double = 0
    var velocity: Double = 0

    var overlayScale: Double {
        max(0.988, 1.0 - min(max(progress, 0), 1) * 0.012)
    }

    var readingMode: Bool {
        abs(velocity) < 0.12
    }

    var dense: Bool {
        progress > 0.45
    }

    var glassOpacityBoost: Double {
        min(max(progress, 0), 1) * 0.18
    }

    var overlayOffset: Double {
        -min(max(progress, 0), 1) * 18
    }
}

struct GetReadyComposerAction: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let icon: String

    static let standard: [GetReadyComposerAction] = [
        GetReadyComposerAction(id: "pray", title: "Pray", icon: "hands.sparkles"),
        GetReadyComposerAction(id: "reflect", title: "Reflect", icon: "text.book.closed"),
        GetReadyComposerAction(id: "share", title: "Share", icon: "square.and.arrow.up"),
        GetReadyComposerAction(id: "save", title: "Save", icon: "bookmark")
    ]

    static let contextual: [GetReadyComposerAction] = [
        GetReadyComposerAction(id: "route", title: "Route", icon: "location"),
        GetReadyComposerAction(id: "remind", title: "Remind", icon: "bell"),
        GetReadyComposerAction(id: "invite", title: "Invite", icon: "person.badge.plus")
    ]
}
