// AmenMinistryRoomDiscussionsTab.swift — AMEN App
// Space-scoped topic-channel discussion threads for Ministry Rooms.
// Channels: General, Questions, Prayer, Wins — spec Feature 18.
// Extended 2026-06-03: CF-backed category threads, AI-generated badge, composer sheet.

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Discussion Category

enum DiscussionCategory: String, Codable, CaseIterable, Identifiable {
    case prayer
    case study
    case question
    case general
    case announcement

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .prayer:       return "Prayer"
        case .study:        return "Study"
        case .question:     return "Question"
        case .general:      return "General"
        case .announcement: return "Announcement"
        }
    }

    var icon: String {
        switch self {
        case .prayer:       return "hands.sparkles.fill"
        case .study:        return "text.book.closed.fill"
        case .question:     return "questionmark.circle.fill"
        case .general:      return "bubble.left.and.bubble.right.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .prayer:       return Color(hex: "6E4BB5")
        case .study:        return Color(hex: "D9A441")
        case .question:     return Color(hex: "2CB6A8")
        case .general:      return Color.white.opacity(0.65)
        case .announcement: return Color.red
        }
    }
}

// MARK: - CF Thread

struct CFDiscussionThread: Identifiable, Codable {
    let id: String
    let title: String
    let authorFirstName: String
    let category: DiscussionCategory
    let replyCount: Int
    let isPinned: Bool
    let isAIGenerated: Bool
    let lastActivityAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, authorFirstName, category, replyCount, isPinned, isAIGenerated, lastActivityAt
    }

    init(
        id: String, title: String, authorFirstName: String,
        category: DiscussionCategory, replyCount: Int,
        isPinned: Bool, isAIGenerated: Bool, lastActivityAt: Date
    ) {
        self.id              = id
        self.title           = title
        self.authorFirstName = authorFirstName
        self.category        = category
        self.replyCount      = replyCount
        self.isPinned        = isPinned
        self.isAIGenerated   = isAIGenerated
        self.lastActivityAt  = lastActivityAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,            forKey: .id)
        title           = try c.decode(String.self,            forKey: .title)
        authorFirstName = try c.decode(String.self,            forKey: .authorFirstName)
        category        = try c.decodeIfPresent(DiscussionCategory.self, forKey: .category) ?? .general
        replyCount      = try c.decodeIfPresent(Int.self,      forKey: .replyCount)      ?? 0
        isPinned        = try c.decodeIfPresent(Bool.self,     forKey: .isPinned)        ?? false
        isAIGenerated   = try c.decodeIfPresent(Bool.self,     forKey: .isAIGenerated)   ?? false
        if let epoch = try? c.decode(Double.self, forKey: .lastActivityAt) {
            lastActivityAt = Date(timeIntervalSince1970: epoch)
        } else {
            lastActivityAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(title,           forKey: .title)
        try c.encode(authorFirstName, forKey: .authorFirstName)
        try c.encode(category,        forKey: .category)
        try c.encode(replyCount,      forKey: .replyCount)
        try c.encode(isPinned,        forKey: .isPinned)
        try c.encode(isAIGenerated,   forKey: .isAIGenerated)
        try c.encode(lastActivityAt.timeIntervalSince1970, forKey: .lastActivityAt)
    }
}

// MARK: - ViewModel

@MainActor
final class SpaceDiscussionsViewModel: ObservableObject {
    @Published var threads: [CFDiscussionThread] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private let firestoreService = AmenSpaceDiscussionService.shared

