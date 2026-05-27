import SwiftUI
import AVKit
import FirebaseDatabase

// MARK: - GroupWatchSessionView
// Full-screen synchronised video player with a collapsible glass chat panel.
// Playback position is synced every 500ms via Firebase RTDB.

struct GroupWatchSessionView: View {
    var sessionId: String
    var mediaURL: URL
    @StateObject var coordinator = GroupWatchCoordinator()

    @State private var player: AVPlayer?
    @State private var isChatVisible = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let chatPanelWidth: CGFloat = 280

    var body: some View {
        ZStack(alignment: .trailing) {
            // Full-screen video
            videoLayer

            // Collapsible chat panel
            HStack(spacing: 0) {
                Spacer()
                if isChatVisible {
                    chatPanel
                        .frame(width: chatPanelWidth)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .trailing).combined(with: .opacity)
                        )
                }
            }
            .animation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82),
                value: isChatVisible
            )

            // Toggle button
            chatToggleButton
        }
        .ignoresSafeArea()
        .onAppear { setupPlayer() }
        .onDisappear { coordinator.leave() }
    }

    // MARK: - Video layer
    private var videoLayer: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .accessibilityLabel("Group watch video")
            } else {
                Color.black.ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
    }

    // MARK: - Chat panel
    private var chatPanel: some View {
        GroupWatchChatPanel(
            sessionId: sessionId,
            participants: coordinator.participants
        )
        .frame(maxHeight: .infinity)
        .background {
            if reduceTransparency {
                Color(.systemBackground)
            } else {
                Rectangle()
                    .fill(Material.regularMaterial)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group watch chat")
    }

    // MARK: - Toggle button
    private var chatToggleButton: some View {
        VStack {
            Spacer()
            Button {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: LiquidGlassTokens.motionFast)
                        : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.8)
                ) {
                    isChatVisible.toggle()
                }
            } label: {
                Image(systemName: isChatVisible ? "chevron.right" : "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(width: 36, height: 56)
                    .background {
                        if reduceTransparency {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                .fill(Color(.systemBackground))
                                .overlay {
                                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                                }
                        } else {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                .fill(LiquidGlassTokens.blurElevated)
                                .overlay {
                                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.6)
                                }
                        }
                    }
                    .shadow(
                        color: LiquidGlassTokens.shadowSoft.color,
                        radius: LiquidGlassTokens.shadowSoft.radius,
                        y: LiquidGlassTokens.shadowSoft.y
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 100)
            .offset(x: isChatVisible ? -chatPanelWidth : 0)
            .animation(
                reduceMotion ? nil : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82),
                value: isChatVisible
            )
            .accessibilityLabel(isChatVisible ? "Hide chat" : "Show chat")
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: - Setup
    private func setupPlayer() {
        let p = AVPlayer(url: mediaURL)
        player = p
        coordinator.join(sessionId: sessionId, player: p)
    }
}

// MARK: - GroupWatchChatPanel
// Minimal chat panel — wire up to your messaging layer as needed.
struct GroupWatchChatPanel: View {
    var sessionId: String
    var participants: [String]

    @State private var messages: [GroupWatchMessage] = []
    @State private var draft: String = ""

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("\(participants.count) watching")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Composer
            HStack(spacing: 8) {
                TextField("Message…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityLabel("Chat message")
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(draft.isEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(AmenTheme.Colors.textPrimary))
                }
                .buttonStyle(.plain)
                .disabled(draft.isEmpty)
                .accessibilityLabel("Send chat message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func chatBubble(_ msg: GroupWatchMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(msg.senderName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text(msg.text)
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(reduceTransparency
                    ? AnyShapeStyle(Color(.systemFill))
                    : AnyShapeStyle(LiquidGlassTokens.blurThin))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(msg.senderName): \(msg.text)")
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let msg = GroupWatchMessage(id: UUID().uuidString, senderName: "You", text: text)
        messages.append(msg)
        draft = ""
        // TODO: persist to RTDB /groupWatch/{sessionId}/messages/{msgId}
    }
}

// MARK: - GroupWatchMessage model
struct GroupWatchMessage: Identifiable {
    let id: String
    let senderName: String
    let text: String
}
