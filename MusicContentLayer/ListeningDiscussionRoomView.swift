// ListeningDiscussionRoomView.swift
// AMENAPP — MusicContentLayer
//
// Full Listening + Discussion Room screen and compact card.
// Liquid Glass surfaces, accessible, Reduced Motion / Transparency aware.

import SwiftUI

// MARK: - ListeningRoomType

enum ListeningRoomType: String, Codable, Sendable, CaseIterable {
    case songRelease        = "song_release"
    case albumListening     = "album_listening"
    case sermonDiscussion   = "sermon_discussion"
    case worshipNight       = "worship_night"
    case bibleStudy         = "bible_study"
    case churchNoteDiscussion = "church_note_discussion"
    case prayerRoom         = "prayer_room"
    case eventRoom          = "event_room"

    var displayLabel: String {
        switch self {
        case .songRelease:          return "Song Release"
        case .albumListening:       return "Album Listening"
        case .sermonDiscussion:     return "Sermon Discussion"
        case .worshipNight:         return "Worship Night"
        case .bibleStudy:           return "Bible Study"
        case .churchNoteDiscussion: return "Church Note"
        case .prayerRoom:           return "Prayer Room"
        case .eventRoom:            return "Event Room"
        }
    }

    var icon: String {
        switch self {
        case .songRelease:          return "music.note"
        case .albumListening:       return "square.stack.fill"
        case .sermonDiscussion:     return "mic.fill"
        case .worshipNight:         return "music.quarternote.3"
        case .bibleStudy:           return "book.fill"
        case .churchNoteDiscussion: return "note.text"
        case .prayerRoom:           return "hands.and.sparkles.fill"
        case .eventRoom:            return "calendar"
        }
    }
}

// MARK: - RoomMessageType

enum RoomMessageType: String, Codable, Sendable, CaseIterable {
    case comment   = "comment"
    case prayer    = "prayer"
    case scripture = "scripture"
    case poll      = "poll"
    case pinned    = "pinned"
}

// MARK: - RoomMessage
// Note: ListeningRoom and ListeningRoomState are defined in MusicContentContracts.swift.
// This file defines the extended ListeningRoomSession and message models for the room UI.

struct ListeningRoomSession: Codable, Sendable, Identifiable {
    let id: String
    let type: ListeningRoomType
    let title: String
    let hostName: String
    let hostID: String
    let artworkURL: URL?
    let description: String?
    let attachedContentID: String?
    let scheduledAt: String?
    let startedAt: String?
    let endedAt: String?
    let attendeeCount: Int
    let isPublic: Bool
    let isPaidAccess: Bool
    let isMemberOnly: Bool
    // Uses ListeningRoomState from MusicContentContracts.swift
    let state: ListeningRoomState
}

struct RoomMessage: Codable, Sendable, Identifiable {
    let id: String
    let authorName: String
    let text: String
    let messageType: RoomMessageType
    let sentAt: String      // ISO 8601
}

// MARK: - Room State Badge

private struct RoomStateBadge: View {
    let state: ListeningRoomState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            if state == .live {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(isPulsing ? 0.4 : 1.0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
                    .accessibilityHidden(true)
            }
            Text(badgeLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(badgeColor)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(badgeColor.opacity(0.14)))
        .accessibilityLabel(accessibilityLabel)
    }

    private var badgeLabel: String {
        switch state {
        case .live:      return "Live"
        case .scheduled: return "Scheduled"
        case .ended:     return "Ended"
        case .cancelled: return "Cancelled"
        }
    }

    private var badgeColor: Color {
        switch state {
        case .live:      return .red
        case .scheduled: return .orange
        case .ended:     return .secondary
        case .cancelled: return .gray
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .live:      return "Live now"
        case .scheduled: return "Scheduled"
        case .ended:     return "Room ended"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Room Artwork

private struct RoomArtworkView: View {
    let url: URL?
    let type: ListeningRoomType
    let size: CGFloat

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: type.icon)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.24)
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - RoomMessage Row

private struct RoomMessageRow: View {
    let message: RoomMessage

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        switch message.messageType {
        case .pinned:
            pinnedBanner
        case .scripture:
            scripturePill
        default:
            standardBubble
        }
    }

    private var standardBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.messageType == .prayer {
                Text("🙏")
                    .font(.subheadline)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(message.authorName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(bubbleBorderColor, lineWidth: contrast == .increased ? 1.5 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.authorName): \(message.text)")
    }

    private var scripturePill: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.authorName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.indigo)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.indigo.opacity(0.1)))
        .overlay(Capsule().strokeBorder(Color.indigo.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scripture from \(message.authorName): \(message.text)")
    }

    private var pinnedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pinned")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            reduceTransparency
                ? AnyView(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground)))
                : AnyView(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.08))))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pinned message: \(message.text)")
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.messageType == .prayer {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.purple.opacity(0.10)))
            }
        } else {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06)))
            }
        }
    }

    private var bubbleBorderColor: Color {
        let opacity = contrast == .increased ? 0.4 : 0.18
        if message.messageType == .prayer {
            return Color.purple.opacity(opacity)
        }
        return Color.white.opacity(opacity)
    }
}

