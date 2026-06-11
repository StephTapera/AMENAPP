import SwiftUI

// MARK: - Models

enum DetectedPostContextType {
    case link, music, book, podcast, place, date, sensitiveSignal, intent, topicTag, audienceRisk, linkTrust

    var icon: String {
        switch self {
        case .link:            return "link"
        case .music:           return "music.note"
        case .book:            return "book"
        case .podcast:         return "mic"
        case .place:           return "mappin.and.ellipse"
        case .date:            return "calendar"
        case .sensitiveSignal: return "exclamationmark.triangle"
        case .intent:          return "sparkles"
        case .topicTag:        return "tag"
        case .audienceRisk:    return "person.2.badge.gearshape"
        case .linkTrust:       return "checkmark.shield"
        }
    }

    var actionLabel: String {
        switch self {
        case .link:            return "Add Preview"
        case .music:           return "Attach Music"
        case .book:            return "Attach Book"
        case .podcast:         return "Attach Podcast"
        case .place:           return "Tag Place"
        case .date:            return "Create Reminder"
        case .sensitiveSignal: return "Review Content"
        case .intent:          return "Use Suggestion"
        case .topicTag:        return "Add Topic"
        case .audienceRisk:    return "Review Audience"
        case .linkTrust:       return "Review Link"
        }
    }

    var tint: Color {
        switch self {
        case .sensitiveSignal, .audienceRisk:
            return .orange
        case .linkTrust:
            return .blue
        default:
            return .secondary
        }
    }
}

struct DetectedPostContextItem: Identifiable {
    let id: UUID
    let type: DetectedPostContextType
    let displayText: String
    let rawValue: String
}

enum PostContextAction {
    case addLinkPreview, attachMusic, createReminder, saveAsMemory, addTopicTag, adjustAudience, dismiss
}

enum SmartComposerReviewSeverity {
    case info, note, warning, confirmation

    var icon: String {
        switch self {
        case .info:         return "info.circle"
        case .note:         return "sparkles"
        case .warning:      return "exclamationmark.triangle"
        case .confirmation: return "hand.raised"
        }
    }

    var tint: Color {
        switch self {
        case .info:         return .blue
        case .note:         return .secondary
        case .warning:      return .orange
        case .confirmation: return .orange
        }
    }
}

enum SmartComposerReviewAction: String, Identifiable {
    case makeFollowersOnly
    case limitRepliesToFollowers
    case addSensitiveWarning
    case openTopicTags
    case openLinkPreview
    case addVerseContext
    case continuePosting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .makeFollowersOnly:       return "Make followers only"
        case .limitRepliesToFollowers: return "Limit replies"
        case .addSensitiveWarning:     return "Add content warning"
        case .openTopicTags:           return "Choose topic"
        case .openLinkPreview:         return "Preview link"
        case .addVerseContext:         return "Add verse context"
        case .continuePosting:         return "Post anyway"
        }
    }
}

struct SmartComposerReviewNote: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: SmartComposerReviewSeverity
    let actions: [SmartComposerReviewAction]
}

// MARK: - View

struct SmartPostContextTray: View {
    let detectedItems: [DetectedPostContextItem]
    let onAction: (PostContextAction, DetectedPostContextItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: "smartPostContextEnabled") as? Bool) ?? true
    }

    var body: some View {
        if isEnabled && !detectedItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(detectedItems) { item in
                        chip(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.80)) {
                    appeared = true
                }
            }
            .onDisappear { appeared = false }
        }
    }

    private func chip(for item: DetectedPostContextItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.type.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.type.tint)

            Button {
                onAction(primaryAction(for: item.type), item)
            } label: {
                Text(item.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.type.actionLabel): \(item.displayText)")

            Button {
                onAction(.dismiss, item)
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 20, minHeight: 20)
            .accessibilityLabel("Dismiss \(item.displayText)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    item.type == .sensitiveSignal || item.type == .audienceRisk ? Color.orange.opacity(0.4) : Color.white.opacity(0.4),
                    lineWidth: 0.6
                )
        )
    }

    private func primaryAction(for type: DetectedPostContextType) -> PostContextAction {
        switch type {
        case .link:            return .addLinkPreview
        case .music:           return .attachMusic
        case .date:            return .createReminder
        case .sensitiveSignal: return .saveAsMemory
        case .topicTag:        return .addTopicTag
        case .audienceRisk:    return .adjustAudience
        case .linkTrust:       return .addLinkPreview
        default:               return .addLinkPreview
        }
    }
}

struct SmartComposerReviewSheet: View {
    let notes: [SmartComposerReviewNote]
    let requiresConfirmation: Bool
    let onAction: (SmartComposerReviewAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: note.severity.icon)
                                    .font(.systemScaled(15, weight: .semibold))
                                    .foregroundStyle(note.severity.tint)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                    Text(note.message)
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if !note.actions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(note.actions) { action in
                                            Button(action.title) {
                                                onAction(action)
                                            }
                                            .font(AMENFont.semiBold(12))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(.thinMaterial, in: Capsule())
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .navigationTitle(requiresConfirmation ? "Review Before Posting" : "Post Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
                if requiresConfirmation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Post anyway") {
                            onAction(.continuePosting)
                        }
                        .font(AMENFont.semiBold(15))
                    }
                }
            }
        }
    }
}
