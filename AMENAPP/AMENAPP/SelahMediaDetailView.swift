import SwiftUI

struct SelahMediaDetailView: View {
    let item: SelahMediaItem
    let relatedMedia: [SelahMediaItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showCommentRoom = false
    @State private var showMemoryComposer = false
    @State private var showBereanAsk = false
    @State private var bereanQuestion = ""
    @State private var bereanResponse = ""
    @State private var bereanStreaming = false
    @State private var liked = false
    @State private var saved = false
    @State private var selectedRelated: SelahMediaItem?
    @State private var imageLoadError = false

    @StateObject private var service = SelahMediaService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    mediaHero
                    contentBlock
                    meaningTagsRow
                    actionBar
                    if item.commentRoomEnabled && item.commentRoomMode != SelahCommentRoomMode.closed.rawValue {
                        commentRoomTeaser
                    }
                    if !relatedMedia.isEmpty {
                        relatedSection
                    }
                    Spacer(minLength: 40)
                }
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMemoryComposer = true } label: {
                        Image(systemName: "brain.filled.head.profile")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .accessibilityLabel("Save to Memories")
                }
            }
            .sheet(isPresented: $showCommentRoom) {
                SelahCommentRoomView(item: item)
            }
            .sheet(isPresented: $showMemoryComposer) {
                SelahSaveToMemorySheet(item: item)
            }
            .sheet(isPresented: $showBereanAsk) {
                SelahBereanAskSheet(item: item)
            }
            .sheet(item: $selectedRelated) { related in
                SelahMediaDetailView(
                    item: related,
                    relatedMedia: []
                )
            }
        }
    }

    // MARK: - Subviews

    private var mediaHero: some View {
        Group {
            if item.itemType == .photo || item.itemType == .video {
                AsyncImage(url: URL(string: item.mediaURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 340)
                            .clipped()
                    case .failure:
                        placeholderHero
                    default:
                        ZStack {
                            Rectangle().fill(Color(.systemGray5))
                                .frame(maxWidth: .infinity).frame(height: 340)
                            ProgressView()
                        }
                    }
                }
            } else {
                placeholderHero
            }
        }
    }

    private var placeholderHero: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.3), Color.indigo.opacity(0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: item.itemType == .audio ? "waveform" : "photo")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity).frame(height: 340)
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ref = item.scriptureRef, !ref.isEmpty {
                Label(ref, systemImage: "book.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.12))
                    )
            }

            if !item.caption.isEmpty {
                Text(item.caption)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var meaningTagsRow: some View {
        Group {
            if !item.meaningTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.meaningTags) { tag in
                            SelahMeaningTagBadge(tag: tag)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionButton(
                icon: liked ? "heart.fill" : "heart",
                label: "\(item.likeCount + (liked ? 1 : 0))",
                tint: liked ? .red : .secondary
            ) {
                liked.toggle()
                Task { try? await service.toggleLike(itemId: item.id ?? "") }
            }

            Spacer()

            actionButton(
                icon: "bubble.left",
                label: "\(item.commentCount)",
                tint: .secondary
            ) {
                showCommentRoom = true
            }

            Spacer()

            actionButton(
                icon: saved ? "bookmark.fill" : "bookmark",
                label: "Save",
                tint: saved ? .orange : .secondary
            ) {
                saved = true
                Task { try? await service.saveMedia(itemId: item.id ?? "") }
            }

            Spacer()

            actionButton(
                icon: "sparkles",
                label: "Ask",
                tint: .purple
            ) {
                showBereanAsk = true
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    private func actionButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(label)
    }

    private var commentRoomTeaser: some View {
        Button { showCommentRoom = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Comment Room")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Join the conversation around this moment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.purple.opacity(0.18), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .buttonStyle(.plain)
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Moments")
                .font(.headline)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(relatedMedia) { related in
                        SelahMediaMiniCard(item: related)
                            .onTapGesture { selectedRelated = related }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 20)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(.systemBackground), Color.purple.opacity(0.04)]
                : [Color(.systemBackground), Color.indigo.opacity(0.03)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Comment Room View

struct SelahCommentRoomView: View {
    let item: SelahMediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [SelahCommentRoomMessage] = []
    @State private var draftText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Be the first to share a reflection")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { message in
                                SelahCommentBubble(message: message)
                            }
                        }
                        .padding(16)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    TextField("Share a reflection...", text: $draftText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($focused)

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(draftText.trimmingCharacters(in: .whitespaces).isEmpty
                                             ? Color.secondary : Color.purple)
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Comment Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadMessages() }
    }

    private func loadMessages() async {
        isLoading = true
        messages = (try? await SelahMediaService.shared.fetchCommentRoom(for: item.id ?? "")) ?? []
        isLoading = false
    }

    private func sendMessage() {
        let text = draftText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draftText = ""
        isSending = true
        Task {
            try? await SelahMediaService.shared.addCommentRoomMessage(to: item.id ?? "", text: text)
            await loadMessages()
            isSending = false
        }
    }
}

struct SelahCommentBubble: View {
    let message: SelahCommentRoomMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.authorDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let ref = message.scriptureRef {
                Label(ref, systemImage: "book.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Save to Memory Sheet

struct SelahSaveToMemorySheet: View {
    let item: SelahMediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var selectedTags: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory Title") {
                    TextField("What does this moment mean to you?", text: $title)
                }
                Section("Your Reflection") {
                    TextField("Add a personal note...", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Themes") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                        ForEach(SelahMeaningCategory.allCases) { cat in
                            Toggle(isOn: Binding(
                                get: { selectedTags.contains(cat.rawValue) },
                                set: { if $0 { selectedTags.insert(cat.rawValue) } else { selectedTags.remove(cat.rawValue) } }
                            )) {
                                Label(cat.rawValue, systemImage: "circle.fill")
                                    .font(.caption)
                            }
                            .toggleStyle(.button)
                        }
                    }
                }
            }
            .navigationTitle("Save to Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveMemory() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func saveMemory() {
        isSaving = true
        let tags = selectedTags.map { cat in
            SelahMeaningTag(category: SelahMeaningCategory(rawValue: cat) ?? .faith, label: cat)
        }
        let memory = SelahMediaMemory(
            title: title,
            bodyText: note,
            linkedMediaIds: [item.id ?? ""].filter { !$0.isEmpty },
            linkedScriptureRefs: [item.scriptureRef].compactMap { $0 },
            meaningTags: tags
        )
        Task {
            try? await SelahMediaService.shared.saveMemory(memory)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Berean Ask Sheet

struct SelahBereanAskSheet: View {
    let item: SelahMediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var response = ""
    @State private var streaming = false
    @FocusState private var questionFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Context chip
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.caption.isEmpty ? "Selected media" : String(item.caption.prefix(40)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .padding(.horizontal, 20)
                .padding(.top, 16)

                TextField("Ask Berean about this moment...", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal, 20)
                    .focused($questionFocused)

                Button {
                    askBerean()
                } label: {
                    HStack {
                        Spacer()
                        Label(streaming ? "Thinking…" : "Ask Berean", systemImage: "sparkles")
                            .font(.headline)
                        Spacer()
                    }
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.purple)
                    )
                    .foregroundStyle(.white)
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || streaming)
                .padding(.horizontal, 20)

                if !response.isEmpty {
                    ScrollView {
                        Text(response)
                            .font(.body)
                            .padding(20)
                    }
                }

                Spacer()
            }
            .navigationTitle("Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { questionFocused = true }
        }
    }

    private func askBerean() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        streaming = true
        response = ""
        Task {
            do {
                let stream = SelahMediaService.shared.askBereanAboutMedia(item: item, question: q)
                for try await chunk in stream {
                    response += chunk
                }
            } catch {}
            streaming = false
        }
    }
}

// MARK: - Shared Small Components

struct SelahMeaningTagBadge: View {
    let tag: SelahMeaningTag

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.categoryEnum.emoji)
                .font(.caption)
            Text(tag.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        )
    }
}

struct SelahMediaMiniCard: View {
    let item: SelahMediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: item.thumbnailURL ?? item.mediaURL)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.systemGray5))
                }
            }
            .frame(width: 120, height: 160)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let tag = item.meaningTags.first {
                Text(tag.categoryEnum.emoji)
                    .font(.caption)
                    .padding(6)
                    .background(Circle().fill(.ultraThinMaterial))
                    .padding(6)
            }
        }
        .frame(width: 120, height: 160)
    }
}
