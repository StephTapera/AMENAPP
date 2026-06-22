// CreatorContentCapabilityBadgesView.swift
// AMENAPP — Creator Spotlight / Wave 1
//
// "What's inside" grid of available content capability badges.
// Green tint — green = state/capability in the two-accent system.
// Only shows capabilities where available == true.

import SwiftUI

struct CreatorContentCapabilityBadgesView: View {

    let capabilities: [ContentCapability]

    private var available: [ContentCapability] {
        capabilities.filter { $0.available }
    }

    var body: some View {
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What's Inside")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)

                // Wrapping layout via LazyVGrid with adaptive columns
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(available, id: \.kind) { capability in
                        CapabilityBadge(kind: capability.kind)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Individual Badge

private struct CapabilityBadge: View {

    let kind: ContentCapabilityKind

    private static let green = Color(red: 0.13, green: 0.62, blue: 0.34)

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Self.green)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Self.green.opacity(0.2), lineWidth: 1)
        )
    }

    private var icon: String {
        switch kind {
        case .studyGuide:            return "book.closed"
        case .audio:                 return "waveform"
        case .groupReady:            return "person.3"
        case .originalLanguageNotes: return "character.book.closed.he"
        case .worksWithBerean:       return "sparkles"
        case .transcripts:           return "doc.text"
        case .captions:              return "captions.bubble"
        case .signLanguage:          return "hands.sparkles"
        case .discussionGuide:       return "bubble.left.and.bubble.right"
        case .prayerGuide:           return "hands.sparkles.fill"
        case .downloadable:          return "arrow.down.circle"
        }
    }

    private var label: String {
        switch kind {
        case .studyGuide:            return "Study Guide"
        case .audio:                 return "Audio"
        case .groupReady:            return "Group Ready"
        case .originalLanguageNotes: return "Original Language"
        case .worksWithBerean:       return "Ask Berean"
        case .transcripts:           return "Transcript"
        case .captions:              return "Captions"
        case .signLanguage:          return "Sign Language"
        case .discussionGuide:       return "Discussion Guide"
        case .prayerGuide:           return "Prayer Guide"
        case .downloadable:          return "Downloadable"
        }
    }
}
