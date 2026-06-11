// ListeningDiscussionRoomView.swift
// AMENAPP — MusicContentLayer
//
// Live listening room models, service, card, and full-screen view.
// v1: sync is mocked. Upgrade path: LiveKit (project dep) or Firebase RTDB.

import SwiftUI

// MARK: - Models

enum ListeningRoomType: String, Codable, Sendable, CaseIterable {
    case songRelease, albumListening, sermonDiscussion, worshipNight
    case bibleStudy, churchNoteDiscussion, prayerRoom, eventRoom

    var displayName: String {
        switch self {
        case .songRelease: return "Song Release"; case .albumListening: return "Album Listening"
        case .sermonDiscussion: return "Sermon Discussion"; case .worshipNight: return "Worship Night"
        case .bibleStudy: return "Bible Study"; case .churchNoteDiscussion: return "Church Notes"
        case .prayerRoom: return "Prayer Room"; case .eventRoom: return "Event Room"
        }
    }

    var sfSymbol: String {
        switch self {
        case .songRelease: return "music.note"; case .albumListening: return "record.circle"
        case .sermonDiscussion: return "text.bubble"; case .worshipNight: return "music.mic"
        case .bibleStudy: return "book.closed"; case .churchNoteDiscussion: return "note.text"
        case .prayerRoom: return "hands.sparkles"; case .eventRoom: return "calendar.badge.plus"
        }
    }
}

struct ListeningRoomParticipant: Codable, Sendable, Identifiable {
    let id: String; let displayName: String; let avatarURL: URL?
    let isHost: Bool; let isModerator: Bool; let joinedAt: String
}

struct RoomPoll: Codable, Sendable, Identifiable {
    let id: String; let question: String; let options: [String]
    var votes: [String: Int]; let createdAt: String
}

struct ListeningRoom: Codable, Sendable, Identifiable {
    let id: String; let type: ListeningRoomType; let title: String
    let hostName: String; let hostID: String; let attachmentID: String?
    var state: String; let participantCount: Int; let isMembersOnly: Bool; let isPaid: Bool
    var polls: [RoomPoll]; var pinnedMessages: [String]
    let scheduledAt: String?; let endedAt: String?; let createdAt: String
}

// MARK: - Service

@MainActor final class ListeningRoomService: ObservableObject {
    @Published private(set) var currentRoom: ListeningRoom?
    @Published private(set) var participants: [ListeningRoomParticipant] = []
    @Published private(set) var liveMessages: [String] = []
    @Published private(set) var activePoll: RoomPoll?
    @Published private(set) var isLoading = false
    private static let maxMessages = 50

    func joinRoom(_ roomID: String) async {
        isLoading = true; defer { isLoading = false }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let fmt = ISO8601DateFormatter()
        currentRoom = ListeningRoom(
            id: roomID, type: .sermonDiscussion, title: "Sunday Sermon — John 15",
            hostName: "Pastor Marcus", hostID: "host-001", attachmentID: nil, state: "live",
            participantCount: 47, isMembersOnly: false, isPaid: false, polls: [],
            pinnedMessages: ["Welcome! Ask questions below."],
            scheduledAt: nil, endedAt: nil, createdAt: fmt.string(from: Date())
        )
        participants = [
            ListeningRoomParticipant(id: "host-001", displayName: "Pastor Marcus", avatarURL: nil, isHost: true, isModerator: true, joinedAt: fmt.string(from: Date().addingTimeInterval(-3600))),
            ListeningRoomParticipant(id: "mod-002", displayName: "Sister Alicia", avatarURL: nil, isHost: false, isModerator: true, joinedAt: fmt.string(from: Date().addingTimeInterval(-1800))),
            ListeningRoomParticipant(id: "user-003", displayName: "David K.", avatarURL: nil, isHost: false, isModerator: false, joinedAt: fmt.string(from: Date().addingTimeInterval(-600)))
        ]
        liveMessages = ["Pastor Marcus: Welcome, everyone! 🙏", "Sister Alicia: So glad to be here", "David K.: What does it mean to abide in the vine?"]
    }

    func leaveRoom() async { try? await Task.sleep(nanoseconds: 100_000_000); currentRoom = nil; participants = []; liveMessages = []; activePoll = nil }
    func sendMessage(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        var msgs = liveMessages; msgs.append("You: \(t)")
        if msgs.count > Self.maxMessages { msgs.removeFirst(msgs.count - Self.maxMessages) }
        liveMessages = msgs
    }
    func submitVote(pollID: String, option: String) { guard activePoll?.id == pollID else { return }; var p = activePoll; p?.votes[option, default: 0] += 1; activePoll = p }
    func endRoom() async {
        guard var room = currentRoom else { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
        room.state = "ended"; currentRoom = room
        liveMessages.append("— Room ended with \(participants.count) participants.")
    }
    var recapSummary: String { guard let r = currentRoom else { return "" }; return "\"\(r.title)\" wrapped up with \(r.participantCount) participants." }
}

// MARK: - ListeningRoomCard

struct ListeningRoomCard: View {
    let room: ListeningRoom; let onJoin: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var stateLabel: String { switch room.state { case "live": return "Live"; case "scheduled": return "Scheduled"; default: return "Ended" } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: room.type.sfSymbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.accentColor)
                }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Hosted by \(room.hostName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        if room.state == "live" { Circle().fill(Color.green).frame(width: 7, height: 7) }
                        Text(stateLabel).font(.caption2.weight(.semibold)).foregroundStyle(room.state == "live" ? Color.green : .secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule(style: .continuous).fill(Color(.secondarySystemFill)))
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill").font(.caption2)
                        Text("\(room.participantCount)").font(.caption2.weight(.medium))
                    }.foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 14).padding(.top, 12)

            Button(action: onJoin) {
                Text(room.state == "ended" ? "Replay" : "Join").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 36)
            }.buttonStyle(.borderedProminent).controlSize(.small).padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay { if !reduceTransparency { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.10)) } }
        }
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(contrast == .increased ? 0.50 : 0.28), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.title), hosted by \(room.hostName), \(room.participantCount) participants, \(stateLabel)")
    }
}

