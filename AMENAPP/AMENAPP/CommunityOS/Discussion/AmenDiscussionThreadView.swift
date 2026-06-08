// AmenDiscussionThreadView.swift
// AMEN App — Community OS / Discussion OS (A6) Phase 2
//
// Full thread view for an AmenDiscussionRoom.
// Wired to AmenDiscussionService for real-time Firestore messages.
//
// This view is distinct from DiscussionRoomView.swift (which uses the lighter
// DiscussionRoom model and placeholder rows). AmenDiscussionThreadView renders
// the full Phase 2 Discussion OS surface.
//
// Feature flag gate: AMENFeatureFlags.shared.communityOSDiscussionEnabled
//
// Design (C3):
//   - systemGroupedBackground page background
//   - White cards (28pt continuous corner radius), soft shadow for message bubbles
//   - System semantic colors only — no hex, no amenGold
//   - No public message counts, no engagement comparisons
//   - Provenance banner from DiscussionProvenanceBanner (existing component)
//   - Follow-up prompt chips from DiscussionFollowUpPrompt (existing component)

import SwiftUI
import FirebaseAuth

// MARK: - AmenDiscussionThreadView

struct AmenDiscussionThreadView: View {

    let room: AmenDiscussionRoom

    @StateObject private var service = AmenDiscussionService()
    @State private var newMessageText = ""
    @State private var replyingTo: DiscussionMessage? = nil
    @State private var isComposingReply = false
    @State private var showFollowUpPrompts = false
    @State private var errorAlertMessage: String? = nil
    @State private var isAtBottom = true
    @State private var showBerean = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentUID: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var isModerator: Bool {
        room.moderatorIds.contains(currentUID)
    }

    // MARK: - Body

    var body: some View {
        guard AMENFeatureFlags.shared.communityOSDiscussionEnabled else {
            return AnyView(featureUnavailableView)
        }
        return AnyView(mainContent)
    }

    // MARK: - Main content

