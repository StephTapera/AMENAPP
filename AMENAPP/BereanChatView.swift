// BereanChatView.swift
// AMEN App — Berean AI Chat · White Liquid Glass redesign
// All backend logic preserved. Only the visual layer is changed.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// ─── MARK: Models ────────────────────────────────────────────────────────────
// Unchanged — all logic preserved.

struct BereanChatMsg: Identifiable, Equatable {
    let id = UUID()
    let role: BereanMsgRole
    var content: String
    let timestamp: Date

    enum BereanMsgRole { case user, assistant }
}

// ─── MARK: ViewModel ─────────────────────────────────────────────────────────
// Unchanged — all logic preserved.

@MainActor
final class BereanChatViewModel: ObservableObject {
    @Published var messages: [BereanChatMsg] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "demo_user" }

    private let freeMsgLimit = 10
    @Published var messageCount: Int = 0
    @Published var isProUser: Bool = false

    var isAtLimit: Bool { !isProUser && messageCount >= freeMsgLimit }

    init() {
        messages.append(BereanChatMsg(
            role: .assistant,
            content: "Hey — I'm Berean. Ask me anything. Scripture, life, business, whatever's on your mind. I'll give you the real answer.",
            timestamp: .now
        ))
        loadMessageCount()
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, !isAtLimit else { return }

        inputText = ""

        let userMsg = BereanChatMsg(role: .user, content: text, timestamp: .now)
        messages.append(userMsg)
        messageCount += 1

        var assistantMsg = BereanChatMsg(role: .assistant, content: "", timestamp: .now)
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        isStreaming = true
        errorMessage = nil

        let history: [ClaudeMessage] = messages
            .dropLast()
            .suffix(10)
            .map { ClaudeMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content) }

        Task {
            do {
                let stream = await ClaudeAPIService.shared.stream(
                    system: BereanPrompts.bereanChat,
                    messages: history,
                    maxTokens: 1024
                )
                for try await token in stream {
                    messages[assistantIndex].content += token
                }
                saveConversation()
            } catch {
                messages[assistantIndex].content = "Something went wrong. Try again."
                errorMessage = error.localizedDescription
            }
            isStreaming = false
        }
    }

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
                self?.messageCount = doc?.data()?["chatMessageCount"] as? Int ?? 0
            }
    }
}

// ─── MARK: BereanChatView ────────────────────────────────────────────────────

struct BereanChatView: View {
    @StateObject private var vm = BereanChatViewModel()
    // TODO: Re-enable guardrail once BereanGuardrailSystem.swift is properly added to project
    // @StateObject private var guardrail = BereanGuardrailEngine()
    @State private var selectedMode: BereanQuickMode = .berean
    @State private var activeChip: BereanChipAction? = nil
    @State private var isRecording = false
    @State private var showOnboardingGuardrail = false
    @AppStorage("berean_onboarding_shown") private var onboardingShown = false

    /// True once user has sent at least one message — switches from landing → chat layout
    private var isInChat: Bool { vm.messages.count > 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Background ───────────────────────────────────────────────────
            AmenColor.background.ignoresSafeArea()

            // ── Content ──────────────────────────────────────────────────────
            VStack(spacing: 0) {
                header

                if isInChat {
                    chatScrollView
                } else {
                    landingHeroArea
                }

                Spacer(minLength: 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reserve space for composer to prevent content from being hidden
                Color.clear
                    .frame(height: vm.isAtLimit ? 165 : (isInChat ? 95 : 150))
            }

            // ── Composer + Chips anchored at bottom ──────────────────────────
            // Using overlay instead of ZStack ensures proper keyboard avoidance
            VStack(spacing: 12) {
                if !isInChat {
                    BereanActionChipRow(activeChip: $activeChip) { chip in
                        vm.inputText = chip.promptSeed
                    }
                }

                // ── Community Guardrail Prompt ───────────────────────────────
                // TODO: Re-enable once BereanGuardrailSystem.swift is properly added to project
                /* if guardrail.shouldShowCommunityPrompt, let promptType = guardrail.communityPromptType {
                    BereanCommunityPromptCard(
                        promptType: promptType,
                        onFindChurch: {
                            guardrail.logCommunityPromptShown(type: promptType, userAction: "find_church")
                            guardrail.shouldShowCommunityPrompt = false
                            // Navigate to Find Church
                        },
                        onReachOut: {
                            guardrail.logCommunityPromptShown(type: promptType, userAction: "reach_out")
                            guardrail.shouldShowCommunityPrompt = false
                            // Open contacts or messaging
                        },
                        onContinue: {
                            guardrail.logCommunityPromptShown(type: promptType, userAction: "continue")
                            guardrail.shouldShowCommunityPrompt = false
                            guardrail.markPromptShown()
                        }
                    )
                    .padding(.horizontal, 14)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
                } */

                if vm.isAtLimit {
                    paywallBanner
                }

                BereanGlassComposer(
                    text: $vm.inputText,
                    selectedMode: $selectedMode,
                    isRecording: $isRecording,
                    isStreaming: vm.isStreaming,
                    isAtLimit: vm.isAtLimit,
                    onSend: { 
                        // TODO: Re-enable guardrail analysis
                        // guardrail.analyzeMessage(vm.inputText, role: .user)
                        vm.send() 
                    },
                    onMicToggle: { isRecording.toggle() },
                    onAttach: nil,
                    onCamera: nil,
                    onNotes: nil,
                    onScripture: {
                        selectedMode = .scripture
                    }
                )
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 12)
            .background(AmenColor.background)
        }
        .navigationBarHidden(true)
        // TODO: Re-enable guardrail onboarding once BereanGuardrailSystem.swift is properly added
        /* .sheet(isPresented: $showOnboardingGuardrail) {
            BereanOnboardingGuardrailView(
                onFindChurch: {
                    showOnboardingGuardrail = false
                    onboardingShown = true
                    // Navigate to Find Church
                },
                onTalkToSomeone: {
                    showOnboardingGuardrail = false
                    onboardingShown = true
                    // Open contacts
                },
                onContinue: {
                    showOnboardingGuardrail = false
                    onboardingShown = true
                }
            )
        }
        .onAppear {
            if !onboardingShown && !isInChat {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showOnboardingGuardrail = true
                }
            }
        } */
    }

