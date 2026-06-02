import SwiftUI
import FirebaseAuth
import FirebaseCore

// MARK: - Discussion Room ViewModel

@MainActor
final class AmenObjectDiscussionRoomViewModel: ObservableObject {
    @Published var messages: [ObjectDiscussionMessage] = []
    @Published var presenceMembers: [DiscussionPresenceMember] = []
    @Published var room: ObjectDiscussionRoom?
    @Published var isSending = false
    @Published var error: String?

    private let service = AmenObjectDiscussionService.shared
    private var msgListener: (any Sendable)?
    private var presenceListener: (any Sendable)?

    var participantCount: Int { presenceMembers.count }

    var groupedMessages: [(dateLabel: String, messages: [ObjectDiscussionMessage])] {
        let grouped = Dictionary(grouping: messages) { msg -> String in
            let date = msg.createdAt.dateValue()
            if Calendar.current.isDateInToday(date)     { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return f.string(from: date)
        }
        let sortedKeys = grouped.keys.sorted {
            (grouped[$0]?.first?.createdAt.dateValue() ?? .distantPast) <
            (grouped[$1]?.first?.createdAt.dateValue() ?? .distantPast)
        }
        return sortedKeys.compactMap { key in
            guard let msgs = grouped[key] else { return nil }
            return (dateLabel: key, messages: msgs.sorted { $0.createdAt.dateValue() < $1.createdAt.dateValue() })
        }
    }

    func start(objectId: String, room: ObjectDiscussionRoom) {
        self.room = room
        guard let roomId = room.id else { return }

        Task { await service.joinPresence(objectId: objectId, roomId: roomId) }

        let msgReg = service.listenMessages(objectId: objectId, roomId: roomId) { [weak self] msgs in
            self?.messages = msgs
        }
        let presReg = service.observePresence(objectId: objectId, roomId: roomId) { [weak self] members in
            self?.presenceMembers = members
        }
        msgListener     = msgReg
        presenceListener = presReg
    }

    func stop(objectId: String) {
        guard let room, let roomId = room.id else { return }
        service.leavePresence(objectId: objectId, roomId: roomId)
    }

    func send(objectId: String, body: String) async {
        guard let roomId = room?.id else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await service.sendMessage(objectId: objectId, roomId: roomId, body: trimmed)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Discussion Room View

struct AmenObjectDiscussionRoomView: View {
    let objectId: String
    let objectTitle: String
    let roomType: ObjectDiscussionRoom.ObjectDiscussionRoomType
    /// If non-nil, the room already exists (join flow). If nil, we spawn on appear.
    let existingRoom: ObjectDiscussionRoom?

    @StateObject private var vm = AmenObjectDiscussionRoomViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var messageText = ""
    @State private var isAtBottom  = true
    @State private var isSpawning  = false
    @State private var spawnError: String?

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if vm.room == nil && isSpawning {
                    spawningState
                } else {
                    chatContent
                }
            }
            .navigationTitle(roomType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    presencePill
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil || spawnError != nil },
                set: { if !$0 { vm.error = nil; spawnError = nil } }
            )) {
                Button("OK", role: .cancel) { vm.error = nil; spawnError = nil }
            } message: {
                Text(vm.error ?? spawnError ?? "")
            }
        }
        .task { await spawnOrJoin() }
        .onDisappear { vm.stop(objectId: objectId) }
    }

    // MARK: - Spawning State

    private var spawningState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: roomType.icon)
                .font(.system(size: 44))
                .foregroundStyle(roomTypeColor)
            Text("Opening \(roomType.displayName)…")
                .font(.headline)
                .foregroundStyle(.secondary)
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    roomHeader

                    ForEach(vm.groupedMessages, id: \.dateLabel) { group in
                        dateSeparator(group.dateLabel)
                        ForEach(group.messages) { msg in
                            DiscussionMessageBubble(
                                message: msg,
                                currentUid: currentUid,
                                reduceTransparency: reduceTransparency
                            )
                        }
                    }

                    if vm.messages.isEmpty {
                        emptyState
                    }

                    Color.clear
                        .frame(height: 96)
                        .id("bottom")
                }
            }
            .onChange(of: vm.messages.count) { _, _ in
                guard isAtBottom else { return }
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .safeAreaInset(edge: .bottom) { composerBar }
    }

    // MARK: - Room Header

    private var roomHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(roomTypeColor.opacity(0.12))
                    .frame(width: 60, height: 60)
                Image(systemName: roomType.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(roomTypeColor)
            }
            Text(roomType.displayName)
                .font(.headline)
            Text("on \(objectTitle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(roomType.displayName) for \(objectTitle)")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Be the first to share.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("This room was just opened.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Date Separator

    private func dateSeparator(_ label: String) -> some View {
        HStack {
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        HStack(spacing: 12) {
            TextField(
                "Message this \(roomType.displayName.lowercased())…",
                text: $messageText,
                axis: .vertical
            )
            .font(.subheadline)
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Message input")

            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemGroupedBackground)) : AnyShapeStyle(.ultraThinMaterial))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
        }
    }

    private var sendButton: some View {
        Button {
            let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !vm.isSending else { return }
            messageText = ""
            isAtBottom  = true
            Task { await vm.send(objectId: objectId, body: text) }
        } label: {
            ZStack {
                if vm.isSending {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary : roomTypeColor
                        )
                }
            }
            .frame(width: 36, height: 36)
        }
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending)
        .accessibilityLabel("Send message")
    }

    // MARK: - Presence Pill

    private var presencePill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(vm.participantCount > 0 ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(vm.participantCount == 0
                 ? "Empty"
                 : "\(vm.participantCount) \(vm.participantCount == 1 ? "person" : "people")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(vm.participantCount) people present")
    }

    // MARK: - Room Type Color

    private var roomTypeColor: Color {
        switch roomType {
        case .discussion: return .blue
        case .prayer:     return .purple
        case .studyGroup: return .green
        }
    }

    // MARK: - Spawn or Join

    private func spawnOrJoin() async {
        if let room = existingRoom {
            vm.start(objectId: objectId, room: room)
            return
        }
        isSpawning = true
        do {
            let room = try await AmenObjectDiscussionService.shared.getOrCreateRoom(
                objectId:    objectId,
                objectTitle: objectTitle,
                type:        roomType
            )
            vm.start(objectId: objectId, room: room)
        } catch {
            spawnError = error.localizedDescription
        }
        isSpawning = false
    }
}

