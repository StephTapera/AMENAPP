// ConnectForumView.swift
// AMENAPP
//
// Community forum with threaded discussions for the AMEN Connect platform.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct ForumThread: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var authorUID: String = ""
    var authorName: String = ""
    var authorPhotoURL: String = ""
    var category: String = "General"
    var replyCount: Int = 0
    var viewCount: Int = 0
    var lastActivityAt: Date = Date()
    var isPinned: Bool = false
    var isLocked: Bool = false
    var tags: [String] = []
    var createdAt: Date = Date()
}

struct ForumReply: Identifiable, Codable {
    var id: String = UUID().uuidString
    var threadId: String = ""
    var authorUID: String = ""
    var authorName: String = ""
    var authorPhotoURL: String = ""
    var body: String = ""
    var likeCount: Int = 0
    var createdAt: Date = Date()
}

// MARK: - View

struct ConnectForumView: View {
    @State private var threads: [ForumThread] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var selectedCategory: String? = nil
    @State private var appeared = false

    private let categories = ["General", "Bible Study", "Apologetics", "Theology", "Testimony", "Prayer Requests", "Off-Topic"]
    private let accentRed = Color(red: 0.78, green: 0.22, blue: 0.22)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader
                categoryPills.padding(.top, 12)
                Divider().opacity(0.3).padding(.horizontal, 20).padding(.top, 8)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if filteredThreads.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        // Pinned threads first
                        ForEach(filteredThreads.filter { $0.isPinned }) { thread in
                            NavigationLink(destination: ForumThreadDetailView(thread: thread)) {
                                threadRow(thread, isPinned: true)
                            }
                            Divider().opacity(0.2).padding(.leading, 16)
                        }
                        ForEach(filteredThreads.filter { !$0.isPinned }) { thread in
                            NavigationLink(destination: ForumThreadDetailView(thread: thread)) {
                                threadRow(thread, isPinned: false)
                            }
                            Divider().opacity(0.2).padding(.leading, 16)
                        }
                    }
                    .padding(.top, 8)
                }

                Color.clear.frame(height: 100)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateForumThreadSheet { newThread in
                threads.insert(newThread, at: 0)
            }
        }
        .task { await loadThreads() }
    }

    private var filteredThreads: [ForumThread] {
        guard let cat = selectedCategory else { return threads }
        return threads.filter { $0.category == cat }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.12, blue: 0.12),
                    Color(red: 0.78, green: 0.22, blue: 0.22),
                    Color(red: 0.45, green: 0.10, blue: 0.10)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Color.white.opacity(0.06)).frame(width: 100).offset(x: -20, y: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("FORUM")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Community Forum")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                Text("Discuss, debate, and grow together in faith.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                Button { showCreate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("New Thread").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(accentRed)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 56)
        }
        .frame(minHeight: 200)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
    }

    // MARK: - Category Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.25)) { selectedCategory = nil }
                } label: {
                    Text("All")
                        .font(.system(size: 13, weight: selectedCategory == nil ? .bold : .regular))
                        .foregroundStyle(selectedCategory == nil ? .white : .secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(selectedCategory == nil ? accentRed : Color(.secondarySystemBackground)))
                }
                ForEach(categories, id: \.self) { cat in
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    } label: {
                        Text(cat)
                            .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .regular))
                            .foregroundStyle(selectedCategory == cat ? .white : .secondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(selectedCategory == cat ? accentRed : Color(.secondarySystemBackground)))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Thread Row

    private func threadRow(_ thread: ForumThread, isPinned: Bool) -> some View {
        HStack(spacing: 12) {
            // Author avatar
            AsyncImage(url: URL(string: thread.authorPhotoURL)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    Circle().fill(accentRed.opacity(0.15))
                        .overlay(
                            Text(String(thread.authorName.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accentRed)
                        )
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accentRed)
                    }
                    Text(thread.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(thread.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left").font(.system(size: 11))
                        Text("\(thread.replyCount)").font(.system(size: 11))
                    }
                    .foregroundStyle(.tertiary)

                    HStack(spacing: 4) {
                        Image(systemName: "eye").font(.system(size: 11))
                        Text("\(thread.viewCount)").font(.system(size: 11))
                    }
                    .foregroundStyle(.tertiary)

                    Text(thread.category)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accentRed)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accentRed.opacity(0.1)))
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("No threads yet")
                .font(.system(size: 17, weight: .bold))
            Text("Start a new thread to kick off the discussion!")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Data

    private func loadThreads() async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("forumThreads")
                .order(by: "lastActivityAt", descending: true)
                .limit(to: 30)
                .getDocuments()

            threads = snap.documents.compactMap {
                try? Firestore.Decoder().decode(ForumThread.self, from: $0.data())
            }
        } catch {
            dlog("ConnectForumView: Failed to load — \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Thread Detail

struct ForumThreadDetailView: View {
    let thread: ForumThread
    @State private var replies: [ForumReply] = []
    @State private var isLoading = true
    @State private var replyText = ""
    @FocusState private var isReplyFocused: Bool

    private let accentRed = Color(red: 0.78, green: 0.22, blue: 0.22)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Thread header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(thread.category.uppercased())
                            .font(.system(size: 10, weight: .bold)).kerning(1)
                            .foregroundStyle(accentRed)

                        Text(thread.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            AsyncImage(url: URL(string: thread.authorPhotoURL)) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Circle().fill(accentRed.opacity(0.15))
                                }
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())

                            Text(thread.authorName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)

                            Text(formatDate(thread.createdAt))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(thread.body)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)

                    Divider()

                    // Replies
                    Text("\(thread.replyCount) Replies")
                        .font(.system(size: 16, weight: .bold))

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    } else if replies.isEmpty {
                        Text("No replies yet. Be the first to respond!")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                    } else {
                        ForEach(replies) { reply in
                            replyRow(reply)
                        }
                    }
                }
                .padding(16)
            }

            // Reply composer
            if !thread.isLocked {
                HStack(spacing: 10) {
                    TextField("Write a reply...", text: $replyText)
                        .font(.system(size: 15))
                        .focused($isReplyFocused)
                        .textFieldStyle(.plain)

                    Button {
                        postReply()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(replyText.isEmpty ? Color.secondary : accentRed)
                    }
                    .disabled(replyText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadReplies() }
    }

    private func replyRow(_ reply: ForumReply) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: reply.authorPhotoURL)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Circle().fill(Color(.secondarySystemBackground))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(reply.authorName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(formatDate(reply.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(reply.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 8)
    }

    private func loadReplies() async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("forumThreads")
                .document(thread.id)
                .collection("replies")
                .order(by: "createdAt", descending: false)
                .limit(to: 50)
                .getDocuments()

            replies = snap.documents.compactMap {
                try? Firestore.Decoder().decode(ForumReply.self, from: $0.data())
            }
        } catch {
            dlog("ForumThreadDetailView: Failed to load replies — \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func postReply() {
        guard let uid = Auth.auth().currentUser?.uid,
              let user = Auth.auth().currentUser,
              !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let reply = ForumReply(
            threadId: thread.id,
            authorUID: uid,
            authorName: user.displayName ?? "User",
            authorPhotoURL: user.photoURL?.absoluteString ?? "",
            body: replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        replies.append(reply)
        let text = replyText
        replyText = ""

        Task {
            let db = Firestore.firestore()
            let encoded = try? Firestore.Encoder().encode(reply)
            if let encoded {
                try? await db.collection("forumThreads")
                    .document(thread.id)
                    .collection("replies")
                    .document(reply.id)
                    .setData(encoded)

                try? await db.collection("forumThreads")
                    .document(thread.id)
                    .updateData([
                        "replyCount": FieldValue.increment(Int64(1)),
                        "lastActivityAt": FieldValue.serverTimestamp()
                    ])
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Create Thread Sheet

struct CreateForumThreadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (ForumThread) -> Void

    @State private var title = ""
    @State private var body_text = ""
    @State private var category = "General"
    @State private var isSaving = false

    private let categories = ["General", "Bible Study", "Apologetics", "Theology", "Testimony", "Prayer Requests", "Off-Topic"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Thread") {
                    TextField("Title", text: $title)
                    TextField("What do you want to discuss?", text: $body_text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("New Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { save() }
                        .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid,
              let user = Auth.auth().currentUser else { return }
        isSaving = true
        let thread = ForumThread(
            title: title,
            body: body_text,
            authorUID: uid,
            authorName: user.displayName ?? "User",
            authorPhotoURL: user.photoURL?.absoluteString ?? "",
            category: category
        )
        Task {
            let db = Firestore.firestore()
            let encoded = try? Firestore.Encoder().encode(thread)
            if let encoded {
                try? await db.collection("forumThreads").document(thread.id).setData(encoded)
            }
            await MainActor.run {
                onCreate(thread)
                dismiss()
            }
        }
    }
}
