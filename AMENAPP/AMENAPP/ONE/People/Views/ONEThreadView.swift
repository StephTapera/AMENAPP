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
    @State private var shareItem: String?
    @State private var showShareSheet = false
    @State private var reportTargetMessageId: String = ""
    @State private var showReportSheet = false
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
                threadContract: .dmDefault,
                recipientId: thread.participantUIDs.first(where: { $0 != currentUID })
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
            if livingThreadsEnabled {
                if #available(iOS 26, *) { Task { await runDistillation() } }
            }
        }
        .onDisappear { store.stopListeningToMessages(threadID: thread.id) }
        .sheet(isPresented: $showShareSheet) {
            if let item = shareItem {
                ShareSheet(items: [item])
            }
        }
        .reportContentSheet(
            isPresented: $showReportSheet,
            targetType: .message,
            targetId: reportTargetMessageId
        )
    }

    // MARK: - Messages scroll area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ONE.Spacing.xs) {
                    ForEach(messages) { msg in
                        messageRow(for: msg)
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

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(for msg: ONEThreadMessage) -> some View {
        let isFromCurrentUser = msg.senderUID == currentUID
        HStack(alignment: .bottom, spacing: ONE.Spacing.xs) {
            if isFromCurrentUser {
                messageBubble(for: msg, isFromCurrentUser: true)
            } else {
                messageBubble(for: msg, isFromCurrentUser: false)
                reportButton(for: msg)
            }
        }
        .padding(.horizontal, ONE.Spacing.md)
        .contextMenu {
            if !isFromCurrentUser {
                Button(role: .destructive) { presentReport(for: msg) } label: {
                    Label("Report Message", systemImage: "flag")
                }
                Button(role: .destructive) {
                    Task { try? await BlockService.shared.blockUser(userId: msg.senderUID) }
                } label: {
                    Label("Block Sender", systemImage: "nosign")
                }
            }
        }
    }

    private func messageBubble(for msg: ONEThreadMessage, isFromCurrentUser: Bool) -> some View {
        ONEMessageBubble(
            message: msg,
            plaintext: decrypted[msg.id],
            isFromCurrentUser: isFromCurrentUser,
            senderName: displayName(for: msg.senderUID),
            permissions: thread.consentOverrides[msg.senderUID] ?? ONEMomentPermissions()
        )
    }

    private func reportButton(for msg: ONEThreadMessage) -> some View {
        Button(role: .destructive) { presentReport(for: msg) } label: {
            Image(systemName: "flag")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.red.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report message")
        .accessibilityHint("Reports this message to Amen's safety team")
    }

    private func presentReport(for msg: ONEThreadMessage) {
        reportTargetMessageId = msg.id
        showReportSheet = true
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var e2eToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(threadDisplayName)
                    .font(.systemScaled(15, weight: .semibold))
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.systemScaled(9))
                        .accessibilityHidden(true)
                    Text("End-to-end encrypted").font(.systemScaled(10))
                }
                .foregroundStyle(ONE.Colors.privateIndigo)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(threadDisplayName), end-to-end encrypted")
        }
    }

    // MARK: - Living Threads

    @available(iOS 26.0, *)
    private func runDistillation() async {
        guard livingThreadsEnabled, !isDistilling else { return }
        isDistilling = true
        defer { isDistilling = false }

        let inputs = messages
            .map { (senderName: displayName(for: $0.senderUID), text: decrypted[$0.id] ?? "") }
            .filter { !$0.text.isEmpty }

        let engine = ONELivingThreadsEngine()
        livingSummary = await engine.distil(messages: inputs)
    }
}

