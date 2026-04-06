// BereanChatView.swift
// AMEN App — Berean AI core chat conversation screen.
// White Liquid Glass design. Streaming via ClaudeService.shared.sendMessage.
// Replaces the previous BereanChatView with a full redesign.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct BereanChatMsg: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: BereanChatMsgRole
    var content: String
    var timestamp: Date
    var isStreaming: Bool = false

    enum BereanChatMsgRole: String, Codable {
        case user, assistant
    }
}

// MARK: - ViewModel

@MainActor
final class BereanChatViewModel: ObservableObject {
    @Published var messages: [BereanChatMsg] = []
    @Published var inputText: String = ""
    @Published var isThinking: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentMode: BereanPersonalityMode = .shepherd

    private let db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "demo_user" }
    private var streamTask: Task<Void, Never>? = nil

    private let freeMsgLimit = 10
    @Published var messageCount: Int = 0
    @Published var isProUser: Bool = false
    var isAtLimit: Bool { !isProUser && messageCount >= freeMsgLimit }

    init(mode: BereanPersonalityMode = .shepherd) {
        self.currentMode = mode
        messages.append(BereanChatMsg(
            role: .assistant,
            content: "Hey — I'm Berean. Ask me anything. Scripture, life, business, whatever's on your mind.",
            timestamp: .now
        ))
        loadMessageCount()
    }

    // MARK: Send

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking, !isAtLimit else { return }

        inputText = ""
        errorMessage = nil

        let userMsg = BereanChatMsg(role: .user, content: text, timestamp: .now)
        messages.append(userMsg)
        messageCount += 1

        // Placeholder for streaming assistant message
        let assistantMsg = BereanChatMsg(
            role: .assistant,
            content: "",
            timestamp: .now,
            isStreaming: true
        )
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        isThinking = true

        // Build history from existing messages (excluding the empty placeholder)
        let history: [OpenAIChatMessage] = messages
            .dropLast(2)
            .suffix(10)
            .map { OpenAIChatMessage(content: $0.content, isFromUser: $0.role == .user) }

        streamTask = Task {
            do {
                let stream = ClaudeService.shared.sendMessage(
                    text,
                    conversationHistory: history,
                    mode: currentMode
                )
                for try await chunk in stream {
                    try Task.checkCancellation()
                    messages[assistantIndex].content += chunk
                }
                messages[assistantIndex].isStreaming = false
                saveConversation()
            } catch is CancellationError {
                messages[assistantIndex].isStreaming = false
                if messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content = "Cancelled."
                }
            } catch {
                messages[assistantIndex].isStreaming = false
                messages[assistantIndex].content = "Something went wrong. Please try again."
                errorMessage = error.localizedDescription
                dlog("BereanChatView stream error: \(error)")
            }
            isThinking = false
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: Persistence

    private func saveConversation() {
        guard let last = messages.last else { return }
        db.collection("users").document(userId)
            .collection("chatHistory")
            .addDocument(data: [
                "role": "assistant",
                "content": last.content,
                "timestamp": Timestamp(date: last.timestamp)
            ])
    }

    private func loadMessageCount() {
        db.collection("users").document(userId)
            .getDocument { [weak self] doc, _ in
                DispatchQueue.main.async {
                    self?.messageCount = doc?.data()?["chatMessageCount"] as? Int ?? 0
                }
            }
    }
}

// MARK: - BereanChatView

struct BereanChatView: View {
    /// Pass a mode to seed the conversation; defaults to shepherd.
    var initialMode: BereanPersonalityMode = .shepherd
    /// Optional initial query auto-sent on appear.
    var initialQuery: String? = nil
    /// Optional conversation title shown in nav bar center.
    var conversationTitle: String? = nil

    @StateObject private var vm: BereanChatViewModel
    @State private var showModeSheet = false
    @State private var sendSweep = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(initialMode: BereanPersonalityMode = .shepherd,
         initialQuery: String? = nil,
         conversationTitle: String? = nil) {
        self.initialMode = initialMode
        self.initialQuery = initialQuery
        self.conversationTitle = conversationTitle
        _vm = StateObject(wrappedValue: BereanChatViewModel(mode: initialMode))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            BereanColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar
                messageScrollView
            }

