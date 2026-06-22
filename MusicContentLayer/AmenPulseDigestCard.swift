// AmenPulseDigestCard.swift
// AMENAPP — MusicContentLayer
//
// Enhanced Pulse digest card for the Faith + Music Content Layer.
// Liquid Glass, expandable sections, long-press context menu,
// "Why am I seeing this?" popover, mute animation.
// Accessible: Dynamic Type, Reduced Motion, Reduced Transparency, VoiceOver.

import SwiftUI

// MARK: - PulseDigestItemType

enum PulseDigestItemType: String, Codable, Sendable, CaseIterable {
    case newMusic          = "new_music"
    case sermon            = "sermon"
    case churchNote        = "church_note"
    case prayerUpdate      = "prayer_update"
    case event             = "event"
    case listeningRoom     = "listening_room"
    case communityActivity = "community_activity"
    case scripture         = "scripture"
    case trending          = "trending"
    case followUp          = "follow_up"
    case memberOnly        = "member_only"

    var icon: String {
        switch self {
        case .newMusic:          return "music.note"
        case .sermon:            return "mic.fill"
        case .churchNote:        return "note.text"
        case .prayerUpdate:      return "hands.and.sparkles.fill"
        case .event:             return "calendar"
        case .listeningRoom:     return "waveform"
        case .communityActivity: return "person.3.fill"
        case .scripture:         return "book.fill"
        case .trending:          return "chart.line.uptrend.xyaxis"
        case .followUp:          return "arrow.uturn.right.circle.fill"
        case .memberOnly:        return "star.fill"
        }
    }

    var displayLabel: String {
        switch self {
        case .newMusic:          return "New Music"
        case .sermon:            return "Sermon"
        case .churchNote:        return "Church Note"
        case .prayerUpdate:      return "Prayer Update"
        case .event:             return "Event"
        case .listeningRoom:     return "Listening Room"
        case .communityActivity: return "Community"
        case .scripture:         return "Scripture"
        case .trending:          return "Trending"
        case .followUp:          return "Follow-Up"
        case .memberOnly:        return "Members Only"
        }
    }
}

// MARK: - PulseDigestItem

struct PulseDigestItem: Codable, Sendable, Identifiable {
    let id: String
    let type: PulseDigestItemType
    let title: String
    let summary: String
    let sourceName: String
    let sourceArtworkURL: URL?
    let deepLink: String
    let reasonLabel: String     // "Why am I seeing this?"
    let isMemberOnly: Bool
    let publishedAt: String     // ISO 8601
}

// MARK: - PulseDigest

struct PulseDigest: Codable, Sendable, Identifiable {
    let id: String
    let digestType: String      // "daily", "weekly", "church", "community"
    let generatedAt: String     // ISO 8601
    let items: [PulseDigestItem]
    let greetingText: String
}

// MARK: - Source Artwork

private struct SourceArtworkView: View {
    let url: URL?
    let fallbackIcon: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .overlay {
                Image(systemName: fallbackIcon)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.28)
                    .foregroundStyle(Color.accentColor)
            }
    }
}

// MARK: - Digest Item Row

private struct DigestItemRow: View {
    let item: PulseDigestItem
    let onTap: (PulseDigestItem) -> Void
    let onMute: (PulseDigestItem) -> Void

    @State private var showReasonPopover = false