// MARK: - LiveDiscussionRoomView

struct LiveDiscussionRoomView: View {
    @StateObject var service: ListeningRoomService
    let currentUserID: String; let isHost: Bool
    @State private var messageText = ""; @State private var showRecapOverlay = false
    @FocusState private var messageFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                roomHeader; Divider()
                messageList
                if let poll = service.activePoll {
                    pollCard(poll).transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)).padding(.horizontal, 12).padding(.top, 6)
                }
                messageInputBar
            }
            if service.currentRoom?.state == "ended" && showRecapOverlay {
                recapOverlay.transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)).zIndex(10)
            }
        }
        .navigationBarHidden(true)
        .onChange(of: service.currentRoom?.state) { _, newState in
            if newState == "ended" { withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.45)) { showRecapOverlay = true } }
        }
    }

    private var roomHeader: some View {
        HStack(spacing: 12) {
            if let room = service.currentRoom {
                Image(systemName: room.type.sfSymbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.title).font(.headline).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(room.type.displayName).font(.caption).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                        Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.secondary)
                        Text("\(service.participants.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else { Text("Joining…").font(.headline).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Button { Task { await service.leaveRoom() }; dismiss() } label: {
                Text("Leave").font(.subheadline.weight(.semibold)).foregroundStyle(.red)
            }.accessibilityLabel("Leave room")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background { Rectangle().fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial)) }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let pinned = service.currentRoom?.pinnedMessages.first {
                        HStack(spacing: 6) {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.accentColor)
                            Text(pinned).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.08)))
                        .accessibilityLabel("Pinned: \(pinned)")
                    }
                    ForEach(Array(service.liveMessages.enumerated()), id: \.offset) { index, msg in
                        Text(msg).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                            .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial)) }
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(contrast == .increased ? 0.50 : 0.28), lineWidth: 0.5) }
                            .accessibilityLabel(msg).id(index)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onChange(of: service.liveMessages.count) { _, _ in
                if let last = service.liveMessages.indices.last {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func pollCard(_ poll: RoomPoll) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(poll.question).font(.subheadline.weight(.semibold))
            ForEach(poll.options, id: \.self) { option in
                Button { service.submitVote(pollID: poll.id, option: option) } label: {
                    HStack { Text(option).font(.subheadline); Spacer(); Text("\(poll.votes[option, default: 0])").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    .padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
                }.buttonStyle(.plain).accessibilityLabel("\(option), \(poll.votes[option, default: 0]) votes")
            }
        }
        .padding(14)
        .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial)) }
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
    }

    private var messageInputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                TextField("Say something…", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline).lineLimit(1...4)
                    .focused($messageFieldFocused).submitLabel(.send).onSubmit { sendMessage() }.accessibilityLabel("Message input")
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.tertiaryLabel) : Color.accentColor)
                }.disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel("Send")
                Button { service.sendMessage("🙏 Prayer moment."); messageText = "" } label: {
                    Image(systemName: "hands.sparkles").font(.system(size: 22)).foregroundStyle(Color.accentColor)
                }.accessibilityLabel("Send prayer moment")
                if isHost {
                    Button { Task { await service.endRoom() } } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 22)).foregroundStyle(.red)
                    }.accessibilityLabel("End room")
                }
            }.padding(.horizontal, 14).padding(.vertical, 10)
            .background { Rectangle().fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial)).ignoresSafeArea(edges: .bottom) }
        }
    }

    private var recapOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { showRecapOverlay = false }
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text("Room Ended").font(.title2.weight(.bold))
                Text(service.recapSummary).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 8)
                HStack(spacing: 12) {
                    Button("Share Recap") { showRecapOverlay = false }.buttonStyle(.borderedProminent)
                    Button("Add to Pulse") { showRecapOverlay = false }.buttonStyle(.bordered)
                }
            }
            .padding(28)
            .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial)).overlay { if !reduceTransparency { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.10)) } } }
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8).padding(.horizontal, 32)
        }
    }

    private func sendMessage() {
        let t = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        service.sendMessage(t); messageText = ""
    }
}

#Preview("Live Room") {
    let service = ListeningRoomService()
    NavigationStack { LiveDiscussionRoomView(service: service, currentUserID: "user-003", isHost: false).task { await service.joinRoom("preview") } }
}
