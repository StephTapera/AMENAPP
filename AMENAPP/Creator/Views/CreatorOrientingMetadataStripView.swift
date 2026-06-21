// CreatorOrientingMetadataStripView.swift
// AMENAPP — Creator Spotlight / Wave 1
//
// Horizontal strip of opaque white metadata chips.
// NOT glass — metadata is read, not acted on.
// Hides entirely when metadata is nil.

import SwiftUI

struct CreatorOrientingMetadataStripView: View {

    let metadata: OrientingMetadata?

    var body: some View {
        if let metadata {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips(from: metadata), id: \.label) { chip in
                        MetadataChip(icon: chip.icon, label: chip.label)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Chip Assembly

    private struct ChipInfo {
        let icon: String
        let label: String
    }

    private func chips(from m: OrientingMetadata) -> [ChipInfo] {
        var result: [ChipInfo] = []

        for format in m.format {
            result.append(ChipInfo(icon: iconFor(format), label: labelFor(format)))
        }

        if let minutes = m.approximateLengthMinutes {
            result.append(ChipInfo(icon: "clock", label: "~\(minutes) min"))
        }

        for ref in m.scriptureReferences.prefix(3) {
            result.append(ChipInfo(icon: "text.book.closed", label: ref))
        }

        if let season = m.liturgicalSeason, season != .none {
            result.append(ChipInfo(icon: "calendar", label: labelFor(season)))
        }

        if let audience = m.audienceDescription, !audience.isEmpty {
            result.append(ChipInfo(icon: "person.2", label: audience))
        }

        return result
    }

    private func iconFor(_ format: ContentFormat) -> String {
        switch format {
        case .video:      return "play.rectangle"
        case .audio:      return "waveform"
        case .text:       return "doc.text"
        case .series:     return "rectangle.stack"
        case .studyGuide: return "book.closed"
        case .devotional: return "sun.horizon"
        case .prayer:     return "hands.sparkles"
        case .live:       return "dot.radiowaves.left.and.right"
        }
    }

    private func labelFor(_ format: ContentFormat) -> String {
        switch format {
        case .video:      return "Video"
        case .audio:      return "Audio"
        case .text:       return "Text"
        case .series:     return "Series"
        case .studyGuide: return "Study Guide"
        case .devotional: return "Devotional"
        case .prayer:     return "Prayer"
        case .live:       return "Live"
        }
    }

    private func labelFor(_ season: CreatorLiturgicalSeason) -> String {
        switch season {
        case .advent:       return "Advent"
        case .christmas:    return "Christmas"
        case .epiphany:     return "Epiphany"
        case .lent:         return "Lent"
        case .holyWeek:     return "Holy Week"
        case .easter:       return "Easter"
        case .pentecost:    return "Pentecost"
        case .ordinaryTime: return "Ordinary Time"
        case .none:         return ""
        }
    }
}

// MARK: - Chip Component

private struct MetadataChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.systemBackground), in: Capsule())
        .overlay(Capsule().stroke(Color(.separator).opacity(0.4), lineWidth: 1))
    }
}
