import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - CommunalChatView

struct CommunalChatView: View {
    let channel: AmenChannel
    let groupName: String

    @StateObject private var vm: CommunalChatViewModel
    @FocusState private var composerFocused: Bool
    @State private var pendingOffer: PrayerRequestOffer?
    @State private var showBlocked = false
    @State private var blockedReason = ""

    init(channel: AmenChannel, groupName: String) {
        self.channel = channel
        self.groupName = groupName
        _vm = StateObject(wrappedValue: CommunalChatViewModel(channel: channel))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(vm.messages) { msg in
                            CommunalBubble(message: msg, isFromMe: msg.senderId == vm.currentUid)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, pendingOffer == nil ? 80 : 160)
                    .padding(.top, 8)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last?.id {
                        withAnimation(.spring(response: 0.4)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            VStack(spacing: 0) {
                if channel.channelClass == .monitored {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.fill")
                            .font(.caption2)
                        Text("Messages are reviewed for safety before delivery")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial)
                    .accessibilityLabel("Safety notice: messages in this chat are checked before delivery")
                }
                if let offer = pendingOffer {
                    PrayerRequestOfferBanner(offer: offer) {
                        Task {
                            try? await BereanSmartChannelHook.shared.saveChannelPrayerRequest(offer)
                            withAnimation { pendingOffer = nil }
                        }
                    } onDismiss: {
                        withAnimation { pendingOffer = nil }
                    }
                    .padding(.bottom, 8)
                }
                CommunalComposerBar(text: $vm.draftText, isSending: vm.isSending, focused: $composerFocused) {
                    Task { await sendAndProcess() }
                }
            }
        }
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
        .sheet(isPresented: $showBlocked) {
            GuardianBlockedNoticeView(reason: blockedReason)
        }
        .task { await vm.start() }
        .onDisappear { vm.stop() }
    }

    private func sendAndProcess() async {
        guard let groupId = channel.groupId ?? channel.id else { return }
        if let (decision, msg) = await vm.send() {
            if decision == .block {
                blockedReason = "Your message didn't go through. Please keep conversations kind and uplifting."
                showBlocked = true
            } else if let msg {
                // Check for prayer request offer (non-blocking, user can dismiss)
                if let offer = await BereanSmartChannelHook.shared.detectChannelPrayerRequest(in: msg, groupId: groupId) {
                    withAnimation(.spring(response: 0.35)) { pendingOffer = offer }
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class CommunalChatViewModel: ObservableObject {
    @Published var messages: [CommunalMessage] = []
    @Published var draftText = ""
    @Published var isSending = false

    let channel: AmenChannel
    let currentUid: String
    private var listener: ListenerRegistration?

    init(channel: AmenChannel) {
        self.channel = channel
        self.currentUid = Auth.auth().currentUser?.uid ?? ""
    }

    func start() async {
        guard let channelId = channel.id else { return }
        listener = ChannelService.shared.listenCommunalMessages(channelId: channelId) { [weak self] msgs in
            withAnimation(.spring(response: 0.35)) { self?.messages = msgs }
        }
    }

    func stop() { listener?.remove() }

    /// Returns (decision, deliveredMessage?) after Guardian has classified the message.
    func send() async -> (GuardianDecision, CommunalMessage?)? {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let channelId = channel.id else { return nil }
        draftText = ""
        isSending = true
        defer { isSending = false }
        do {
            let msg = try await ChannelService.shared.sendCommunalMessage(channelId: channelId, text: text)
            guard let msgId = msg.id else { return nil }
            let decision = try await GuardianService.shared.awaitVerdict(messageId: msgId, channelId: channelId)
            return (decision, decision == .allow || decision == .allowWithSupport ? msg : nil)
        } catch {
            return nil
        }
    }
}

// MARK: - Communal Bubble

private struct CommunalBubble: View {
    let message: CommunalMessage
    let isFromMe: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isFromMe { Spacer(minLength: 48) }
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                if !message.scriptureRefs.isEmpty {
                    ScriptureRefRow(refs: message.scriptureRefs)
                }
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isFromMe ? Color.white : AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        if isFromMe {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AmenTheme.Colors.accentPrimary)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                                }
                        }
                    }
                if message.supportResourcesAttached {
                    CrisisResourcePill()
                }
            }
            if !isFromMe { Spacer(minLength: 48) }
        }
        .padding(.vertical, 2)
        .transition(.asymmetric(
            insertion: .push(from: isFromMe ? .trailing : .leading),
            removal: .opacity))
    }
}

// MARK: - Scripture Ref Row

private struct ScriptureRefRow: View {
    let refs: [String]
    @State private var expanded: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(refs, id: \.self) { ref in
                    ScriptureLinkChip(reference: ref, isExpanded: expanded == ref) {
                        withAnimation(.spring(response: 0.3)) {
                            expanded = (expanded == ref) ? nil : ref
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Crisis Resource Pill

private struct CrisisResourcePill: View {
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            Label("Support resources", systemImage: "heart.text.square")
                .font(.caption.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.accentPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule().strokeBorder(AmenTheme.Colors.accentPrimary.opacity(0.4), lineWidth: 0.5) }
                }
        }
        .sheet(isPresented: $showSheet) { CrisisResourceSheet() }
    }
}

// MARK: - Communal Composer Bar

struct CommunalComposerBar: View {
    @Binding var text: String
    let isSending: Bool
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.body)
                .focused(focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                        }
                }
            Button(action: onSend) {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(text.isEmpty ? AmenTheme.Colors.textTertiary : AmenTheme.Colors.accentPrimary)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) { Divider().opacity(0.3) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
