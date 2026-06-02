// ONEThreadListView.swift
// ONE — People zone root: E2E thread inbox.
// Owns its own NavigationStack; the shell has no nav container for zone content.

import SwiftUI
import FirebaseAuth

struct ONEThreadListView: View {
    @ObservedObject var store: ONEThreadStore

    @State private var searchQuery = ""
    @State private var showEphemeralFlow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }

    private var filteredThreads: [ONEThread] {
        guard !searchQuery.isEmpty else { return store.threads }
        let q = searchQuery.lowercased()
        return store.threads.filter { $0.id.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.threads.isEmpty {
                    emptyState
                } else {
                    threadList
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    newConversationButton
                }
            }
            .searchable(text: $searchQuery, prompt: "Search conversations")
            .navigationDestination(for: String.self) { threadID in
                if let thread = store.threads.first(where: { $0.id == threadID }) {
                    ONEThreadView(
                        thread: thread,
                        participantNames: [:],
                        store: store
                    )
                }
            }
            .sheet(isPresented: $showEphemeralFlow) {
                ONEEphemeralGroupFlowView(participantUIDs: []) { _ in
                    // TODO P2: create ephemeral thread in Firestore
                }
            }
        }
        .task {
            store.startListeningToThreads(uid: currentUID)
        }
        .onDisappear {
            store.stopListeningToThreads()
        }
    }

    // MARK: - Thread list

    private var threadList: some View {
        List {
            ForEach(filteredThreads) { thread in
                NavigationLink(value: thread.id) {
                    threadRow(thread)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Thread row

    private func threadRow(_ thread: ONEThread) -> some View {
        HStack(spacing: ONE.Spacing.md) {
            avatarView(for: thread)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(threadName(thread))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(thread.lastActivityAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: ONE.Spacing.xs) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(ONE.Colors.privateIndigo)
                    Text("End-to-end encrypted")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if thread.isEphemeral {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(ONE.Colors.ephemeralRed)
                    }
                }
            }
        }
        .padding(.vertical, ONE.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(threadName(thread)), end-to-end encrypted\(thread.isEphemeral ? ", ephemeral" : "")"
        )
    }

    private func avatarView(for thread: ONEThread) -> some View {
        let initials = String(threadName(thread).prefix(2)).uppercased()
        return ZStack {
            Circle().fill(ONE.Colors.privateIndigo.opacity(0.18))
            Text(initials)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ONE.Colors.privateIndigo)
        }
        .frame(width: 44, height: 44)
    }

    private func threadName(_ thread: ONEThread) -> String {
        let others = thread.participantUIDs.filter { $0 != currentUID }
        guard !others.isEmpty else { return "Note to Self" }
        return others.prefix(3).map { String($0.prefix(6)) }.joined(separator: ", ")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: ONE.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52))
                .foregroundStyle(ONE.Colors.privateIndigo.opacity(0.35))

            VStack(spacing: ONE.Spacing.sm) {
                Text("Private conversations")
                    .font(.system(size: 19, weight: .semibold))
                Text("Every message is end-to-end encrypted.\nStart a conversation only you and the recipient can read.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("New Conversation") { /* TODO P2: contact picker */ }
                .buttonStyle(.borderedProminent)
                .tint(ONE.Colors.privateIndigo)
                .accessibilityLabel("Start a new end-to-end encrypted conversation")
        }
        .padding(ONE.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var newConversationButton: some View {
        Menu {
            Button { /* TODO P2: contact picker */ } label: {
                Label("New Message", systemImage: "square.and.pencil")
            }
            Button { showEphemeralFlow = true } label: {
                Label("Ephemeral Group", systemImage: "flame.fill")
            }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16))
        }
        .accessibilityLabel("New conversation")
    }
}