// MARK: - Message Bubble

private struct DiscussionMessageBubble: View {
    let message: ObjectDiscussionMessage
    let currentUid: String
    let reduceTransparency: Bool

    private var isOwn: Bool { message.authorId == currentUid }

    private var initials: String {
        let parts = message.authorDisplayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters)
    }

    var body: some View {
        if message.isDeleted {
            Text("This message was removed.")
                .font(.subheadline.italic())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
        } else {
            HStack(alignment: .top, spacing: 10) {
                if !isOwn { avatarView }

                VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                    if !isOwn {
                        Text(message.authorDisplayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    bubbleBody
                }
                .frame(
                    maxWidth: UIScreen.main.bounds.width * 0.72,
                    alignment: isOwn ? .trailing : .leading
                )

                if isOwn { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(message.authorDisplayName): \(message.body)")
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 30, height: 30)

            if let urlStr = message.authorAvatarURL,
               !urlStr.isEmpty,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initialsText
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            } else {
                initialsText
            }
        }
    }

    private var initialsText: some View {
        Text(initials)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.purple)
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.body)
                .font(.subheadline)
                .foregroundStyle(isOwn ? Color.white : Color.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Text(message.createdAt.dateValue(), style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(isOwn ? Color.white.opacity(0.6) : Color.secondary.opacity(0.7))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isOwn ? Color.purple : Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
