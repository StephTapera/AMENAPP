// PostEngagementView.swift
// AMENAPP
//
// Replaces shallow like/comment counts with meaningful engagement interactions.
// Used as the footer/action bar on every post card.

import SwiftUI

// MARK: - Engagement Action

enum EngagementAction: String, CaseIterable {
    case illuminate              // private, no public count
    case reply                   // opens reply composer
    case save                    // saves to notes/bookmarks
    case reflect                 // opens private reflection composer
    case askBerean               // opens Berean AI with post context
    case shareSmartly            // share with source preserved
    case takeNotes               // opens note-taking for teaching posts
    case planVisit               // for church posts
    case encouragePrivately      // private encouragement message

    var icon: String {
        switch self {
        case .illuminate:          return "sun.max"
        case .reply:               return "bubble.right"
        case .save:                return "bookmark"
        case .reflect:             return "pencil.and.outline"
        case .askBerean:           return "sparkles"
        case .shareSmartly:        return "square.and.arrow.up"
        case .takeNotes:           return "note.text"
        case .planVisit:           return "mappin.and.ellipse"
        case .encouragePrivately:  return "heart.text.square"
        }
    }

    var label: String {
        switch self {
        case .illuminate:          return "Illuminate"
        case .reply:               return "Reply"
        case .save:                return "Save"
        case .reflect:             return "Reflect"
        case .askBerean:           return "Ask Berean"
        case .shareSmartly:        return "Share"
        case .takeNotes:           return "Take Notes"
        case .planVisit:           return "Plan Visit"
        case .encouragePrivately:  return "Encourage"
        }
    }
}

// MARK: - Smart Engagement Signals

struct SmartEngagementSignals {
    static func publicLabels(for postIntent: String) -> [String] {
        switch postIntent {
        case "reflection", "testimony":
            return ["Many were encouraged", "Saved to notes", "Active discussion"]
        case "sermonClip", "teaching":
            return ["Saved to notes", "Notes taken", "Active discussion"]
        case "churchEvent", "announcement":
            return ["Visits planned", "Saved to notes"]
        case "prayer":
            return ["Many were encouraged", "Prayers offered"]
        case "question":
            return ["Active discussion", "Thoughtful replies"]
        default:
            return []
        }
    }
}

// MARK: - Engagement Chip

private struct EngagementChip: View {
    let action: EngagementAction
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(action.label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.75))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(isPressed ? 0.35 : 0.55))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        ._onButtonGesture(pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Post Smart Signal Strip

struct PostSmartSignalStrip: View {
    let signals: [String]

    var body: some View {
        if !signals.isEmpty {
            let visibleSignals = Array(signals.prefix(3))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleSignals, id: \.self) { signal in
                        Text(signal)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.04))
                            )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Post Engagement Bar

struct PostEngagementBar: View {
    let postId: String
    let postIntent: String
    let accountType: String
    let onAction: (EngagementAction) -> Void

    private var primaryActions: [EngagementAction] {
        switch postIntent {
        case "reflection", "testimony":
            return [.illuminate, .reply, .save, .reflect]
        case "sermonClip", "teaching":
            return [.takeNotes, .reflect, .askBerean, .save]
        case "churchEvent", "announcement":
            return [.planVisit, .save, .reply, .shareSmartly]
        case "prayer":
            return [.encouragePrivately, .save, .reply]
        case "question":
            return [.reply, .reflect, .askBerean, .shareSmartly]
        default:
            return [.illuminate, .reply, .save, .shareSmartly]
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primaryActions, id: \.rawValue) { action in
                    EngagementChip(action: action) {
                        onAction(action)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Post Engagement View (Combined)

struct PostEngagementView: View {
    let postId: String
    let postIntent: String
    let accountType: String
    let signals: [String]
    let onAction: (EngagementAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PostSmartSignalStrip(signals: signals)

            PostEngagementBar(
                postId: postId,
                postIntent: postIntent,
                accountType: accountType,
                onAction: onAction
            )
        }
    }
}

// MARK: - Preview

#Preview("Reflection Post") {
    ZStack {
        Color(white: 0.96).ignoresSafeArea()
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("reflection / testimony")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PostEngagementView(
                    postId: "post-001",
                    postIntent: "reflection",
                    accountType: "personal",
                    signals: SmartEngagementSignals.publicLabels(for: "reflection"),
                    onAction: { action in
                        print("Tapped: \(action.label)")
                    }
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.55))
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("sermonClip / teaching")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PostEngagementView(
                    postId: "post-002",
                    postIntent: "sermonClip",
                    accountType: "minister",
                    signals: SmartEngagementSignals.publicLabels(for: "sermonClip"),
                    onAction: { action in
                        print("Tapped: \(action.label)")
                    }
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.55))
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("church event / announcement")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PostEngagementView(
                    postId: "post-003",
                    postIntent: "announcement",
                    accountType: "church",
                    signals: SmartEngagementSignals.publicLabels(for: "announcement"),
                    onAction: { action in
                        print("Tapped: \(action.label)")
                    }
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.55))
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12)
            )
        }
        .padding()
    }
}