    func start(spaceId: String, channelType: SpaceDiscussionChannelType?) {
        listener?.remove()
        isLoading = true
        listener = firestoreService.listenThreads(spaceId: spaceId, channelType: channelType) { [weak self] rawThreads in
            self?.threads = rawThreads.map { t in
                let cat: DiscussionCategory
                switch SpaceDiscussionChannelType(rawValue: t.channelType ?? "general") ?? .general {
                case .prayer:        cat = .prayer
                case .questions:     cat = .question
                case .wins, .general: cat = .general
                }
                return CFDiscussionThread(
                    id:              t.postId,
                    title:           t.postTitle ?? "Untitled Thread",
                    authorFirstName: "",
                    category:        cat,
                    replyCount:      t.commentCount,
                    isPinned:        false,
                    isAIGenerated:   false,
                    lastActivityAt:  t.updatedAt.dateValue()
                )
            }
            self?.isLoading = false
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func loadCF(spaceId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            threads = try await AmenSpaceDiscussionService.shared.getDiscussions(spaceId: spaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Navigation wrapper

private struct ThreadNavItem: Identifiable {
    let id: String
    let title: String?
}

// MARK: - Relative formatter

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f
}()

// MARK: - Main Tab

struct AmenMinistryRoomDiscussionsTab: View {
    let spaceId: String
    var spaceName: String = ""

    @StateObject private var vm = SpaceDiscussionsViewModel()
    @State private var selectedChannel: SpaceDiscussionChannelType? = nil
    @State private var showNewThread = false
    @State private var showComposer  = false
    @State private var openThread: ThreadNavItem? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinnedThreads: [CFDiscussionThread]  { vm.threads.filter(\.isPinned) }
    private var aiThreads: [CFDiscussionThread]      { vm.threads.filter { !$0.isPinned && $0.isAIGenerated } }
    private var regularThreads: [CFDiscussionThread] { vm.threads.filter { !$0.isPinned && !$0.isAIGenerated } }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                channelPillRow

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Color(hex: "D9A441"))
                    Spacer()
                } else if vm.threads.isEmpty {
                    emptyState
                } else {
                    threadList
                }
            }
        }
        .sheet(item: $openThread) { item in
            DiscussionThreadView(postId: item.id, postTitle: item.title)
        }
        .sheet(isPresented: $showComposer) {
            NewSpaceThreadComposerSheet(spaceId: spaceId) {
                Task { await vm.loadCF(spaceId: spaceId) }
            }
        }
        .sheet(isPresented: $showNewThread) {
            NewSpaceThreadSheet(spaceId: spaceId, defaultChannel: selectedChannel ?? .general) {
                vm.start(spaceId: spaceId, channelType: selectedChannel)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            startDiscussionFAB
        }
        .onAppear {
            Task { await vm.loadCF(spaceId: spaceId) }
        }
        .onDisappear { vm.stop() }
        .onChange(of: selectedChannel) { _, new in
            vm.start(spaceId: spaceId, channelType: new)
        }
    }

    // MARK: - Channel Pill Row

