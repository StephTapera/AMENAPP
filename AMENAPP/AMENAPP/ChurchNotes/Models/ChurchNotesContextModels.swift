import Foundation
import FirebaseFirestore

// MARK: - Context Section Identifiers

enum CNContextSection: String, CaseIterable, Identifiable {
    case relatedScripture
    case relatedNotes
    case themes
    case prayerPrompts
    case reflectionQuestions
    case smallGroupQuestions
    case actionSuggestions

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .relatedScripture:    return "Related Scripture"
        case .relatedNotes:        return "Related Notes"
        case .themes:              return "Possible Themes"
        case .prayerPrompts:       return "Prayer Prompts"
        case .reflectionQuestions: return "Questions to Reflect On"
        case .smallGroupQuestions: return "Small Group Questions"
        case .actionSuggestions:   return "Possible Next Steps"
        }
    }

    var sfSymbol: String {
        switch self {
        case .relatedScripture:    return "book.fill"
        case .relatedNotes:        return "note.text"
        case .themes:              return "tag.fill"
        case .prayerPrompts:       return "hands.sparkles.fill"
        case .reflectionQuestions: return "questionmark.bubble.fill"
        case .smallGroupQuestions: return "person.3.fill"
        case .actionSuggestions:   return "arrow.forward.circle.fill"
        }
    }
}

// MARK: - Provenance

enum CNConfidenceLevel: String, Codable, Equatable {
    case confirmed   = "confirmed"
    case possible    = "possible"
    case needsReview = "needsReview"

    var displayLabel: String {
        switch self {
        case .confirmed:   return "Confirmed"
        case .possible:    return "Possible match"
        case .needsReview: return "Needs review"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .confirmed:   return "Confirmed source match"
        case .possible:    return "Possible match — please verify"
        case .needsReview: return "Needs your review before using"
        }
    }
}

struct CNProvenanceLabel: Codable, Equatable {
    let source: String        // "your note", "prior notes", "transcript", "OCR", "system"
    let confidence: CNConfidenceLevel
    let whySuggested: String  // plain-language explanation shown to user
}

// MARK: - Approval State

enum CNApprovalState: String, Codable, Equatable {
    case pending
    case approved
    case edited
    case rejected
}

// MARK: - Related Scripture

struct CNRelatedScripture: Identifiable, Codable, Equatable {
    let id: String
    let reference: String
    let text: String?
    let provenance: CNProvenanceLabel
    var isApproved: Bool = false
}

// MARK: - Related Notes

struct CNRelatedNote: Identifiable, Codable, Equatable {
    let id: String
    let noteId: String
    let title: String
    let sermonTitle: String?
    let connectionSummary: String
    let sharedThemes: [String]
    let provenance: CNProvenanceLabel
}

// MARK: - Detected Themes

struct CNDetectedTheme: Identifiable, Codable, Equatable {
    let id: String
    let theme: String
    let occurrenceCount: Int
    let isRecurring: Bool
    let exampleQuotes: [String]
    let provenance: CNProvenanceLabel

    var recurringLabel: String {
        isRecurring ? "A recurring theme in your notes" : "This may connect to…"
    }
}

// MARK: - Prayer Prompts

enum CNPrayerPromptCategory: String, Codable, Equatable {
    case personal
    case intercession
    case thanksgiving
    case surrender
    case unknown
}

struct CNPrayerPrompt: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let category: CNPrayerPromptCategory
    let provenance: CNProvenanceLabel
    var isApproved: Bool = false
    var isAddedToPrayer: Bool = false
}

// MARK: - Reflection Questions

struct CNReflectionQuestion: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let isPersonal: Bool
    let provenance: CNProvenanceLabel
}

// MARK: - Small Group Questions

struct CNSmallGroupQuestion: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let provenance: CNProvenanceLabel
    var isApproved: Bool = false
}

// MARK: - Action Suggestions

enum CNActionSuggestionType: String, Codable, Equatable {
    case personalAction
    case prayerItem
    case followUpReminder
    case smallGroupQuestion
    case mentorMessage
    case calendarSuggestion

    var displayLabel: String {
        switch self {
        case .personalAction:     return "Action Step"
        case .prayerItem:         return "Prayer Item"
        case .followUpReminder:   return "Follow-Up"
        case .smallGroupQuestion: return "Group Question"
        case .mentorMessage:      return "Mentor Draft"
        case .calendarSuggestion: return "Calendar"
        }
    }

    var sfSymbol: String {
        switch self {
        case .personalAction:     return "checkmark.circle"
        case .prayerItem:         return "hands.sparkles"
        case .followUpReminder:   return "bell"
        case .smallGroupQuestion: return "person.3"
        case .mentorMessage:      return "envelope"
        case .calendarSuggestion: return "calendar"
        }
    }
}

struct CNActionSuggestion: Identifiable, Codable, Equatable {
    let id: String
    let type: CNActionSuggestionType
    let text: String
    let sourceQuote: String?
    let provenance: CNProvenanceLabel
    var approvalState: CNApprovalState = .pending
    var editedText: String?

    var displayText: String { editedText ?? text }
}

// MARK: - Group Intelligence

struct CNGroupInsight: Identifiable, Codable, Equatable {
    let id: String
    let groupId: String
    let topThemes: [String]
    let emergingPrayerNeeds: [String]
    let recurringQuestions: [String]
    let leaderActionItems: [String]
    let generatedAt: Date?
    let provenance: CNProvenanceLabel
}