    // ─── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 10) {
            // Berean avatar — gold B on white glass
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                    .frame(width: 36, height: 36)

                Text("B")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AmenColor.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Berean AI")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AmenColor.titleText)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.133, green: 0.773, blue: 0.369))
                        .frame(width: 6, height: 6)
                    Text("Online · Powered by AMEN")
                        .font(.system(size: 11))
                        .foregroundColor(AmenColor.mutedText)
                }
            }

            Spacer()

            if !vm.isProUser {
                Text("\(max(0, 10 - vm.messageCount)) left")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(AmenColor.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AmenColor.accentMuted)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AmenColor.accent.opacity(0.30), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            AmenColor.background
                .overlay(Divider().background(AmenColor.divider), alignment: .bottom)
        )
    }

    // ─── Landing Hero Area ───────────────────────────────────────────────────
    // Shown before the user sends any message.

    private var landingHeroArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 32)

            VStack(alignment: .leading, spacing: 6) {
                // Animation 2 — staggered hero text lines
                HeroTextLine(
                    text: "Good morning.",
                    font: .system(size: 34, weight: .bold),
                    color: AmenColor.titleText,
                    delay: 0.08,
                    lineHeight: 44
                )
                HeroTextLine(
                    text: "What's on your heart?",
                    font: .system(size: 34, weight: .bold),
                    color: AmenColor.titleText,
                    delay: 0.22,
                    lineHeight: 44
                )
                HeroTextLine(
                    text: "Berean is ready.",
                    font: .system(size: 16),
                    color: AmenColor.mutedText,
                    delay: 0.38,
                    lineHeight: 24
                )
            }
            .padding(.horizontal, 22)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─── Chat Scroll View ────────────────────────────────────────────────────
    // Shown after the user has sent at least one message.

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { msg in
                        BereanLiquidMessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if vm.isStreaming {
                        BereanLiquidTypingIndicator()
                            .id("typing")
                    }
                    // Bottom anchor — accounts for composer height
                    Color.clear.frame(height: 180).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .onChange(of: vm.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: vm.isStreaming) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // ─── Paywall Banner ──────────────────────────────────────────────────────

    private var paywallBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13))
                .foregroundColor(AmenColor.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Free limit reached")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AmenColor.titleText)
                Text("Upgrade to Pro for unlimited Berean AI")
                    .font(.system(size: 11))
                    .foregroundColor(AmenColor.mutedText)
            }

            Spacer()

            Button("Upgrade") { /* Navigate to paywall */ }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(AmenColor.titleText)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.86))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AmenColor.accentMuted, lineWidth: 1)
                )
        )
        .padding(.horizontal, 14)
    }
}

// ─── MARK: BereanLiquidMessageBubble ─────────────────────────────────────────
// White LG redesign of message bubbles. Animation 4 — bubble entry.

struct BereanLiquidMessageBubble: View {
    let message: BereanChatMsg
    private var isUser: Bool { message.role == .user }

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 56) }

            if !isUser {
                // Berean avatar dot
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                        .frame(width: 28, height: 28)
                    Text("B")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AmenColor.accent)
                }
                .alignmentGuide(.bottom) { $0[.bottom] }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Bubble content
                Text(message.content.isEmpty ? "▌" : message.content)
                    .font(.system(size: 15))
                    .foregroundColor(isUser ? AmenColor.userBubbleText : AmenColor.bereanBubbleText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)

                // Timestamp
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(AmenColor.mutedText)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 56) }
        }
        // Animation 4 — bubble entry
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : (isUser ? 10 : -10))
        .scaleEffect(appeared ? 1 : 0.97, anchor: isUser ? .bottomTrailing : .bottomLeading)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.70)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            RoundedRectangle(cornerRadius: AmenRadius.bubble, style: .continuous)
                .fill(AmenColor.userBubble)
        } else {
            RoundedRectangle(cornerRadius: AmenRadius.bubble, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: AmenRadius.bubble, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AmenRadius.bubble, style: .continuous)
                        .stroke(Color.white.opacity(0.30), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

// ─── MARK: BereanLiquidTypingIndicator ───────────────────────────────────────
// White LG typing indicator — replaces dark BereanTypingIndicator.

struct BereanLiquidTypingIndicator: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Berean avatar
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                    .frame(width: 28, height: 28)
                Text("B")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AmenColor.accent)
            }

            // Glass bubble with animated dots
            HStack(spacing: 5) {
                BereanTypingDots()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: AmenRadius.bubble, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .background(
                        RoundedRectangle(cornerRadius: AmenRadius.bubble, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AmenRadius.bubble, style: .continuous)
                            .stroke(Color.white.opacity(0.30), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )

            Spacer(minLength: 56)
        }
    }
}
