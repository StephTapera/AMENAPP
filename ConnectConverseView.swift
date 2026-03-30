// ConnectConverseView.swift
// AMENAPP
//
// Discussion topics and faith conversations within AMEN Connect.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct ConversationTopic: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var authorUID: String = ""
    var authorName: String = ""
    var authorPhotoURL: String = ""
    var category: String = "General"
    var replyCount: Int = 0
    var likeCount: Int = 0
    var likedByUIDs: [String] = []
    var isPinned: Bool = false
    var tags: [String] = []
    var createdAt: Date = Date()
}

// MARK: - View

struct ConnectConverseView: View {
    @State private var topics: [ConversationTopic] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var appeared = false

    private let accentTeal = Color(red: 0.18, green: 0.55, blue: 0.60)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader

                Divider().opacity(0.3).padding(.horizontal, 20).padding(.top, 12)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if topics.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(topics) { topic in
                            topicRow(topic)
                            Divider().opacity(0.2).padding(.leading, 16)
                        }
                    }
                    .padding(.top, 8)
                }

                Color.clear.frame(height: 100)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateConversationSheet { newTopic in
                topics.insert(newTopic, at: 0)
            }
        }
        .task { await loadTopics() }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.38, blue: 0.42),
                    Color(red: 0.18, green: 0.55, blue: 0.60),
                    Color(red: 0.08, green: 0.30, blue: 0.35)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Color.white.opacity(0.06)).frame(width: 100).offset(x: -20, y: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("CONVERSATIONS")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Faith Discussions")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                Text("Engage in meaningful conversations about faith, life, and scripture.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                Button { showCreate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("Start a Discussion").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(accentTeal)
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

    // MARK: - Topic Row

    private func topicRow(_ topic: ConversationTopic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AsyncImage(url: URL(string: topic.authorPhotoURL)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        Circle().fill(accentTeal.opacity(0.15))
                            .overlay(
                                Text(String(topic.authorName.prefix(1)).uppercased())
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(accentTeal)
                            )
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(topic.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(topic.category)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timeAgo(topic.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Text(topic.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            Text(topic.body)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left").font(.system(size: 12))
                    Text("\(topic.replyCount)").font(.system(size: 12))
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "heart").font(.system(size: 12))
                    Text("\(topic.likeCount)").font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("No conversations yet")
                .font(.system(size: 17, weight: .bold))
            Text("Start a discussion about faith, scripture, or life.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Data

    private func loadTopics() async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("conversations")
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .getDocuments()

            topics = snap.documents.compactMap {
                try? Firestore.Decoder().decode(ConversationTopic.self, from: $0.data())
            }
        } catch {
            dlog("ConnectConverseView: Failed to load — \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Create Sheet

struct CreateConversationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (ConversationTopic) -> Void

    @State private var title = ""
    @State private var body_text = ""
    @State private var category = "General"
    @State private var isSaving = false

    private let categories = ["General", "Scripture", "Theology", "Life", "Testimony", "Questions", "Encouragement"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") {
                    TextField("Title", text: $title)
                    TextField("What's on your heart?", text: $body_text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Start Discussion")
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
        let topic = ConversationTopic(
            title: title,
            body: body_text,
            authorUID: uid,
            authorName: user.displayName ?? "User",
            authorPhotoURL: user.photoURL?.absoluteString ?? "",
            category: category
        )
        Task {
            let db = Firestore.firestore()
            let encoded = try? Firestore.Encoder().encode(topic)
            if let encoded {
                try? await db.collection("conversations").document(topic.id).setData(encoded)
            }
            await MainActor.run {
                onCreate(topic)
                dismiss()
            }
        }
    }
}
