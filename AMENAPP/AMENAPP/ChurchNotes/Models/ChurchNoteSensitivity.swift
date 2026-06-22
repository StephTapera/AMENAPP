import SwiftUI

/// Category of pastoral / counseling / prayer-confidential context.
/// When a note is tagged with any of these, the privacy default is forced to
/// `.privateNote` and the UI surfaces a lock indicator. The user can still
/// remove the sensitive tag if they want to share — explicit, never implicit.
enum ChurchNoteSensitivityCategory: String, CaseIterable, Equatable {
    case pastoral
    case counseling
    case prayer

    var displayLabel: String {
        switch self {
        case .pastoral:   return "Pastoral care"
        case .counseling: return "Counseling"
        case .prayer:     return "Confidential prayer"
        }
    }

    var sfSymbol: String {
        switch self {
        case .pastoral:   return "person.fill.questionmark"
        case .counseling: return "ear.fill"
        case .prayer:     return "hands.sparkles.fill"
        }
    }

    /// Tag substrings (lower-cased) that map to this sensitivity category.
    var detectionTags: [String] {
        switch self {
        case .pastoral:   return ["pastoral", "pastoral-care", "pastoralcare"]
        case .counseling: return ["counseling", "counselling"]
        case .prayer:     return ["confidential-prayer", "private-prayer", "confidential prayer"]
        }
    }

    /// Maps a raw tag string to a sensitivity category if it matches a known
    /// sensitive tag. Whitespace and case are normalized.
    static func detect(in tags: [String]) -> ChurchNoteSensitivityCategory? {
        let normalized = Set(tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        for category in ChurchNoteSensitivityCategory.allCases {
            for needle in category.detectionTags where normalized.contains(needle) {
                return category
            }
        }
        return nil
    }
}

extension ChurchNote {
    /// The sensitivity category detected from this note's tags, if any.
    /// Detection is conservative — only explicit, well-known tag values trigger it,
    /// so a note about a sermon on counseling doesn't get locked unless the user
    /// or template intentionally marked it.
    var detectedSensitivity: ChurchNoteSensitivityCategory? {
        ChurchNoteSensitivityCategory.detect(in: tags)
    }

    /// True if the note's sensitivity locks it to private. The user can remove
    /// the sensitive tag if they want to share — this is a soft lock that prevents
    /// accidental sharing, not a permanent restriction.
    var isPrivacyLocked: Bool {
        detectedSensitivity != nil
    }

    /// Returns the permission that should be applied at write time given the
    /// user's requested permission. If the note is currently sensitive, the
    /// effective permission is always `.privateNote` regardless of request.
    func effectivePermission(requested: NotePermission) -> NotePermission {
        isPrivacyLocked ? .privateNote : requested
    }
}

/// Indicator badge displayed in the editor header so the user always knows the
/// current privacy state of their note and why it's locked when sensitive.
struct ChurchNotePrivacyIndicator: View {
    let note: ChurchNote

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
            if let sensitivity = note.detectedSensitivity {
                Text("• \(sensitivity.displayLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        if note.isPrivacyLocked { return "lock.shield.fill" }
        switch note.permission {
        case .privateNote: return "lock.fill"
        case .shared:      return "person.2.fill"
        case .publicNote:  return "globe"
        }
    }

    private var label: String {
        if note.isPrivacyLocked { return "Private — locked" }
        switch note.permission {
        case .privateNote: return "Private"
        case .shared:      return "Shared"
        case .publicNote:  return "Public"
        }
    }

    private var background: Color {
        if note.isPrivacyLocked { return Color.purple.opacity(0.12) }
        switch note.permission {
        case .privateNote: return Color(.secondarySystemFill)
        case .shared:      return Color.blue.opacity(0.12)
        case .publicNote:  return Color.green.opacity(0.12)
        }
    }

    private var foreground: Color {
        if note.isPrivacyLocked { return .purple }
        switch note.permission {
        case .privateNote: return .secondary
        case .shared:      return .blue
        case .publicNote:  return .green
        }
    }

    private var accessibilityLabel: String {
        if let sensitivity = note.detectedSensitivity {
            return "Private — locked because note is tagged \(sensitivity.displayLabel)"
        }
        switch note.permission {
        case .privateNote: return "Private note. Only you can see it."
        case .shared:      return "Shared note. Visible to collaborators."
        case .publicNote:  return "Public note."
        }
    }
}
