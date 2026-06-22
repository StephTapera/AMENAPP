// CachedThreadView.swift
// AMEN — Global Resilience System
// Displays a chat thread by merging Firestore messages (with offline persistence)
// and pending OutboxMessages from MessageOutbox.shared.
//
// Message states:
//   pending   — "Sending when connected…" + clock icon (from outbox)
//   failed    — "Tap to retry" button calling MessageOutbox.shared.retry(id)
//   synced / sent / delivered — normal bubble display (from Firestore)
//
// A LowDataBanner is pinned at the top when in low data mode.
// Each message body is followed by an InlineTranslationControl.

import SwiftUI
import FirebaseFirestore

// MARK: - FirestoreMessage

/// Decoded from /threads/{threadId}/messages/{messageId}.
private struct FirestoreMessage: Identifiable, Decodable {
    let id: String
    let senderId: String
    let bodyText: String
    let sentAt: Date
    let detectedLanguage: String?
    let translationConfidence: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId
        case bodyText
        case sentAt
        case detectedLanguage
        case translationConfidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        senderId = try c.decode(String.self, forKey: .senderId)
        bodyText = try c.decode(String.self, forKey: .bodyText)

        if let ts = try? c.decode(Timestamp.self, forKey: .sentAt) {
            sentAt = ts.dateValue()
        } else {
            sentAt = Date()
        }

        detectedLanguage = try? c.decode(String.self, forKey: .detectedLanguage)
        translationConfidence = try? c.decode(Double.self, forKey: .translationConfidence)
    }
}

// MARK: - ThreadViewModel

@MainActor
private final class ThreadViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var syncedMessages: [FirestoreMessage] = []
    @Published private(set) var errorMessage: String? = nil

    // MARK: Private

    private let threadId: String
    private var listener: ListenerRegistration? = nil

    // MARK: Init / deinit

    init(threadId: String) {
        self.threadId = threadId
    }

    deinit {
        listener?.remove()
    }

    // MARK: Firestore Listener

    func startListening() {
        guard listener == nil else { return }

        let collection = Firestore.firestore()
            .collection("threads")
            .document(threadId)
            .collection("messages")
            .order(by: "sentAt", descending: false)

        listener = collection.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                return
            }
            guard let snapshot else { return }

            self.syncedMessages = snapshot.documents.compactMap { doc in
                var data = doc.data()
                data["id"] = doc.documentID
                guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
                      let msg = try? JSONDecoder().decode(FirestoreMessage.self, from: jsonData)
                else { return nil }
                return msg
            }
            self.errorMessage = nil
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - CachedThreadView

struct CachedThreadView: View {

    // MARK: Input

    let threadId: String

    // MARK: State / Observed

    @StateObject private var viewModel: ThreadViewModel
    @ObservedObject private var outbox = MessageOutbox.shared
    @ObservedObject private var lowData = LowDataModeManager.shared

    // MARK: Init

    init(threadId: String) {
        self.threadId = threadId
        _viewModel = StateObject(wrappedValue: ThreadViewModel(threadId: threadId))
    }

    // MARK: Derived

    /// Outbox messages scoped to this thread.
    private var outboxMessages: [OutboxMessage] {
        outbox.pendingMessages.filter { $0.threadId == threadId }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Low-data banner pinned at top
            LowDataBanner()

            if let error = viewModel.errorMessage {
                errorBanner(message: error)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Synced messages from Firestore (offline cache is automatic)
                        ForEach(viewModel.syncedMessages) { msg in
                            syncedBubble(msg)
                                .id("synced-\(msg.id)")
                        }

                        // Pending / failed messages from outbox
                        ForEach(outboxMessages) { msg in
                            outboxBubble(msg)
                                .id("outbox-\(msg.id)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.syncedMessages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: outboxMessages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    // MARK: - Synced Bubble

    @ViewBuilder
    private func syncedBubble(_ msg: FirestoreMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Message body
            Text(msg.bodyText)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .accessibilityLabel(msg.bodyText)

            // Timestamp
            Text(msg.sentAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)

            // Inline translation
            InlineTranslationControl(
                originalText: msg.bodyText,
                detectedLanguage: msg.detectedLanguage,
                confidence: msg.translationConfidence
            )
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Outbox Bubble

    @ViewBuilder
    private func outboxBubble(_ msg: OutboxMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Message body
            Text(msg.bodyText ?? "")
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                )
                .accessibilityLabel(msg.bodyText ?? "")

            // Status row
            switch msg.status {
            case .pending:
                pendingStatusRow

            case .failed:
                failedStatusRow(messageId: msg.id)

            case .sent, .delivered, .synced:
                // Normal display — no status label needed once synced.
                EmptyView()

            case .draft:
                EmptyView()
            }

            // Inline translation for outbox messages that have body text
            if let body = msg.bodyText, !body.isEmpty {
                InlineTranslationControl(
                    originalText: body,
                    detectedLanguage: nil,
                    confidence: nil
                )
                .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Status Rows

    private var pendingStatusRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Sending when connected…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 4)
        .accessibilityLabel("Message pending. Will send when connected.")
    }

    private func failedStatusRow(messageId: String) -> some View {
        Button {
            MessageOutbox.shared.retry(messageId)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Tap to retry")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .accessibilityLabel("Message failed. Tap to retry sending.")
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityLabel("Thread load error: \(message)")
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastOutbox = outboxMessages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("outbox-\(lastOutbox.id)", anchor: .bottom)
            }
        } else if let lastSynced = viewModel.syncedMessages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("synced-\(lastSynced.id)", anchor: .bottom)
            }
        }
    }
}

// MARK: - Preview

#Preview("Cached Thread View") {
    NavigationStack {
        CachedThreadView(threadId: "thread_preview_001")
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
    }
    .onAppear {
        GlobalResilienceFeatureFlags.shared.autoTranslateEnabled = true
    }
}
