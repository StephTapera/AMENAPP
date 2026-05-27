import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - SacredChatView
//
// Chat UI for sacred (encrypted) channels.
// No GUARDIAN. No Berean. No AI. No preview.
// The absence of those features IS the promise.

struct SacredChatView: View {
    let channel: AmenChannel
    let partnerDisplayName: String

    @StateObject private var vm: SacredChatViewModel
    @FocusState private var composerFocused: Bool

    init(channel: AmenChannel, partnerDisplayName: String) {
        self.channel = channel
        self.partnerDisplayName = partnerDisplayName
        _vm = StateObject(wrappedValue: SacredChatViewModel(channel: channel))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(vm.messages) { item in
                            SacredBubble(text: item.text, isFromMe: item.isFromMe).id(item.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 80)
                    .padding(.top, 8)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last?.id {
                        withAnimation(.spring(response: 0.4)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            CommunalComposerBar(text: $vm.draftText, isSending: vm.isSending, focused: $composerFocused) {
                Task { await vm.send() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(partnerDisplayName).font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.caption2)
                        Text("Private").font(.caption2)
                    }
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
        }
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
        .task { await vm.start() }
        .onDisappear { vm.stop() }
    }
}

// MARK: - ViewModel

@MainActor
final class SacredChatViewModel: ObservableObject {
    struct DecryptedMessage: Identifiable {
        let id: String
        let text: String
        let isFromMe: Bool
    }

    @Published var messages: [DecryptedMessage] = []
    @Published var draftText = ""
    @Published var isSending = false

    let channel: AmenChannel
    private let currentUid: String
    private var listener: ListenerRegistration?

    init(channel: AmenChannel) {
        self.channel = channel
        self.currentUid = Auth.auth().currentUser?.uid ?? ""
    }

    func start() async {
        guard let channelId = channel.id else { return }
        try? await ChannelService.shared.bootstrapIdentityKeyIfNeeded()
        listener = ChannelService.shared.listenSacredMessages(channelId: channelId) { [weak self] msgs in
            guard let self else { return }
            let items = msgs.compactMap { msg -> DecryptedMessage? in
                guard let id = msg.id else { return nil }
                let text = (try? ChannelService.shared.decryptMessage(msg)) ?? "🔒"
                return DecryptedMessage(id: id, text: text, isFromMe: msg.senderId == self.currentUid)
            }
            withAnimation(.spring(response: 0.35)) { self.messages = items }
        }
    }

    func stop() { listener?.remove() }

    func send() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let channelId = channel.id else { return }
        draftText = ""
        isSending = true
        defer { isSending = false }
        try? await ChannelService.shared.sendSacredMessage(channelId: channelId, plaintext: text)
    }
}

// MARK: - Sacred Bubble

private struct SacredBubble: View {
    let text: String
    let isFromMe: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            if isFromMe { Spacer(minLength: 48) }
            Text(text)
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
            if !isFromMe { Spacer(minLength: 48) }
        }
        .padding(.vertical, 2)
        .transition(.asymmetric(
            insertion: .push(from: isFromMe ? .trailing : .leading),
            removal: .opacity))
    }
}