    private var mainContent: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    messageScrollView
                }

                if !room.isReadOnly {
                    composerBar
                }
            }
            .navigationTitle(room.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { errorAlertMessage != nil },
                    set: { if !$0 { errorAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorAlertMessage = nil }
            } message: {
                Text(errorAlertMessage ?? "")
            }
        }
        .task {
            service.startListening(roomId: room.id)
        }
        .onDisappear {
            service.stopListening()
        }
        .onChange(of: service.errorMessage) { _, msg in
            if let msg { errorAlertMessage = msg }
        }
        .sheet(isPresented: $showBerean) {
            BereanVoiceAssistantView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Close discussion room")
        }
        ToolbarItem(placement: .topBarTrailing) {
            askBereanButton
        }
    }

    // MARK: - Message scroll view

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 1. Provenance banner
                    provenanceSection

                    // 2. Room type chip + participant hint
                    roomHeaderSection
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // 3. AI summary card
                    summaryCard

                    // 4. Locked / readonly banner
                    if room.isReadOnly {
                        lockedBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // 5. Message list
                    if service.isLoading && service.messages.isEmpty {
                        loadingState
                    } else if service.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.messages) { message in
                            messageRow(message)
                        }
                    }

                    // 6. Follow-up prompt chips
                    if !room.followUpPrompts.isEmpty {
                        followUpPromptsSection
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                    }

                    // Scroll anchor
                    Color.clear.frame(height: 96).id("bottom")
                }
            }
            .onChange(of: service.messages.count) { _, _ in
                guard isAtBottom else { return }
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Provenance section

    @ViewBuilder
    private var provenanceSection: some View {
        if let prov = room.provenance, room.hasProvenance {
            DiscussionProvenanceBanner(provenance: prov, onTap: nil)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Room header (type chip)

    private var roomHeaderSection: some View {
        HStack(spacing: 8) {
            // Room type chip
            HStack(spacing: 5) {
                Image(systemName: room.type.systemImage)
                    .font(.systemScaled(11, weight: .regular))
                Text(room.type.displayName)
                    .font(.systemScaled(12, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
            .accessibilityLabel("Room type: \(room.type.displayName)")

            // Privacy badge
            HStack(spacing: 4) {
                Image(systemName: room.privacyLevel.systemImage)
                    .font(.systemScaled(10))
                Text(room.privacyLevel.displayName)
                    .font(.systemScaled(11))
            }
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemFill))
            )
            .accessibilityLabel("Privacy: \(room.privacyLevel.displayName)")

            Spacer()
        }
    }

    // MARK: - Summary card

    @ViewBuilder
    private var summaryCard: some View {
        if let summary = room.summaryText, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Overview", systemImage: "text.quote")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))

                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Locked banner

    private var lockedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(12))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("This discussion is closed. No new messages can be posted.")
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }

    // MARK: - Loading state

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.accentColor)
                .scaleEffect(0.85)
            Text("Loading messages…")
                .font(.systemScaled(13))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(32, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Be the first to start the conversation.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No messages yet. Be the first to start the conversation.")
    }

    // MARK: - Message row

    @ViewBuilder
    private func messageRow(_ message: DiscussionMessage) -> some View {
        let isOwn = message.authorId == currentUID
        let visibleBody = message.visibleBody(viewerId: currentUID, isModerator: isModerator)
        let isPending = message.isModerated && !isModerator && message.authorId != currentUID

        VStack(alignment: .leading, spacing: 0) {
            // Threaded reply indent + header
            if message.isReply {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 2, height: 14)
                        .accessibilityHidden(true)
                    Text("Reply")
                        .font(.systemScaled(11))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .padding(.leading, 58)
                .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 10) {
                // Avatar placeholder
                Circle()
                    .fill(isOwn
                          ? Color.accentColor.opacity(0.15)
                          : Color(uiColor: .tertiarySystemFill))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(message.authorId.prefix(1)).uppercased())
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(isOwn ? Color.accentColor : Color(uiColor: .secondaryLabel))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    // Timestamp row
                    HStack(spacing: 6) {
                        Text(isOwn ? "You" : "Member")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(
                                isOwn
                                    ? Color.accentColor
                                    : Color(uiColor: .label)
                            )

                        Text(relativeTime(from: message.createdAt))
                            .font(.systemScaled(11))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))

                        Spacer()

                        if isPending {
                            Label("Pending review", systemImage: "clock")
                                .font(.systemScaled(10))
                                .foregroundStyle(Color.orange)
                        }
                    }

                    // Message body
                    Text(visibleBody)
                        .font(.systemScaled(14))
                        .foregroundStyle(
                            isPending
                                ? Color(uiColor: .tertiaryLabel)
                                : Color(uiColor: .label)
                        )
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Provenance attribution (if message cites another object)
                    if let prov = message.provenance {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.systemScaled(10))
                            Text("From \(prov.sourceType.capitalized)")
                                .font(.systemScaled(11))
                        }
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }

                    // Reply button (not shown for readonly rooms or moderated placeholders)
                    if !room.isReadOnly && !isPending {
                        Button {
                            replyingTo = message
                            isComposingReply = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.systemScaled(11))
                                Text("Reply")
                                    .font(.systemScaled(12))
                            }
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .accessibilityLabel("Reply to this message")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPending
            ? "Pending review message"
            : "\(isOwn ? "You" : "Member"): \(visibleBody)"
        )

        Divider()
            .padding(.leading, 58)
    }

    // MARK: - Follow-up prompts section

    private var followUpPromptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Continue the conversation", systemImage: "sparkle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .accessibilityHidden(true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(room.followUpPrompts, id: \.self) { prompt in
                        Button {
                            newMessageText = prompt
                        } label: {
                            Text(prompt)
                                .font(.systemScaled(13))
                                .foregroundStyle(Color(uiColor: .label))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemFill))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Suggested question: \(prompt)")
                    }
                }
            }
        }
    }

    // MARK: - Ask Berean button

    private var askBereanButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showBerean = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.systemScaled(11))
                Text("Ask Berean")
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel("Ask Berean AI about this discussion")
    }

    // MARK: - Composer bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            // Replying-to banner
            if replyingTo != nil, isComposingReply {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.systemScaled(11))
                        .foregroundStyle(Color.accentColor)
                    Text("Replying to a message")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Spacer()
                    Button {
                        replyingTo = nil
                        isComposingReply = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel reply")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                TextField(room.type.composerPlaceholder, text: $newMessageText, axis: .vertical)
                    .font(.systemScaled(15))
                    .foregroundStyle(Color(uiColor: .label))
                    .tint(Color.accentColor)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
                    .accessibilityLabel("Add to this discussion")

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, 4)
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.5))
                        .frame(height: 0.5),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.18), value: isComposingReply)
    }

    // MARK: - Send button

    private var sendButton: some View {
        Button {
            sendMessage()
        } label: {
            if service.isLoading {
                ProgressView()
                    .tint(Color.accentColor)
                    .scaleEffect(0.8)
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.systemScaled(28))
                    .foregroundStyle(
                        newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(uiColor: .tertiaryLabel)
                            : Color.accentColor
                    )
                    .frame(width: 36, height: 36)
            }
        }
        .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Send message")
    }

    // MARK: - Send action

    private func sendMessage() {
        let body = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !service.isLoading else { return }
        let uid = currentUID
        guard !uid.isEmpty else {
            errorAlertMessage = "Sign in to participate in discussions."
            return
        }
        let parentId = replyingTo?.id
        newMessageText = ""
        replyingTo = nil
        isComposingReply = false
        isAtBottom = true

        Task {
            do {
                try await service.postMessage(
                    to: room.id,
                    body: body,
                    authorId: uid,
                    parentMessageId: parentId
                )
            } catch {
                errorAlertMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Feature unavailable

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(40, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Discussion rooms are coming soon.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discussion rooms feature is not yet available.")
    }

    // MARK: - Helpers

    private func relativeTime(from date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60       { return "now" }
        if diff < 3_600    { return "\(Int(diff / 60))m" }
        if diff < 86_400   { return "\(Int(diff / 3_600))h" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Live discussion") {
    let prov = SpawnProvenance(
        sourceType: "post",
        sourceRef: "/posts/abc123",
        sourceOwnerId: "uid_host",
        intent: "discuss",
        createdAt: Date()
    )
    let room = AmenDiscussionRoom(
        id: "room_preview",
        title: "What does faith mean in daily life?",
        description: "A discussion spawned from Sunday's message.",
        type: .bibleStudy,
        privacyLevel: .public,
        participationControl: .open,
        sourceContextRef: "/posts/abc123",
        sourceContextType: "post",
        provenance: prov,
        participantIds: ["uid_host", "uid_a"],
        messageCount: 0,
        lastMessageAt: nil,
        summaryText: "Exploring James 2:14–26 — faith in action.",
        followUpPrompts: ["How do you live out your faith at work?", "Share a moment faith changed a decision."],
        moderatorIds: ["uid_host"],
        createdBy: "uid_host",
        createdAt: Date(),
        updatedAt: Date(),
        isDeleted: false,
        isPinned: false
    )
    AmenDiscussionThreadView(room: room)
}

#Preview("Readonly room") {
    let room = AmenDiscussionRoom(
        id: "room_readonly",
        title: "Sunday Announcements — June 2026",
        description: "",
        type: .churchLeadership,
        privacyLevel: .church,
        participationControl: .readonly,
        sourceContextRef: nil,
        sourceContextType: nil,
        provenance: nil,
        participantIds: ["uid_pastor"],
        messageCount: 0,
        lastMessageAt: nil,
        summaryText: nil,
        followUpPrompts: [],
        moderatorIds: ["uid_pastor"],
        createdBy: "uid_pastor",
        createdAt: Date(),
        updatedAt: Date(),
        isDeleted: false,
        isPinned: false
    )
    AmenDiscussionThreadView(room: room)
}
#endif
