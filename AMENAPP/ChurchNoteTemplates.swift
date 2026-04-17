// ChurchNoteTemplates.swift
// AMENAPP
//
// Pre-built note templates for different stages of the church visit lifecycle.
// Each template provides a title, icon, default semantic blocks, and tags.

import Foundation

// MARK: - ChurchNoteTemplate

enum ChurchVisitNoteTemplate: String, CaseIterable, Identifiable {
    case preVisit           = "preVisit"
    case sermonCapture      = "sermonCapture"
    case postVisitReflection = "postVisitReflection"
    case returnDecision     = "returnDecision"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preVisit:            return "Pre-Visit Intentions"
        case .sermonCapture:       return "Sermon Capture"
        case .postVisitReflection: return "Post-Visit Reflection"
        case .returnDecision:      return "Return Decision"
        }
    }

    var icon: String {
        switch self {
        case .preVisit:            return "thought.bubble"
        case .sermonCapture:       return "text.quote"
        case .postVisitReflection: return "heart.text.clipboard"
        case .returnDecision:      return "arrow.uturn.backward.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .preVisit:            return "Set your prayer intention and expectations"
        case .sermonCapture:       return "Key scriptures, takeaways, and action steps"
        case .postVisitReflection: return "Reflect on your visit experience"
        case .returnDecision:      return "Decide if this church is right for you"
        }
    }

    var defaultTags: [String] {
        switch self {
        case .preVisit:            return ["pre-visit", "intentions", "prayer"]
        case .sermonCapture:       return ["sermon", "notes", "scripture"]
        case .postVisitReflection: return ["reflection", "post-visit"]
        case .returnDecision:      return ["decision", "next-steps"]
        }
    }

    var defaultBlocks: [ChurchNoteBlock] {
        switch self {
        case .preVisit:
            return [
                ChurchNoteBlock(type: .reflection, text: ""),
                ChurchNoteBlock(type: .prayer, text: ""),
                ChurchNoteBlock(type: .reflection, text: ""),
                ChurchNoteBlock(type: .paragraph, text: ""),
            ]

        case .sermonCapture:
            return [
                ChurchNoteBlock(type: .paragraph, text: ""),
                ChurchNoteBlock(type: .scripture, text: ""),
                ChurchNoteBlock(type: .takeaway, text: ""),
                ChurchNoteBlock(type: .takeaway, text: ""),
                ChurchNoteBlock(type: .takeaway, text: ""),
                ChurchNoteBlock(type: .action, text: ""),
                ChurchNoteBlock(type: .prayer, text: ""),
            ]

        case .postVisitReflection:
            return [
                ChurchNoteBlock(type: .reflection, text: ""),
                ChurchNoteBlock(type: .takeaway, text: ""),
                ChurchNoteBlock(type: .reflection, text: ""),
                ChurchNoteBlock(type: .prayer, text: ""),
            ]

        case .returnDecision:
            return [
                ChurchNoteBlock(type: .reflection, text: ""),
                ChurchNoteBlock(type: .reflection, text: ""),
                ChurchNoteBlock(type: .action, text: ""),
            ]
        }
    }

    /// Placeholder prompts for each block — shown as placeholder text in the editor.
    var blockPlaceholders: [String] {
        switch self {
        case .preVisit:
            return [
                "Why I chose this church…",
                "My prayer intention for this visit…",
                "What I hope to find…",
                "Questions or concerns…",
            ]

        case .sermonCapture:
            return [
                "Sermon title / topic…",
                "Key scripture reference…",
                "Takeaway 1…",
                "Takeaway 2…",
                "Takeaway 3…",
                "My action step this week…",
                "Prayer response…",
            ]

        case .postVisitReflection:
            return [
                "How I felt during the service…",
                "A key moment that stood out…",
                "Would I return? Why or why not…",
                "Prayer response…",
            ]

        case .returnDecision:
            return [
                "Did I feel welcomed?",
                "Do I want to connect further?",
                "My next step…",
            ]
        }
    }

    /// Creates a pre-populated `ChurchNote` for the given church and user.
    func createNote(
        userId: String,
        churchId: String?,
        churchName: String?,
        visitPlanId: String? = nil
    ) -> ChurchNote {
        let noteTitle: String
        if let churchName, !churchName.isEmpty {
            noteTitle = "\(churchName) — \(title)"
        } else {
            noteTitle = title
        }

        // Pre-fill block text with placeholder prompts
        var blocks = defaultBlocks
        let placeholders = blockPlaceholders
        for i in blocks.indices where i < placeholders.count {
            blocks[i].text = placeholders[i]
        }

        return ChurchNote(
            userId: userId,
            title: noteTitle,
            churchName: churchName,
            churchId: churchId,
            date: Date(),
            content: "",
            tags: defaultTags,
            visitPlanId: visitPlanId,
            blocks: blocks
        )
    }
}