    private var channelPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                allPill
                ForEach(SpaceDiscussionChannelType.allCases) { ch in
                    channelPill(ch)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(hex: "070607").opacity(0.95))
    }

    private var allPill: some View {
        let isActive = selectedChannel == nil
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.01) : .easeInOut(duration: 0.18)) {
                selectedChannel = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tray.2")
                    .font(.systemScaled(11, weight: .semibold))
                Text("All")
                    .font(.systemScaled(13, weight: .semibold))
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.55))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.07))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isActive ? Color.white.opacity(0.4) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All channels")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func channelPill(_ ch: SpaceDiscussionChannelType) -> some View {
        let isActive = selectedChannel == ch
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.01) : .easeInOut(duration: 0.18)) {
                selectedChannel = ch
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: ch.icon)
                    .font(.systemScaled(11, weight: .semibold))
                Text(ch.label)
                    .font(.systemScaled(13, weight: .semibold))
            }
            .foregroundStyle(isActive ? .white : ch.color)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isActive ? ch.color.opacity(0.22) : Color.white.opacity(0.07))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isActive ? ch.color.opacity(0.55) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ch.label) channel")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Thread List

    private var threadList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(pinnedThreads) { thread in
                    threadCard(thread)
                }
                if !aiThreads.isEmpty {
                    aiSectionHeader
                    ForEach(aiThreads) { thread in
                        threadCard(thread, isAIBadged: true)
                    }
                }
                ForEach(regularThreads) { thread in
                    threadCard(thread)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 96)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - AI Section Header

    private var aiSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(Color(hex: "6E4BB5"))
            Text("From Recent Content".uppercased())
                .font(.systemScaled(11, weight: .bold))
                .kerning(1.1)
                .foregroundStyle(Color(hex: "6E4BB5"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color(hex: "6E4BB5").opacity(0.30), lineWidth: 0.5)
                }
        }
        .padding(.top, 6)
        .accessibilityLabel("AI-generated threads from recent content")
    }

    // MARK: - Thread Card

    private func threadCard(_ thread: CFDiscussionThread, isAIBadged: Bool = false) -> some View {
        Button {
            openThread = ThreadNavItem(id: thread.id, title: thread.title)
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    Image(systemName: thread.category.icon)
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(thread.category.accentColor)
                        .frame(width: 38, height: 38)
                        .background { Circle().fill(thread.category.accentColor.opacity(0.12)) }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            if thread.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.systemScaled(10, weight: .semibold))
                                    .foregroundStyle(Color(hex: "D9A441"))
                            }
                            Text(thread.title)
                                .font(.systemScaled(15, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        HStack(spacing: 10) {
                            if !thread.authorFirstName.isEmpty {
                                Text(thread.authorFirstName)
                                    .font(.systemScaled(12))
                                    .foregroundStyle(Color.white.opacity(0.45))
                            }
                            Label("\(thread.replyCount)", systemImage: "bubble.left")
                                .font(.systemScaled(12))
                                .foregroundStyle(Color.white.opacity(0.45))
                            Spacer()
                            Text(relativeFormatter.localizedString(for: thread.lastActivityAt, relativeTo: Date()))
                                .font(.systemScaled(11))
                                .foregroundStyle(Color.white.opacity(0.35))
                        }

                        categoryBadge(thread.category)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    thread.isPinned
                                        ? Color(hex: "D9A441").opacity(0.30)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        }
                }

                if isAIBadged || thread.isAIGenerated {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(Color(hex: "6E4BB5"))
                        .padding(5)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color(hex: "6E4BB5").opacity(0.4), lineWidth: 0.5)
                                }
                        }
                        .offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(thread.isPinned ? "Pinned. " : "")\(thread.title), \(thread.replyCount) replies, \(thread.category.displayLabel)"
        )
        .accessibilityHint("Double tap to open discussion")
    }

    private func categoryBadge(_ category: DiscussionCategory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.systemScaled(9, weight: .semibold))
            Text(category.displayLabel)
                .font(.systemScaled(10, weight: .semibold))
        }
        .foregroundStyle(category.accentColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background { Capsule().fill(category.accentColor.opacity(0.15)) }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(44, weight: .ultraLight))
                .foregroundStyle(Color(hex: "D9A441").opacity(0.5))
            Text("No discussions yet.")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text("Be the first to start one!")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start Discussion") { showComposer = true }
                .font(.systemScaled(15, weight: .bold))
                .foregroundStyle(Color(hex: "070607"))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color(hex: "D9A441"), in: Capsule())
                .buttonStyle(.plain)
                .accessibilityLabel("Start a new discussion")
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - FAB

    private var startDiscussionFAB: some View {
        Button { showComposer = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color(hex: "070607"))
                Text("Start Discussion")
                    .font(.systemScaled(14, weight: .bold))
                    .foregroundStyle(Color(hex: "070607"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Color(hex: "D9A441"), in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 24)
        .accessibilityLabel("Start a new discussion thread")
    }
}

// MARK: - New Thread Composer Sheet