// MARK: - Growth Timeline

enum CNGrowthEntryType: String, Codable, Equatable {
    case recurringTheme
    case answeredPrayer
    case repeatedVerse
    case sermonContinuity
    case reflectionCompleted
    case actionFollowedThrough

    var displayLabel: String {
        switch self {
        case .recurringTheme:       return "Recurring Theme"
        case .answeredPrayer:       return "Answered Prayer"
        case .repeatedVerse:        return "Scripture Journey"
        case .sermonContinuity:     return "Sermon Continuity"
        case .reflectionCompleted:  return "Reflection Completed"
        case .actionFollowedThrough: return "Action Followed Through"
        }
    }

    var sfSymbol: String {
        switch self {
        case .recurringTheme:       return "arrow.trianglehead.2.clockwise"
        case .answeredPrayer:       return "checkmark.seal.fill"
        case .repeatedVerse:        return "book.fill"
        case .sermonContinuity:     return "link"
        case .reflectionCompleted:  return "heart.text.square.fill"
        case .actionFollowedThrough: return "checkmark.circle.fill"
        }
    }
}

struct CNGrowthEntry: Identifiable, Codable, Equatable {
    let id: String
    let type: CNGrowthEntryType
    let title: String
    let summary: String
    let relatedNoteIds: [String]
    let date: Date?
    let isPrivate: Bool
    let provenance: CNProvenanceLabel
}

// MARK: - Smart Recap

struct CNSmartRecap: Identifiable, Codable, Equatable {
    let id: String
    let noteId: String
    let whatStoodOut: String
    let prayerItems: [String]
    let nextStep: String?
    let relatedScriptures: [String]
    let relatedNoteIds: [String]
    let isEdited: Bool
    var editedText: String?
    let generatedAt: Date?
    let provenance: CNProvenanceLabel

    var displayText: String { editedText ?? whatStoodOut }
}

// MARK: - Smart Capture

enum CNSmartCaptureContentType: String, Codable, Equatable {
    case sermonSlide
    case whiteboard
    case scriptureReference
    case actionItem
    case prayerRequest
    case quote
    case announcement
    case unknown

    var displayLabel: String {
        switch self {
        case .sermonSlide:       return "Sermon Slide"
        case .whiteboard:        return "Whiteboard"
        case .scriptureReference: return "Scripture"
        case .actionItem:        return "Action Item"
        case .prayerRequest:     return "Prayer Request"
        case .quote:             return "Quote"
        case .announcement:      return "Announcement"
        case .unknown:           return "Content"
        }
    }
}

struct CNSmartCaptureResult: Identifiable, Codable, Equatable {
    let id: String
    let sourceJobId: String
    let detectedType: CNSmartCaptureContentType
    let extractedText: String
    let confidence: CNConfidenceLevel
    let requiresReview: Bool
    var reviewState: CNApprovalState = .pending
    let provenance: CNProvenanceLabel
}

// MARK: - Command Bar

enum CNCommandBarCommand: String, CaseIterable, Identifiable {
    case summarize      = "/summarize"
    case prayer         = "/prayer"
    case study          = "/study"
    case translate      = "/translate"
    case actionItems    = "/action-items"
    case smallGroup     = "/small-group"
    case askBerean      = "/ask-berean"
    case shareWithGroup = "/share-with-group"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .summarize:      return "Summarize this note"
        case .prayer:         return "Generate prayer prompts"
        case .study:          return "Create a study guide"
        case .translate:      return "Translate content"
        case .actionItems:    return "Extract action items"
        case .smallGroup:     return "Generate small group questions"
        case .askBerean:      return "Ask Berean about this note"
        case .shareWithGroup: return "Prepare to share with group"
        }
    }

    var sfSymbol: String {
        switch self {
        case .summarize:      return "text.quote"
        case .prayer:         return "hands.sparkles.fill"
        case .study:          return "graduationcap.fill"
        case .translate:      return "character.bubble.fill"
        case .actionItems:    return "checklist"
        case .smallGroup:     return "person.3.fill"
        case .askBerean:      return "sparkles"
        case .shareWithGroup: return "square.and.arrow.up"
        }
    }
}

struct CNCommandBarResult: Identifiable, Equatable {
    let id: String
    let command: CNCommandBarCommand
    let text: String
    var editedText: String?
    var isApproved: Bool = false
    let provenance: CNProvenanceLabel

    var displayText: String { editedText ?? text }
}

// MARK: - Load State

enum CNContextLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)
}

// MARK: - Full Context Result

struct CNContextResult: Equatable {
    let noteId: String
    var relatedScriptures: [CNRelatedScripture] = []
    var relatedNotes: [CNRelatedNote] = []
    var detectedThemes: [CNDetectedTheme] = []
    var prayerPrompts: [CNPrayerPrompt] = []
    var reflectionQuestions: [CNReflectionQuestion] = []
    var smallGroupQuestions: [CNSmallGroupQuestion] = []
    var actionSuggestions: [CNActionSuggestion] = []
    var smartCaptures: [CNSmartCaptureResult] = []
    var generatedAt: Date?

    var isEmpty: Bool {
        relatedScriptures.isEmpty && detectedThemes.isEmpty &&
        prayerPrompts.isEmpty && actionSuggestions.isEmpty
    }
}
