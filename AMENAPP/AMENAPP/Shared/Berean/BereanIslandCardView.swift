// BereanIslandCardView.swift
// AMEN — Berean Island Wave 1
//
// IslandCardView: renders any IslandCard in its 6 kinds.
// Rules:
//   · 24 pt corner radius
//   · Flat (non-glass) surface — callers wrap in glass if needed
//   · VoiceOver custom-action rotor covers every action in the action row

import SwiftUI

// MARK: - IslandCardView

struct IslandCardView: View {
    let card: IslandCard
    let onAction: (IslandCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(card: card)
            CardBody(card: card)
            if !card.citations.isEmpty {
                CitationRow(citations: card.citations)
            }
            Divider()
            IslandActionRow(actions: card.actions, onAction: onAction)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        // VoiceOver: expose actions via the custom-action rotor so assistive
        // technology can reach them without swiping into the scroll view.
        // VoiceOver: card is a single element whose double-tap activates the first action
        // (typically Save). The custom-action rotor covers all remaining actions.
        .accessibilityElement(children: .contain)
        .accessibilityActivationPoint(CGPoint(x: 0.5, y: 0.5))
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            ForEach(card.actions, id: \.self) { action in
                Button(action.accessibilityLabel) { onAction(action) }
            }
        }
    }
}

// MARK: - Card Header

private struct CardHeader: View {
    let card: IslandCard

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KindBadge(kind: card.kind)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.header)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)

                if let src = card.sourceLine {
                    Text(src)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if card.aiAssisted {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("AI-assisted")
            }
        }
    }
}

private struct KindBadge: View {
    let kind: IslandCardKind

    var body: some View {
        kindIcon
            .font(.system(size: 17))
            .foregroundStyle(kindTint)
            .frame(width: 34, height: 34)
            .background(kindTint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var kindIcon: some View {
        switch kind {
        case .verse:  Image(systemName: "text.book.closed")
        case .answer: Image(systemName: "lightbulb")
        case .event:  Image(systemName: "calendar")
        case .sermon: Image(systemName: "mic")
        case .music:  Image(systemName: "music.note")
        case .link:   Image(systemName: "link")
        }
    }

    private var kindTint: Color {
        switch kind {
        case .verse:  return .indigo
        case .answer: return .orange
        case .event:  return .green
        case .sermon: return .purple
        case .music:  return .pink
        case .link:   return .blue
        }
    }
}

// MARK: - Card Body

private struct CardBody: View {
    let card: IslandCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.body)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)

            if let payload = card.payload {
                PayloadDetail(payload: payload)
            }
        }
    }
}

private struct PayloadDetail: View {
    let payload: IslandCardPayload

    var body: some View {
        switch payload {
        case .verse(let ref, let trans):
            Label("\(ref) · \(trans)", systemImage: "book")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

        case .event(_, let startsAt, let location):
            VStack(alignment: .leading, spacing: 3) {
                Label(formatted(startsAt), systemImage: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if let loc = location {
                    Label(loc, systemImage: "mappin")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

        case .sermon:
            Label("View sermon notes", systemImage: "note.text")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

        case .link(let url):
            Label(url.host() ?? url.absoluteString, systemImage: "link")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Citation Row

private struct CitationRow: View {
    let citations: [IslandCitation]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            ForEach(citations, id: \.reference) { cit in
                HStack(spacing: 6) {
                    Image(systemName: cit.verified ? "checkmark.seal.fill" : "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(cit.verified ? .green : .secondary)
                    Text("\(cit.reference) · \(cit.translation)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("\(cit.reference), \(cit.translation), \(cit.verified ? "verified" : "unverified")")
            }
        }
    }
}

// MARK: - Action Row

private struct IslandActionRow: View {
    let actions: [IslandCardAction]
    let onAction: (IslandCardAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    ActionChip(action: action) { onAction(action) }
                }
            }
        }
    }
}

private struct ActionChip: View {
    let action: IslandCardAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(action.displayLabel, systemImage: action.systemImage)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.displayLabel)
    }
}

// MARK: - IslandCardAction display helpers

extension IslandCardAction {
    var displayLabel: String {
        switch self {
        case .save:               return "Save"
        case .share:              return "Share"
        case .askFollowUp:        return "Ask More"
        case .addToCalendar:      return "Add to Calendar"
        case .rsvp:               return "RSVP"
        case .openNote:           return "Open Notes"
        case .compareTranslations: return "Compare"
        }
    }

    var systemImage: String {
        switch self {
        case .save:               return "bookmark"
        case .share:              return "square.and.arrow.up"
        case .askFollowUp:        return "arrow.turn.up.left"
        case .addToCalendar:      return "calendar.badge.plus"
        case .rsvp:               return "person.crop.circle.badge.checkmark"
        case .openNote:           return "note.text"
        case .compareTranslations: return "arrow.left.and.right"
        }
    }

    var accessibilityLabel: String { displayLabel }
}