            // Input bar anchored at bottom
            VStack(spacing: 0) {
                if vm.isAtLimit {
                    paywallBanner
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
                inputBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
            }
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.3)
                )
            )
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showModeSheet) {
            BereanModesSheet()
        }
        .onAppear {
            if let query = initialQuery, !query.isEmpty {
                vm.inputText = query
                vm.send()
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack(spacing: 10) {
            // Back button
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundColor(BereanColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(Color.white.opacity(0.60)))
                            .overlay(Circle().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Center title
            Text(conversationTitle ?? "Berean")
                .font(BereanType.headline())
                .foregroundColor(BereanColor.textPrimary)
                .lineLimit(1)

            Spacer()

            // Mode pill
            Button { showModeSheet = true } label: {
                BereanPersonalityPill(mode: vm.currentMode)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.white
                .overlay(Divider().background(BereanColor.separator), alignment: .bottom)
        )
        .modifier(SoftStickyHeaderModifier(isActive: true, intensity: 0.25))
    }

    // MARK: - Message Scroll View

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(vm.messages) { msg in
                        BereanChatBubble(message: msg)
                            .id(msg.id)
                            .contextMenu {
                                messageContextMenu(msg)
                            }
                    }

                    // Thinking indicator shown while waiting for first streaming chunk
                    if vm.isThinking && (vm.messages.last?.content.isEmpty ?? false) {
                        BereanThinkingIndicator()
                            .id("thinking")
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    }

                    // Auto-scroll anchor
                    Color.clear.frame(height: 160).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .animation(.easeOut(duration: 0.2), value: vm.isThinking)
            }
            .onChange(of: vm.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: vm.messages.last?.content) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Message Context Menu

    @ViewBuilder
    private func messageContextMenu(_ msg: BereanChatMsg) -> some View {
        Button {
            UIPasteboard.general.string = msg.content
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            // Read aloud (placeholder — wire to AVSpeechSynthesizer if desired)
            dlog("Read aloud: \(msg.id)")
        } label: {
            Label("Read Aloud", systemImage: "speaker.wave.2")
        }

        Button {
            // Save to notes (placeholder — wire to ChurchNotesService)
            dlog("Save to notes: \(msg.id)")
        } label: {
            Label("Save to Notes", systemImage: "note.text.badge.plus")
        }

        if msg.role == .assistant {
            Button {
                vm.cancelStreaming()
                // Remove the last assistant message and re-send previous user message
                if let lastUser = vm.messages.last(where: { $0.role == .user }) {
                    vm.messages.removeAll { $0.id == msg.id }
                    vm.inputText = lastUser.content
                    vm.messages.removeAll { $0.id == lastUser.id }
                    vm.send()
                }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Attach button
            Button {
                // Attach action placeholder
                dlog("Berean: attach tapped")
            } label: {
                Image(systemName: "paperclip")
                    .font(.systemScaled(18, weight: .light))
                    .foregroundColor(BereanColor.textSecondary)
            }
            .padding(.bottom, 10)

            // Text field
            ZStack(alignment: .leading) {
                if vm.inputText.isEmpty {
                    Text("Ask Berean...")
                        .font(BereanType.body())
                        .foregroundColor(BereanColor.textTertiary)
                        .padding(.horizontal, 4)
                }
                TextField("", text: $vm.inputText, axis: .vertical)
                    .font(BereanType.body())
                    .foregroundColor(BereanColor.textPrimary)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 4)
                    .disabled(vm.isAtLimit)
            }
            .padding(.vertical, 10)

            // Voice + Send
            HStack(spacing: 6) {
                if vm.inputText.isEmpty && !vm.isThinking {
                    Button {
                        dlog("Berean: mic tapped")
                    } label: {
                        Image(systemName: "mic")
                            .font(.systemScaled(16, weight: .medium))
                            .foregroundColor(BereanColor.textSecondary)
                    }
                }

                Button {
                    if vm.isThinking {
                        vm.cancelStreaming()
                    } else {
                        sendSweep.toggle()
                        vm.send()
                        inputFocused = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(vm.isThinking
                                  ? Color.black
                                  : (vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Color(white: 0.85) : Color.black))
                            .frame(width: 34, height: 34)
                        Image(systemName: vm.isThinking ? "stop.fill" : "arrow.up")
                            .font(.systemScaled(13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .highlightSweep(trigger: sendSweep)
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .bereanGlassInputBar()
    }

    // MARK: - Paywall Banner

    private var paywallBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(13))
                .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
            VStack(alignment: .leading, spacing: 1) {
                Text("Free limit reached")
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(BereanColor.textPrimary)
                Text("Upgrade to Pro for unlimited Berean AI")
                    .font(AMENFont.regular(11))
                    .foregroundColor(BereanColor.textSecondary)
            }
            Spacer()
            Button("Upgrade") { }
                .font(AMENFont.semiBold(12))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.clipShape(Capsule()))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - BereanChatBubble

struct BereanChatBubble: View {
    let message: BereanChatMsg
    private var isUser: Bool { message.role == .user }

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 52) }

            if !isUser {
                avatarView
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleBody
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(BereanType.micro())
                    .foregroundColor(BereanColor.textTertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 52) }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : (isUser ? 10 : -10))
        .scaleEffect(appeared ? 1 : 0.97, anchor: isUser ? .bottomTrailing : .bottomLeading)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.72))) {
                appeared = true
            }
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
                .frame(width: 26, height: 26)
            Text("B")
                .font(.systemScaled(10, weight: .bold))
                .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
        }
        .alignmentGuide(.bottom) { $0[.bottom] }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        let displayText = message.content.isEmpty && message.isStreaming ? "▌" : message.content

        Text(displayText)
            .font(BereanType.body())
            .foregroundColor(isUser ? Color.white : BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

// MARK: - Typing Indicator (reexported for backward compat)

struct BereanLiquidTypingIndicator: View {
    var body: some View { BereanThinkingIndicator() }
}

// MARK: - Preview

struct BereanChatView_Previews: PreviewProvider {
    static var previews: some View {
        BereanChatView(initialMode: .shepherd, conversationTitle: "Romans Study")
    }
}
