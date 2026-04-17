//
//  VergeRoomView.swift
//  AMENAPP
//
//  Full-screen immersive live room with chat, speaker area, AI insights, and toolbar.
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - VergeRoomView

struct VergeRoomView: View {

    let room: VergeRoom

    @StateObject private var messagesVM   = VergeMessagesViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var messageText        = ""
    @State private var messageType        = VergeMessageType.text
    @State private var showEmojiPicker    = false
    @State private var showTipSheet       = false
    @State private var aiInsightVisible   = true
    @State private var elapsedSeconds     = 0
    @State private var latestAIInsight    = "Berean is analysing the conversation…"

    private let bg         = Color(hex: "0A0A0F")
    private let amenPurple = Color(hex: "6B48FF")
    private let amenViolet = Color(hex: "C084FC")
    private let amenGold   = Color(hex: "F59E0B")

    private var currentUID: String? { Auth.auth().currentUser?.uid }
    private var isHost: Bool { room.hostId == currentUID }

    private var elapsedLabel: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "0A0A1A"), Color(hex: "0A0A0F")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                speakerArea
                if aiInsightVisible {
                    aiInsightsBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                chatArea
                bottomToolbar
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showTipSheet) {
            TipSheetView(
                creatorId:   room.hostId,
                creatorName: "Host",
                roomTitle:   room.title
            )
        }
        .task { await messagesVM.startListening(roomId: room.id ?? "") }
        .task { await runElapsedTimer() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Title + timer
            VStack(alignment: .leading, spacing: 2) {
                Text(room.title)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if room.isLive {
                        PulsingDot(color: .red)
                        Text(elapsedLabel)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.white.opacity(0.55))
                            .monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.systemScaled(10, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(room.participantCount)")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Spacer()

            // End / Leave buttons
            if isHost {
                Button {
                    Task { try? await endRoomAndDismiss() }
                } label: {
                    Text("End")
                        .font(AMENFont.bold(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.red))
                }
                .buttonStyle(CoCreationPressStyle())
            } else {
                Button { dismiss() } label: {
                    Text("Leave")
                        .font(AMENFont.bold(13))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(CoCreationPressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.6))
    }

    // MARK: - Speaker Area

    private var speakerArea: some View {
        HStack(alignment: .center, spacing: 20) {
            // Host
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "06B6D4"), amenPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 88, height: 88)
                        .scaleEffect(1.05)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: room.isLive)

                    Circle()
                        .fill(amenPurple.opacity(0.3))
                        .frame(width: 80, height: 80)
                    Text(hostInitials)
                        .font(AMENFont.bold(26))
                        .foregroundStyle(.white)
                }
                Text("Host")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.white.opacity(0.7))
                if room.isLive {
                    Text("LIVE")
                        .font(AMENFont.bold(9))
                        .foregroundStyle(.white)
                        .tracking(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                }
            }

            // Featured participants (up to 3, excluding host)
            let featured = room.participantIds.filter { $0 != room.hostId }.prefix(3)
            ForEach(Array(featured.enumerated()), id: \.offset) { _, pid in
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Text(String(pid.prefix(2)).uppercased())
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.white.opacity(0.7))
                        )
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    Text("Member")
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(height: UIScreen.main.bounds.height * 0.22)
    }

    // MARK: - AI Insights Bar

    private var aiInsightsBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.systemScaled(14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(amenViolet)
            Text(latestAIInsight)
                .font(AMENFont.regular(13))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
            Spacer()
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                    aiInsightVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(amenViolet.opacity(0.2), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(messagesVM.messages) { msg in
                        VergeMessageBubbleView(
                            message: msg,
                            isOwnMessage: msg.authorId == currentUID
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: messagesVM.messages.count) { _ in
                if let last = messagesVM.messages.last?.id {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            // Emoji row (shown when showEmojiPicker)
            if showEmojiPicker {
                emojiRow
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                // Type indicator dot
                Circle()
                    .fill(messageType.accentColor)
                    .frame(width: 8, height: 8)

                // Text input
                TextField(
                    messageType == .question ? "Ask a question…" : "Say something…",
                    text: $messageText
                )
                .font(AMENFont.regular(15))
                .foregroundStyle(.white)
                .onSubmit { sendMessage() }

                // Question toggle
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        messageType = (messageType == .question) ? .text : .question
                    }
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.systemScaled(22, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(messageType == .question ? Color(hex: "06B6D4") : .white.opacity(0.35))
                }

                // Reaction button
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        showEmojiPicker.toggle()
                    }
                } label: {
                    Image(systemName: "face.smiling.inverse")
                        .font(.systemScaled(22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }

                // Tip button
                Button { showTipSheet = true } label: {
                    Image(systemName: "gift.fill")
                        .font(.systemScaled(20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(amenGold.opacity(0.8))
                }

                // Send
                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.systemScaled(28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(messageText.isEmpty ? .white.opacity(0.2) : amenViolet)
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Emoji Row

    private var emojiRow: some View {
        HStack(spacing: 18) {
            ForEach(["🙌", "🔥", "❤️", "🙏", "✨"], id: \.self) { emoji in
                Button {
                    sendReaction(emoji)
                    withAnimation { showEmojiPicker = false }
                } label: {
                    Text(emoji)
                        .font(.systemScaled(28))
                }
                .buttonStyle(CoCreationPressStyle())
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var hostInitials: String {
        String(room.hostId.prefix(2)).uppercased()
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let type = messageType
        messageText  = ""
        messageType  = .text
        Task {
            await messagesVM.sendMessage(
                roomId: room.id ?? "",
                workspaceId: room.workspaceId,
                content: text,
                type: type
            )
        }
    }

    private func sendReaction(_ emoji: String) {
        Task {
            await messagesVM.sendMessage(
                roomId: room.id ?? "",
                workspaceId: room.workspaceId,
                content: emoji,
                type: .reaction
            )
        }
    }

    private func endRoomAndDismiss() async throws {
        let vm = VergeViewModel()
        try await vm.endRoom(room)
        dismiss()
    }

    private func runElapsedTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            elapsedSeconds += 1
        }
    }
}

// MARK: - VergeMessagesViewModel

@MainActor
private class VergeMessagesViewModel: ObservableObject {

    @Published var messages: [VergeMessage] = []

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(roomId: String) async {
        guard !roomId.isEmpty else { return }
        listener = db.collection("vergeMessages")
            .whereField("roomId", isEqualTo: roomId)
            .order(by: "createdAt")
            .limit(toLast: 100)
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor [weak self] in
                    self?.messages = snap?.documents.compactMap {
                        try? $0.data(as: VergeMessage.self)
                    } ?? []
                }
            }
    }

    func sendMessage(
        roomId: String,
        workspaceId: String,
        content: String,
        type: VergeMessageType
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let displayName = Auth.auth().currentUser?.displayName ?? "Member"
        try? await db.collection("vergeMessages").addDocument(data: [
            "roomId":      roomId,
            "workspaceId": workspaceId,
            "authorId":    uid,
            "authorName":  displayName,
            "content":     content,
            "type":        type.rawValue,
            "reactions":   [:],
            "isPinned":    false,
            "createdAt":   FieldValue.serverTimestamp()
        ])
    }

    deinit { listener?.remove() }
}
