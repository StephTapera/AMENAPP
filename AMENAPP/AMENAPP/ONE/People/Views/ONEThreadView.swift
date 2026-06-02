// ONEThreadView.swift
// ONE — E2E encrypted conversation view.
// Living Threads distillation is gated by `livingThreadsEnabled` (Remote Config wired at P1-I).

import SwiftUI
import FirebaseAuth

struct ONEThreadView: View {
    let thread: ONEThread
    let participantNames: [String: String]     // uid → displayName; empty = use UID prefix
    var livingThreadsEnabled: Bool = false

    @ObservedObject var store: ONEThreadStore
    @State private var livingSummary: ONELivingThreadSummary?
    @State private var isDistilling = false
    @State private var engine = ONELivingThreadsEngine()
    @State private var shareItem: String?
    @State private var showShareSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var messages: [ONEThreadMessage] { store.messages[thread.id] ?? [] }
    private var decrypted: [String: String]   { store.decryptedMessages[thread.id] ?? [:] }

    private func displayName(for uid: String) -> String {
        participantNames[uid] ?? String(uid.prefix(6))
    }

    private var threadDisplayName: String {
        let others = thread.participantUIDs.filter { $0 != currentUID }
        guard !others.isEmpty else { return "Note to Self" }
        return others.prefix(3).map { displayName(for: $0) }.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesArea
            if let summary = livingSummary, livingThreadsEnabled {
                ONELivingThreadsSummaryCard(summary: summary) { item in
                    shareItem = item
                    showShareSheet = true
                }
            }
            ONEMessageComposerView(
                threadID: thread.id,
                threadContract: .dmDefault
            ) { text, perms in
                try await store.send(text: text, threadID: thread.id, permissions: perms)
            }
        }
        .navigationTitle(threadDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { e2eToolbarItem }
        .task(id: thread.id) {
            store.startListeningToMessages(threadID: thread.id)
        }
        .onChange(of: messages.count) { _, _ in
            if livingThreadsEnabled { Task { await runDistillation() } }
        }
        .onDisappear { store.stopListeningToMessages(threadID: thread.id) }
        .sheet(isPresented: $showShareSheet) {
            if let item = shareItem {
                ShareSheet(items: [item])
            }
        }
    }

    // MARK: - Messages scroll area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ONE.Spacing.xs) {
                    ForEach(messages) { msg in
                        ONEMessageBubble(
                            message: msg,
                            plaintext: decrypted[msg.id],
                            isFromCurrentUser: msg.senderUID == currentUID,
                            senderName: displayName(for: msg.senderUID),
                            permissions: thread.consentOverrides[msg.senderUID] ?? ONEMomentPermissions()
                        )
                        .padding(.horizontal, ONE.Spacing.md)
                        .id(msg.id)
                    }
                    Color.clear.frame(height: 1).id("__bottom__")
                }
                .padding(.vertical, ONE.Spacing.sm)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                    proxy.scrollTo("__bottom__", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("__bottom__", anchor: .bottom)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var e2eToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(threadDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text("End-to-end encrypted").font(.system(size: 10))
                }
                .foregroundStyle(ONE.Colors.privateIndigo)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(threadDisplayName), end-to-end encrypted")
        }
    }

    // MARK: - Living Threads

    private func runDistillation() async {
        guard livingThreadsEnabled, !isDistilling else { return }
        isDistilling = true
        defer { isDistilling = false }

        let inputs = messages
            .map { (senderName: displayName(for: $0.senderUID), text: decrypted[$0.id] ?? "") }
            .filter { !$0.text.isEmpty }

        livingSummary = await engine.distil(messages: inputs)
    }
}