// MARK: - ListeningDiscussionRoomView

struct ListeningDiscussionRoomView: View {
    let room: ListeningRoomSession
    let isHost: Bool
    let isModerator: Bool
    var messages: [RoomMessage] = []
    var onSendMessage: ((String, RoomMessageType) -> Void)?
    var onEndRoom: (() -> Void)?
    var onPinMessage: ((RoomMessage) -> Void)?
    var onMuteParticipant: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var composerText: String = ""
    @State private var selectedMessageType: RoomMessageType = .comment
    @State private var showEndRoomConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(contrast == .increased ? 1 : 0.4)
            contentSection
            if room.state == .live {
                Divider().opacity(contrast == .increased ? 1 : 0.4)
                composerSection
            }
        }
        .background(pageBackground)
        .confirmationDialog(
            "End this room?",
            isPresented: $showEndRoomConfirm,
            titleVisibility: .visible
        ) {
            Button("End Room", role: .destructive) { onEndRoom?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will close the room for all participants.")
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                RoomArtworkView(url: room.artworkURL, type: room.type, size: 64)
                    .accessibilityLabel("\(room.type.displayLabel) artwork")

                VStack(alignment: .leading, spacing: 6) {
                    Text(room.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 8) {
                        typePill
                        RoomStateBadge(state: room.state)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("\(room.attendeeCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(room.attendeeCount) attendees")

                        Text("·")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)

                        Text("Hosted by \(room.hostName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let description = room.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .background(headerBackground)
    }

    private var typePill: some View {
        Label(room.type.displayLabel, systemImage: room.type.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.13)))
            .foregroundStyle(Color.accentColor)
    }

    // MARK: Content

    @ViewBuilder
    private var contentSection: some View {
        switch room.state {
        case .scheduled:
            scheduledPlaceholder
        case .live, .ended:
            liveOrEndedContent
        case .cancelled:
            cancelledPlaceholder
        }
    }

    private var scheduledPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Room not started yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let scheduledAt = room.scheduledAt {
                Text("Scheduled: \(scheduledAt)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Room scheduled\(room.scheduledAt.map { " for \($0)" } ?? "")")
    }

    private var cancelledPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Room cancelled")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityLabel("Room was cancelled")
    }

    private var liveOrEndedContent: some View {
        VStack(spacing: 0) {
            if room.state == .ended {
                endedBanner
                Divider().opacity(contrast == .increased ? 1 : 0.4)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        RoomMessageRow(message: message)
                            .contextMenu {
                                if isHost || isModerator {
                                    Button {
                                        onPinMessage?(message)
                                    } label: {
                                        Label("Pin Message", systemImage: "pin.fill")
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if isHost || isModerator {
                moderatorControls
            }
        }
    }

    private var endedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Room ended")
                    .font(.subheadline.weight(.semibold))
                if let endedAt = room.endedAt {
                    Text(endedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Room ended\(room.endedAt.map { " at \($0)" } ?? "")")
    }

    // MARK: Moderator Controls

    private var moderatorControls: some View {
        HStack(spacing: 12) {
            controlButton(label: "Pin", icon: "pin.fill", tint: .orange) {}
            controlButton(label: "Mute", icon: "mic.slash.fill", tint: .red) {
                onMuteParticipant?()
            }
            if isHost {
                Spacer(minLength: 0)
                controlButton(label: "End Room", icon: "stop.circle.fill", tint: .red) {
                    showEndRoomConfirm = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(moderatorBarBackground)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controlButton(
        label: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(tint.opacity(0.12)))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Composer

    private var composerSection: some View {
        HStack(spacing: 10) {
            messageTypePicker

            TextField("Add a message…", text: $composerText, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .accessibilityLabel("Message text field")

            Button {
                let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSendMessage?(trimmed, selectedMessageType)
                composerText = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary
                        : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(composerBackground)
    }

    private var messageTypePicker: some View {
        Menu {
            ForEach([RoomMessageType.comment, .prayer, .scripture], id: \.self) { type in
                Button {
                    selectedMessageType = type
                } label: {
                    Label(type.displayLabel, systemImage: type.icon)
                }
            }
        } label: {
            Image(systemName: selectedMessageType.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Message type: \(selectedMessageType.displayLabel)")
    }

    // MARK: Backgrounds

    @ViewBuilder
    private var pageBackground: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if reduceTransparency {
            Color(uiColor: .secondarySystemBackground)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.04)))
        }
    }

    @ViewBuilder
    private var moderatorBarBackground: some View {
        if reduceTransparency {
            Color(uiColor: .secondarySystemBackground)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.04)))
        }
    }

    @ViewBuilder
    private var composerBackground: some View {
        if reduceTransparency {
            Color(uiColor: .secondarySystemBackground)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.05)))
        }
    }
}

// MARK: - RoomMessageType display helpers

private extension RoomMessageType {
    var displayLabel: String {
        switch self {
        case .comment:   return "Comment"
        case .prayer:    return "Prayer"
        case .scripture: return "Scripture"
        case .poll:      return "Poll"
        case .pinned:    return "Pinned"
        }
    }

    var icon: String {
        switch self {
        case .comment:   return "bubble.right.fill"
        case .prayer:    return "hands.and.sparkles.fill"
        case .scripture: return "book.fill"
        case .poll:      return "chart.bar.fill"
        case .pinned:    return "pin.fill"
        }
    }
}

// MARK: - ListeningRoomCard

struct ListeningRoomCard: View {
    let room: ListeningRoomSession
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var isPulsing = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoomArtworkView(url: room.artworkURL, type: room.type, size: 52)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(room.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text("by \(room.hostName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        typePill
                        liveDot
                        attendeeCount
                    }
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        contrast == .increased
                            ? Color.primary.opacity(0.4)
                            : Color.white.opacity(0.18),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
            }
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to enter room")
        .accessibilityAddTraits(.isButton)
    }

    private var typePill: some View {
        Label(room.type.displayLabel, systemImage: room.type.icon)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var liveDot: some View {
        if room.state == .live {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 0.3 : 1.0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
                    .accessibilityHidden(true)
                Text("Live")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
            }
        }
    }

    private var attendeeCount: some View {
        Label("\(room.attendeeCount)", systemImage: "person.2.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(room.attendeeCount) attendees")
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
        }
    }

    private var accessibilityLabel: String {
        var parts = [room.title, "by \(room.hostName)", room.type.displayLabel]
        if room.state == .live { parts.append("Live now") }
        parts.append("\(room.attendeeCount) attendees")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("Listening Room Card") {
    let session = ListeningRoomSession(
        id: "room-1",
        type: .worshipNight,
        title: "Sunday Worship Night with Elevation",
        hostName: "Pastor Jordan",
        hostID: "host-123",
        artworkURL: nil,
        description: "Join us as we worship together.",
        attachedContentID: nil,
        scheduledAt: nil,
        startedAt: "2026-06-10T19:00:00Z",
        endedAt: nil,
        attendeeCount: 134,
        isPublic: true,
        isPaidAccess: false,
        isMemberOnly: false,
        state: .live
    )
    return ScrollView {
        VStack(spacing: 12) {
            ListeningRoomCard(room: session, onTap: {})
            ListeningRoomCard(
                room: ListeningRoomSession(
                    id: "room-2",
                    type: .bibleStudy,
                    title: "Romans Deep Dive — Week 3",
                    hostName: "Sis. Angela",
                    hostID: "host-456",
                    artworkURL: nil,
                    description: nil,
                    attachedContentID: nil,
                    scheduledAt: "2026-06-12T18:00:00Z",
                    startedAt: nil,
                    endedAt: nil,
                    attendeeCount: 28,
                    isPublic: true,
                    isPaidAccess: false,
                    isMemberOnly: false,
                    state: .scheduled
                ),
                onTap: {}
            )
        }
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
