import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Room Detail View Model

@MainActor
final class AmenCovenantRoomDetailViewModel: ObservableObject {
    @Published var messages: [CovenantMessage] = []
    @Published var room: CovenantRoom?
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var error: String?
    @Published var reportError: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    func loadRoom(covenantId: String, roomId: String) async {
        do {
            let doc = try await db
                .collection("covenants")
                .document(covenantId)
                .collection("rooms")
                .document(roomId)
                .getDocument()
            room = try? doc.data(as: CovenantRoom.self)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startListening(covenantId: String, roomId: String) {
        listener = db
            .collection("covenants")
            .document(covenantId)
            .collection("rooms")
            .document(roomId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                Task { @MainActor in
                    self.messages = snapshot.documents.compactMap { try? $0.data(as: CovenantMessage.self) }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func sendMessage(covenantId: String, roomId: String, body: String) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        // Optimistic local insert
        let uid = Auth.auth().currentUser?.uid ?? ""
        let displayName = Auth.auth().currentUser?.displayName ?? "Member"
        let optimisticId = UUID().uuidString
        let optimistic = CovenantMessage(
            id: optimisticId,
            covenantId: covenantId,
            roomId: roomId,
            authorId: uid,
            authorDisplayName: displayName,
            authorAvatarURL: Auth.auth().currentUser?.photoURL?.absoluteString,
            body: trimmed,
            mentions: [],
            replyCount: 0,
            lastReplyAt: nil,
            participantsPreview: [],
            aiThreadSummary: nil,
            threadLocked: false,
            reactions: [:],
            isPinned: false,
            isDeleted: false,
            deletedAt: nil,
            deletedBy: nil,
            deletionReason: nil,
            createdAt: Timestamp(date: Date())
        )
        messages.append(optimistic)

        do {
            try await functions.httpsCallable("createCovenantMessage").call([
                "covenantId": covenantId,
                "roomId": roomId,
                "body": trimmed,
                "messageType": "text"
            ])
        } catch {
            messages.removeAll { $0.id == optimisticId }
            throw error
        }
    }

    func deleteMessage(covenantId: String, messageId: String) async {
        do {
            try await functions.httpsCallable("deleteCovenantMessage").call([
                "covenantId": covenantId,
                "messageId": messageId
            ])
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reportMessage(covenantId: String, messageId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "reporterId": uid,
            "covenantId": covenantId,
            "contentType": "message",
            "contentId": messageId,
            "reason": CovenantReport.ReportReason.harassment.rawValue,
            "status": CovenantReport.ReportStatus.submitted.rawValue,
            "createdAt": Timestamp(date: Date())
        ]
        // SECURITY FIX (HIGH 2026-06-11): Replace try? with explicit do-catch.
        // A silently dropped covenant report means harmful content goes unreported.
        do {
            try await db.collection("covenantReports").addDocument(data: data)
        } catch {
            reportError = "Report could not be submitted — please try again."
            print("[AmenCovenantRoomDetailViewModel] Report write failed: \(error)")
        }
    }

    // MARK: - Grouped Message Accessors

    var groupedMessages: [(dateLabel: String, messages: [CovenantMessage])] {
        let grouped = Dictionary(grouping: messages) { msg -> String in
            let date = msg.createdAt.dateValue()
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
        let sortedKeys = grouped.keys.sorted { a, b in
            let aDate = (grouped[a]?.first?.createdAt.dateValue()) ?? Date.distantPast
            let bDate = (grouped[b]?.first?.createdAt.dateValue()) ?? Date.distantPast
            return aDate < bDate
        }
        return sortedKeys.compactMap { key in
            guard let msgs = grouped[key] else { return nil }
            let sorted = msgs.sorted { $0.createdAt.dateValue() < $1.createdAt.dateValue() }
            return (dateLabel: key, messages: sorted)
        }
    }

    var pinnedMessages: [CovenantMessage] {
        messages.filter { $0.isPinned && !$0.isDeleted }
    }
}

// MARK: - Room Detail View

struct AmenCovenantRoomDetailView: View {
    let covenantId: String
    let roomId: String
    @EnvironmentObject var vm: AmenCovenantViewModel

    @StateObject private var detailVM = AmenCovenantRoomDetailViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var messageText: String = ""
    @State private var isAtBottom: Bool = true
    @State private var sendError: String?
    @State private var showUpgradeAlert = false
    @State private var showPaywall = false

    private var canPost: Bool {
        guard let room = detailVM.room else { return false }
        return AmenCovenantPermissions.canPostInRoom(room: room, membership: vm.currentMembership)
    }

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let pinned = detailVM.pinnedMessages.first {
                            pinnedMessageBanner(pinned)
                        }

                        ForEach(detailVM.groupedMessages, id: \.dateLabel) { group in
                            dateSeparator(group.dateLabel)
                            ForEach(group.messages) { message in
                                RoomMessageBubble(
                                    message: message,
                                    currentUserId: currentUserId,
                                    canPost: canPost,
                                    onReply: {
                                        // Thread navigation — push thread view when implemented
                                        print("[AmenCovenantRoomDetailView] Thread tapped for message \(message.id ?? "")")
                                    },
                                    onReport: {
                                        Task { await detailVM.reportMessage(covenantId: covenantId, messageId: message.id ?? "") }
                                    },
                                    onDelete: {
                                        Task { await detailVM.deleteMessage(covenantId: covenantId, messageId: message.id ?? "") }
                                    }
                                )
                            }
                        }

                        Color.clear
                            .frame(height: 96)
                            .id("bottomAnchor")
                    }
                }
                .onChange(of: detailVM.messages.count) { _, _ in
                    if isAtBottom {
                        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
                            proxy.scrollTo("bottomAnchor", anchor: .bottom)
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }

            VStack(spacing: 0) {
                if !isAtBottom {
                    scrollToLatestButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: isAtBottom)
                }
                composerBar
            }
        }
        .navigationTitle(detailVM.room?.name ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await detailVM.loadRoom(covenantId: covenantId, roomId: roomId)
            await vm.loadMembership(for: covenantId)
            detailVM.startListening(covenantId: covenantId, roomId: roomId)
        }
        .onDisappear {
            detailVM.stopListening()
        }
        .alert("Error", isPresented: Binding(
            get: { detailVM.error != nil },
            set: { if !$0 { detailVM.error = nil } }
        )) {
            Button("OK", role: .cancel) { detailVM.error = nil }
        } message: {
            Text(detailVM.error ?? "")
        }
    }

    // MARK: - Date Separator

    private func dateSeparator(_ label: String) -> some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Pinned Message Banner

    private func pinnedMessageBanner(_ message: CovenantMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.systemScaled(12))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pinned message")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .accessibilityLabel("Pinned message: \(message.body)")
    }

    // MARK: - Scroll To Latest Button

    private var scrollToLatestButton: some View {
        HStack {
            Spacer()
            Button {
                isAtBottom = true
            } label: {
                Label("Latest", systemImage: "chevron.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.purple))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }
            Spacer()
        }
        .padding(.bottom, 8)
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            if canPost {
                activeComposerBar
            } else {
                disabledComposerBar
            }
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private var activeComposerBar: some View {
        HStack(spacing: 12) {
            TextField(
                "Message #\(detailVM.room?.name ?? "room")",
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

            Button {
                let textToSend = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !textToSend.isEmpty, !detailVM.isSending else { return }
                messageText = ""
                isAtBottom = true
                Task {
                    do {
                        try await detailVM.sendMessage(
                            covenantId: covenantId,
                            roomId: roomId,
                            body: textToSend
                        )
                    } catch {
                        sendError = error.localizedDescription
                        messageText = textToSend
                    }
                }
            } label: {
                ZStack {
                    if detailVM.isSending {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(
                                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary
                                    : Color.purple
                            )
                    }
                }
                .frame(width: 36, height: 36)
            }
            .disabled(
                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                detailVM.isSending
            )
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, 4)
    }

    private var disabledComposerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
            Text("Upgrade to post in this room.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Upgrade") {
                showUpgradeAlert = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.purple)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .padding(.bottom, 4)
        .alert("Unlock This Room", isPresented: $showUpgradeAlert) {
            Button("Learn More") { showPaywall = true }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Posting in this room requires a higher membership tier. Upgrade your community membership to unlock posting access and all premium rooms.")
        }
        .sheet(isPresented: $showPaywall) {
            if let covenant = vm.currentCovenant {
                AmenCovenantPaywallView(covenant: covenant, context: .general)
            }
        }
    }
}

// MARK: - Message Bubble

private struct RoomMessageBubble: View {
    let message: CovenantMessage
    let currentUserId: String
    let canPost: Bool
    let onReply: () -> Void
    let onReport: () -> Void
    let onDelete: () -> Void

    private var isOwn: Bool { message.authorId == currentUserId }

    private var initials: String {
        let parts = message.authorDisplayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters)
    }

    var body: some View {
        if message.isDeleted {
            HStack {
                Text("This message was removed.")
                    .font(.subheadline.italic())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        } else {
            liveBubble
        }
    }

    private var liveBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isOwn { avatarCircle }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if !isOwn {
                    Text(message.authorDisplayName)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                bubbleBody

                // AI thread summary pill
                if let summary = message.aiThreadSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }

                // Thread reply indicator
                if message.replyCount > 0 {
                    Button(action: onReply) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.fill")
                                .font(.systemScaled(11))
                            Text("\(message.replyCount) \(message.replyCount == 1 ? "reply" : "replies")")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(10))
                        }
                        .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(message.replyCount) replies. Double-tap to view thread.")
                }

                // Reaction strip
                if !message.reactions.isEmpty {
                    reactionStrip
                }
            }
            .frame(
                maxWidth: UIScreen.main.bounds.width * 0.72,
                alignment: isOwn ? .trailing : .leading
            )

            if isOwn { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contextMenu {
            if canPost {
                Button(action: onReply) {
                    Label("Reply", systemImage: "bubble.left")
                }
            }
            if !isOwn {
                Button(role: .destructive, action: onReport) {
                    Label("Report", systemImage: "flag")
                }
            }
            if isOwn {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.authorDisplayName): \(message.body)")
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 30, height: 30)

            if let avatarURL = message.authorAvatarURL,
               !avatarURL.isEmpty,
               let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initialsLabel
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            } else {
                initialsLabel
            }
        }
    }

    private var initialsLabel: some View {
        Text(initials)
            .font(.systemScaled(11, weight: .bold))
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
                    .font(.systemScaled(10))
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

    private var reactionStrip: some View {
        HStack(spacing: 6) {
            ForEach(
                message.reactions.sorted { $0.value > $1.value }.prefix(5),
                id: \.key
            ) { emoji, count in
                HStack(spacing: 3) {
                    Text(emoji)
                        .font(.systemScaled(13))
                    if count > 1 {
                        Text("\(count)")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground)))
            }
        }
    }
}