struct NewSpaceThreadComposerSheet: View {
    let spaceId: String
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title: String = ""
    @State private var threadBody: String = ""
    @State private var selectedCategory: DiscussionCategory = .general
    @State private var isPosting = false
    @State private var errorMessage: String?

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var bodyView: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.systemScaled(16))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("New Discussion")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        postDiscussion()
                    } label: {
                        if isPosting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: "D9A441"))
                        } else {
                            Text("Post")
                                .font(.systemScaled(16, weight: .bold))
                                .foregroundStyle(
                                    isFormValid ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.35)
                                )
                        }
                    }
                    .disabled(!isFormValid || isPosting)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.thinMaterial)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Title")
                            TextField(
                                "",
                                text: $title,
                                prompt: Text("What's this discussion about?").foregroundStyle(.white.opacity(0.3)),
                                axis: .vertical
                            )
                            .lineLimit(2...4)
                            .font(.systemScaled(16, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                    }
                            }
                            .onChange(of: title) { _, new in
                                if new.count > 120 { title = String(new.prefix(120)) }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Category")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(DiscussionCategory.allCases) { cat in
                                        categoryChip(cat)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Details (optional)")
                            ZStack(alignment: .topLeading) {
                                if threadBody.isEmpty {
                                    Text("Share more context, questions, or background...")
                                        .font(.systemScaled(14))
                                        .foregroundStyle(.white.opacity(0.3))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                }
                                TextEditor(text: $threadBody)
                                    .font(.systemScaled(14))
                                    .foregroundStyle(.white)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 120)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .onChange(of: threadBody) { _, new in
                                        if new.count > 2000 { threadBody = String(new.prefix(2000)) }
                                    }
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                    }
                            }
                            Text("\(threadBody.count)/2000")
                                .font(.systemScaled(11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        if let errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(Color.red)
                                Text(errorMessage)
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.white)
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 0.5)
                                    }
                            }
                            .accessibilityLabel("Error: \(errorMessage)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    var body: some View { bodyView }

    private func categoryChip(_ cat: DiscussionCategory) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.01) : .spring(response: 0.28, dampingFraction: 0.85)) {
                selectedCategory = cat
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.systemScaled(11, weight: .semibold))
                Text(cat.displayLabel)
                    .font(.systemScaled(13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color(hex: "070607") : cat.accentColor)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? cat.accentColor : cat.accentColor.opacity(0.12))
                    .overlay {
                        Capsule()
                            .strokeBorder(cat.accentColor.opacity(isSelected ? 0 : 0.35), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cat.displayLabel) category\(isSelected ? ", selected" : "")")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.systemScaled(11, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }

    private func postDiscussion() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody  = threadBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        isPosting = true
        Task {
            do {
                _ = try await AmenSpaceDiscussionService.shared.createDiscussion(
                    spaceId:  spaceId,
                    title:    trimmedTitle,
                    body:     trimmedBody,
                    category: selectedCategory
                )
                await MainActor.run {
                    isPosting = false
                    onCreated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isPosting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Legacy sheet

struct NewSpaceThreadSheet: View {
    let spaceId: String
    let defaultChannel: SpaceDiscussionChannelType
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedChannel: SpaceDiscussionChannelType
    @State private var isCreating = false
    @State private var errorMsg: String?

    private let service = AmenSpaceDiscussionService.shared

    init(
        spaceId: String,
        defaultChannel: SpaceDiscussionChannelType,
        onCreated: @escaping () -> Void
    ) {
        self.spaceId = spaceId
        self.defaultChannel = defaultChannel
        self.onCreated = onCreated
        _selectedChannel = State(initialValue: defaultChannel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thread Topic") {
                    TextField(
                        "e.g. What does Romans 8 mean for our church?",
                        text: $title,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }
                Section("Channel") {
                    ForEach(SpaceDiscussionChannelType.allCases) { ch in
                        HStack(spacing: 12) {
                            Image(systemName: ch.icon)
                                .foregroundStyle(ch.color)
                                .frame(width: 22)
                            Text(ch.label)
                            Spacer()
                            if selectedChannel == ch {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(hex: "D9A441"))
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedChannel = ch }
                    }
                }
                if let errorMsg {
                    Section {
                        Text(errorMsg)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("New Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Post") { createThread() }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func createThread() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreating = true
        Task {
            do {
                _ = try await service.createThread(
                    spaceId: spaceId,
                    title: trimmed,
                    channelType: selectedChannel
                )
                onCreated()
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Preview

#Preview {
    AmenMinistryRoomDiscussionsTab(spaceId: "space_preview", spaceName: "Grace Church")
        .preferredColorScheme(.dark)
}