    var body: some View {
        Button {
            onTap(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                SourceArtworkView(
                    url: item.sourceArtworkURL,
                    fallbackIcon: item.type.icon,
                    size: 36
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if item.isMemberOnly {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Members only")
                        }
                    }

                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        typePill(for: item.type)
                        Text(item.sourceName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title) from \(item.sourceName)\(item.isMemberOnly ? ", members only" : "")")
        .accessibilityHint("Double-tap to open")
        .contextMenu {
            Button {
                onTap(item)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button {
                // Save for later — caller handles persistence
            } label: {
                Label("Save for Later", systemImage: "bookmark")
            }
            Button {
                showReasonPopover = true
            } label: {
                Label("Why am I seeing this?", systemImage: "questionmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                onMute(item)
            } label: {
                Label("Mute this source", systemImage: "speaker.slash.fill")
            }
        }
        .popover(isPresented: $showReasonPopover) {
            reasonPopover
        }
    }

    @ViewBuilder
    private func typePill(for type: PulseDigestItemType) -> some View {
        Label(type.displayLabel, systemImage: type.icon)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            .foregroundStyle(Color.accentColor)
    }

    private var reasonPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why am I seeing this?", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(item.reasonLabel)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 280)
        .presentationCompactAdaptation(.popover)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Digest Section

private struct DigestSection: View {
    let type: PulseDigestItemType
    let items: [PulseDigestItem]
    let onTap: (PulseDigestItem) -> Void
    let onMute: (PulseDigestItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isExpanded = false
    private let defaultVisible = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader

            let visible = isExpanded ? items : Array(items.prefix(defaultVisible))
            ForEach(visible) { item in
                DigestItemRow(item: item, onTap: onTap, onMute: onMute)
                if item.id != visible.last?.id {
                    Divider().opacity(0.3)
                }
            }

            if items.count > defaultVisible {
                showMoreButton
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: type.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(type.displayLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer(minLength: 0)
            Text("\(items.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.displayLabel) section, \(items.count) items")
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var showMoreButton: some View {
        let remaining = items.count - defaultVisible
        Button {
            if reduceMotion {
                isExpanded.toggle()
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? "Show less" : "Show \(remaining) more")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show less items" : "Show \(remaining) more items")
    }
}

// MARK: - AmenPulseDigestCard

struct AmenPulseDigestCard: View {
    let digest: PulseDigest
    let onItemTap: (PulseDigestItem) -> Void
    let onMute: (PulseDigestItem) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var mutedItemIDs: Set<String> = []

    // Group items by type, filtering muted
    private var grouped: [(type: PulseDigestItemType, items: [PulseDigestItem])] {
        let visible = digest.items.filter { !mutedItemIDs.contains($0.id) }
        let order: [PulseDigestItemType] = PulseDigestItemType.allCases
        return order.compactMap { type in
            let typeItems = visible.filter { $0.type == type }
            return typeItems.isEmpty ? nil : (type: type, items: typeItems)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Divider().opacity(contrast == .increased ? 1 : 0.35)
            cardBody
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    contrast == .increased
                        ? Color.primary.opacity(0.45)
                        : Color.white.opacity(0.18),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(digest.greetingText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            HStack {
                Text("Today's Pulse")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                digestTypePill
            }

            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var digestTypePill: some View {
        Text(digest.digestType.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.accentColor.opacity(0.13)))
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("\(digest.digestType) digest")
    }

    private var formattedDate: String {
        // Surface the raw ISO string trimmed to the date portion for display
        String(digest.generatedAt.prefix(10))
    }

    // MARK: Body

    @ViewBuilder
    private var cardBody: some View {
        if grouped.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(grouped, id: \.type) { section in
                        DigestSection(
                            type: section.type,
                            items: section.items,
                            onTap: onItemTap,
                            onMute: handleMute
                        )
                        if section.type != grouped.last?.type {
                            Divider().opacity(0.25)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing new right now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .accessibilityLabel("No pulse items")
    }

    // MARK: Mute

    private func handleMute(_ item: PulseDigestItem) {
        if reduceMotion {
            mutedItemIDs.insert(item.id)
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                mutedItemIDs.insert(item.id)
            }
        }
        onMute(item)
    }

    // MARK: Backgrounds

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}

// MARK: - Preview

#Preview("Pulse Digest Card") {
    let items: [PulseDigestItem] = [
        PulseDigestItem(
            id: "1", type: .newMusic,
            title: "Elevation Worship drops new live album",
            summary: "\"Graves Into Gardens\" live recording now available.",
            sourceName: "Elevation Worship",
            sourceArtworkURL: nil,
            deepLink: "amen://music/elevation-1",
            reasonLabel: "You follow Elevation Worship and listened to them last week.",
            isMemberOnly: false,
            publishedAt: "2026-06-10T09:00:00Z"
        ),
        PulseDigestItem(
            id: "2", type: .sermon,
            title: "The God Who Sees — Pastor S. Furtick",
            summary: "A message from Elevation Church on Hagar's encounter with God.",
            sourceName: "Elevation Church",
            sourceArtworkURL: nil,
            deepLink: "amen://sermon/furtick-sees",
            reasonLabel: "Your church recently shared content from Elevation Church.",
            isMemberOnly: false,
            publishedAt: "2026-06-10T08:00:00Z"
        ),
        PulseDigestItem(
            id: "3", type: .prayerUpdate,
            title: "Marcus shared a prayer update",
            summary: "He shared good news about his health this morning.",
            sourceName: "Marcus T.",
            sourceArtworkURL: nil,
            deepLink: "amen://prayer/marcus-1",
            reasonLabel: "You prayed for Marcus last week.",
            isMemberOnly: false,
            publishedAt: "2026-06-10T07:30:00Z"
        ),
        PulseDigestItem(
            id: "4", type: .memberOnly,
            title: "Exclusive: Monthly Members Worship Night",
            summary: "Join us this Friday for a members-only worship session.",
            sourceName: "Cornerstone Fellowship",
            sourceArtworkURL: nil,
            deepLink: "amen://event/members-worship",
            reasonLabel: "You are a member of Cornerstone Fellowship.",
            isMemberOnly: true,
            publishedAt: "2026-06-10T07:00:00Z"
        )
    ]
    let digest = PulseDigest(
        id: "digest-today",
        digestType: "daily",
        generatedAt: "2026-06-10T06:00:00Z",
        items: items,
        greetingText: "Good morning, Steph 👋"
    )
    return ScrollView {
        AmenPulseDigestCard(
            digest: digest,
            onItemTap: { _ in },
            onMute: { _ in }
        )
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
