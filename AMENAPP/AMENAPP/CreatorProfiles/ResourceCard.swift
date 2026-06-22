// ResourceCard.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// One resource card. White bg / black primary text; translucent glass card (single layer,
// NO glass-on-glass — the card is glass, its inner chips are flat surfaceChip).
//
// Tap behaviour (CRITICAL HONESTY):
//   - link / externalUrl resources open the URL.
//   - fileRef resources open ONLY when `fileRef.isServable` (moderation == .approved).
//     Otherwise the card renders a calm "Processing / unavailable" state and is NOT tappable
//     to content — we never present unapproved media as if it were ready.
//
// Conventions: AmenTheme.Colors.* + Color(hex:) tokens only; Dynamic Type (text styles);
// VoiceOver label + hint on the actionable card; reduce-motion safe (no implicit animation).

import SwiftUI

struct CreatorHubResourceCard: View {
    let resource: CreatorHubResource
    /// Invoked with a resolvable URL when the resource is openable.
    var onOpen: (URL) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    // MARK: Derived state

    /// A resolvable destination, honouring moderation for file-backed resources.
    private var openURL: URL? {
        if let ext = resource.externalUrl, let url = URL(string: ext) {
            return url
        }
        // File-backed resources only resolve when MEDIA-GATE / moderation approved them.
        if let file = resource.fileRef, file.isServable, let url = URL(string: file.storagePath) {
            return url
        }
        return nil
    }

    /// File exists but is not yet approved → honest "processing" state.
    private var isProcessing: Bool {
        resource.externalUrl == nil
            && resource.fileRef != nil
            && !(resource.fileRef?.isServable ?? false)
    }

    private var isOpenable: Bool { openURL != nil }

    // MARK: Body

    var body: some View {
        Group {
            if isOpenable {
                Button {
                    if let url = openURL { onOpen(url) }
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .amenGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isOpenable ? .isButton : [])
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 6) {
                Text(resource.title)
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(kindLabel)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                if !resource.topics.isEmpty {
                    topicChips
                }

                if isProcessing {
                    processingPill
                }
            }

            Spacer(minLength: 0)

            if isOpenable {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
                .frame(width: 48, height: 48)
            Image(systemName: kindIcon)
                .font(.title3)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .accessibilityHidden(true)
    }

    private var topicChips: some View {
        // Flat chips inside the glass card — never glass-on-glass.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(resource.topics, id: \.self) { topic in
                    Text(topic)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(AmenTheme.Colors.surfaceChip)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var processingPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.questionmark")
                .font(.caption)
            Text("Processing — not yet available")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(AmenTheme.Colors.statusWarning)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(AmenTheme.Colors.statusWarning.opacity(0.12))
        )
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    // MARK: Labels

    private var kindLabel: String {
        switch resource.kind {
        case .pdf:         return "PDF"
        case .book:        return "Book"
        case .worksheet:   return "Worksheet"
        case .slides:      return "Slides"
        case .devotional:  return "Devotional"
        case .readingPlan: return "Reading plan"
        case .studyGuide:  return "Study guide"
        case .course:      return "Course"
        case .link:        return "Link"
        }
    }

    private var kindIcon: String {
        switch resource.kind {
        case .pdf:         return "doc.richtext"
        case .book:        return "book.closed"
        case .worksheet:   return "list.bullet.rectangle"
        case .slides:      return "rectangle.on.rectangle"
        case .devotional:  return "sun.max"
        case .readingPlan: return "calendar"
        case .studyGuide:  return "text.book.closed"
        case .course:      return "graduationcap"
        case .link:        return "link"
        }
    }

    private var accessibilityLabel: String {
        "\(kindLabel). \(resource.title)"
    }

    private var accessibilityHint: String {
        if isProcessing { return "Processing. Not yet available." }
        if isOpenable { return "Opens the resource." }
        return "Unavailable."
    }
}

#if DEBUG
#Preview("ResourceCard") {
    ScrollView {
        VStack(spacing: 12) {
            CreatorHubResourceCard(resource: CreatorHubResource(
                id: "1", creatorId: "c", kind: .readingPlan,
                title: "30-Day Psalms Reading Plan",
                fileRef: nil, externalUrl: "https://example.com",
                topics: ["Prayer", "Psalms", "Devotion"]
            ))
            CreatorHubResourceCard(resource: CreatorHubResource(
                id: "2", creatorId: "c", kind: .pdf,
                title: "Study Guide (processing)",
                fileRef: CreatorHubMediaRef(
                    kind: .image, storagePath: "gs://x", aspectRatio: nil,
                    durationSec: nil, moderation: .pending
                ),
                externalUrl: nil, topics: ["Romans"]
            ))
        }
        .padding(16)
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
