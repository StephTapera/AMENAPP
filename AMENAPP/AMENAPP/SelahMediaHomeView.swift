import SwiftUI
import PhotosUI

// MARK: - Selah Media Home View
// The 4-mode glass shell:
//   Pause  — ambient contemplation + deep mode
//   Media  — photo/video feed with meaning tagging + upload
//   Memory — semantic memory graph
//   Continue — next-best-action spiritual continuations

struct SelahMediaHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var service = SelahMediaService.shared
    @State private var selectedMode: SelahMediaMode = .pause
    @State private var sessionStart = Date()
    @State private var viewedMedia: [SelahMediaItem] = []
    @State private var contextWindow: SelahContextWindow?

    // Media mode state
    @State private var selectedItem: SelahMediaItem?
    @State private var showUploader = false
    @State private var photoPickerItems: [PhotosPickerItem] = []

    // Pause mode state
    @State private var pauseItem: SelahMediaItem?
    @State private var showDeepMode = false

    // Trust circles state
    @State private var showTrustCircleManager = false

    private let engine = SelahIntelligenceEngine.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                backgroundForMode
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    modeContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Floating mode switcher bar
                modeSwitcherBar
                    .padding(.bottom, 8)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navToolbar }
            .sheet(item: $selectedItem) { item in
                SelahMediaDetailView(
                    item: item,
                    relatedMedia: engine.findRelatedMedia(to: item, in: service.mediaFeed)
                )
            }
            .sheet(isPresented: $showUploader) {
                SelahMediaUploadSheet(service: service)
            }
            .sheet(isPresented: $showDeepMode) {
                SelahDeepModeView(item: pauseItem, contextWindow: contextWindow)
            }
            .sheet(isPresented: $showTrustCircleManager) {
                SelahTrustCircleManagerView(service: service)
            }
        }
        .task {
            service.startListening()
            rebuildContext()
        }
        .onDisappear {
            // Don't stop listening — keep in memory for quick resume
        }
    }

    // MARK: - Mode Content

    @ViewBuilder
    private var modeContent: some View {
        switch selectedMode {
        case .pause:
            pauseContent
        case .media:
            mediaContent
        case .memory:
            SelahMemoryView(service: service)
        case .continue_:
            SelahContinueView(service: service, contextWindow: contextWindow)
        }
    }

    // MARK: - Pause Mode

    private var pauseContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                pauseHero

                if !service.mediaFeed.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Moments")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(service.mediaFeed.prefix(8)) { item in
                                    PauseMomentCard(item: item)
                                        .onTapGesture {
                                            pauseItem = item
                                            showDeepMode = true
                                        }
                                        .accessibilityLabel("Play moment")
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if let window = contextWindow, window.restSignalDetected {
                    restSignalBanner
                }

                Spacer(minLength: 80)
            }
            .padding(.top, 20)
        }
    }

    private var pauseHero: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.systemScaled(56, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .symbolRenderingMode(.hierarchical)

            Text("Be still.")
                .font(.title.weight(.light))
                .foregroundStyle(.primary)

            Text("Tap a moment to enter deep contemplation.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button {
                pauseItem = nil
                showDeepMode = true
            } label: {
                Label("Enter Pause", systemImage: "moon.stars")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.indigo, .purple],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    )
            }
            .accessibilityLabel("Enter Pause mode")
        }
        .padding(.horizontal, 24)
    }

    private var restSignalBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.systemScaled(18))
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 3) {
                Text("Time to rest")
                    .font(.subheadline.weight(.semibold))
                Text("You've been exploring for a while. Take a quiet moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.indigo.opacity(0.08))
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Media Mode

    private var mediaContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                mediaHeader

                if service.isLoadingFeed && service.mediaFeed.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if service.mediaFeed.isEmpty {
                    mediaEmptyState
                } else {
                    let ranked = engine.rankMediaItems(service.mediaFeed, context: currentSessionContext)
                    LazyVStack(spacing: 0) {
                        ForEach(ranked) { ranked in
                            SelahMediaFeedCard(
                                item: ranked.item,
                                matchReason: ranked.matchReason
                            )
                            .onTapGesture {
                                selectedItem = ranked.item
                                recordView(ranked.item)
                            }
                            .accessibilityLabel("Media item")
                            .accessibilityAddTraits(.isButton)
                            Divider().padding(.leading, 20)
                        }
                    }
                }

                Spacer(minLength: 80)
            }
        }
    }

    private var mediaHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Media")
                    .font(.largeTitle.weight(.bold))
                Text("Meaningful moments from your community")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showUploader = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.systemScaled(26))
                    .foregroundStyle(.purple)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Upload media")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var mediaEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.systemScaled(48, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("No media yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Share a photo or video from a meaningful spiritual moment.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)
            Button { showUploader = true } label: {
                Label("Share a Moment", systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.purple))
            }
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mode Switcher

    private var modeSwitcherBar: some View {
        HStack(spacing: 0) {
            ForEach(SelahMediaMode.allCases) { mode in
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedMode = mode
                    }
                    HapticManager.selection()
                    rebuildContext()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.systemScaled(18, weight: selectedMode == mode ? .semibold : .regular))
                            .foregroundStyle(selectedMode == mode ? Color.purple : Color.secondary)
                            .scaleEffect(selectedMode == mode ? 1.08 : 1.0)
                        Text(mode.label)
                            .font(.systemScaled(10, weight: selectedMode == mode ? .semibold : .regular))
                            .foregroundStyle(selectedMode == mode ? Color.purple : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .accessibilityLabel(mode.label)
            }
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        )
        .padding(.horizontal, 20)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: selectedMode)
    }

    // MARK: - Nav Toolbar

    @ToolbarContentBuilder
    private var navToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(20))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Close Selah")
        }
        ToolbarItem(placement: .principal) {
            Text("Selah")
                .font(.headline.weight(.semibold))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showTrustCircleManager = true } label: {
                Image(systemName: "person.2.circle")
                    .font(.systemScaled(18))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Trust Circles")
        }
    }

    // MARK: - Background per Mode

    private var backgroundForMode: some View {
        ZStack {
            Color(.systemBackground)
            switch selectedMode {
            case .pause:
                LinearGradient(
                    colors: [Color.indigo.opacity(0.06), Color.purple.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            case .media:
                Color.clear
            case .memory:
                LinearGradient(
                    colors: [Color.teal.opacity(0.04), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
            case .continue_:
                LinearGradient(
                    colors: [Color.orange.opacity(0.04), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Helpers

    private var currentSessionContext: SelahSessionContext {
        SelahSessionContext.current(
            mode: selectedMode,
            sessionStart: sessionStart,
            viewedMedia: viewedMedia
        )
    }

    private func rebuildContext() {
        let ctx = currentSessionContext
        contextWindow = engine.buildContextWindow(from: ctx, memories: service.memories)

        // Auto-generate continuations if there are none
        if service.continuations.isEmpty, let window = contextWindow {
            let suggestions = engine.generateContinuations(from: window, userId: "")
            Task {
                for s in suggestions {
                    _ = try? await service.saveContinuation(s)
                }
            }
        }
    }

    private func recordView(_ item: SelahMediaItem) {
        if !viewedMedia.contains(where: { $0.id == item.id }) {
            viewedMedia.append(item)
            rebuildContext()
        }
    }
}

// MARK: - Pause Moment Card

struct PauseMomentCard: View {
    let item: SelahMediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: item.thumbnailURL ?? item.mediaURL)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.indigo.opacity(0.2))
                }
            }
            .frame(width: 140, height: 180)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            )

            VStack(alignment: .leading, spacing: 2) {
                if let tag = item.meaningTags.first {
                    Text(tag.categoryEnum.emoji)
                        .font(.caption)
                }
                if let ref = item.scriptureRef, !ref.isEmpty {
                    Text(ref)
                        .font(.systemScaled(9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(8)
        }
        .frame(width: 140, height: 180)
        .accessibilityLabel("Media moment: \(item.caption.isEmpty ? "tap to open" : item.caption)")
    }
}

// MARK: - Media Feed Card

struct SelahMediaFeedCard: View {
    let item: SelahMediaItem
    let matchReason: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: item.thumbnailURL ?? item.mediaURL)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.systemGray5))
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                if !item.caption.isEmpty {
                    Text(item.caption)
                        .font(.subheadline)
                        .lineLimit(3)
                }

                if !item.meaningTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.meaningTags.prefix(3)) { tag in
                            Text("\(tag.categoryEnum.emoji) \(tag.label)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(matchReason)
                    .font(.caption2)
                    .foregroundStyle(.purple)

                HStack(spacing: 12) {
                    Label("\(item.likeCount)", systemImage: "heart")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Label("\(item.commentCount)", systemImage: "bubble.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Upload Sheet

struct SelahMediaUploadSheet: View {
    let service: SelahMediaService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImage: UIImage?
    @State private var caption = ""
    @State private var scriptureRef = ""
    @State private var selectedCategories: Set<SelahMeaningCategory> = []
    @State private var selectedTier: SelahTrustCircleTier = .community
    @State private var commentMode: SelahCommentRoomMode = .open
    @State private var isUploading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 1, matching: .images) {
                        HStack {
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text("Change Photo")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.systemScaled(32))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, height: 72)
                                Text("Choose a Photo")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .onChange(of: selectedPhotoItems) { _, items in
                        Task {
                            if let item = items.first,
                               let data = try? await item.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                selectedImage = img
                            }
                        }
                    }
                }

                Section("Caption") {
                    TextField("Describe this moment…", text: $caption, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Scripture (optional)") {
                    TextField("e.g. Romans 8:28", text: $scriptureRef)
                }

                Section("Themes") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                        ForEach(SelahMeaningCategory.allCases) { cat in
                            Toggle(isOn: Binding(
                                get: { selectedCategories.contains(cat) },
                                set: { if $0 { selectedCategories.insert(cat) } else { selectedCategories.remove(cat) } }
                            )) {
                                Text("\(cat.emoji) \(cat.rawValue)").font(.caption)
                            }
                            .toggleStyle(.button)
                        }
                    }
                }

                Section("Visibility") {
                    Picker("Who can see this?", selection: $selectedTier) {
                        Text("My Community").tag(SelahTrustCircleTier.community)
                        Text("Everyone").tag(SelahTrustCircleTier.public)
                        Text("Close Circle").tag(SelahTrustCircleTier.close)
                    }
                }

                Section("Comments") {
                    Picker("Comment Room", selection: $commentMode) {
                        Text("Open").tag(SelahCommentRoomMode.open)
                        Text("Close Circle only").tag(SelahCommentRoomMode.trustCircle)
                        Text("Off").tag(SelahCommentRoomMode.closed)
                    }
                }

                if let err = error {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Share a Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        upload()
                    } label: {
                        if isUploading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Share")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(selectedImage == nil || isUploading)
                }
            }
        }
    }

    private func upload() {
        guard let image = selectedImage,
              let data = image.jpegData(compressionQuality: 0.8) else { return }

        isUploading = true
        error = nil

        let tags = selectedCategories.map {
            SelahMeaningTag(category: $0, label: $0.rawValue)
        }
        let ref = scriptureRef.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                _ = try await service.uploadPhoto(
                    imageData: data,
                    caption: caption,
                    meaningTags: tags,
                    scriptureRef: ref.isEmpty ? nil : ref,
                    tier: selectedTier,
                    circleId: nil,
                    commentRoomMode: commentMode
                )
                isUploading = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isUploading = false
            }
        }
    }
}

// MARK: - Trust Circle Manager

struct SelahTrustCircleManagerView: View {
    @ObservedObject var service: SelahMediaService
    @Environment(\.dismiss) private var dismiss
    @State private var showCreator = false
    @State private var newCircleName = ""
    @State private var newCircleEmoji = "🤝"

    var body: some View {
        NavigationStack {
            List {
                if service.trustCircles.isEmpty {
                    Section {
                        Text("No trust circles yet. Create one to share moments with close friends.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your Circles") {
                        ForEach(service.trustCircles) { circle in
                            HStack {
                                Text(circle.emoji).font(.title3)
                                VStack(alignment: .leading) {
                                    Text(circle.name).font(.subheadline.weight(.medium))
                                    Text("\(circle.memberIds.count) member(s)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { showCreator = true } label: {
                        Label("Create Trust Circle", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Trust Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreator) {
                SelahTrustCircleCreatorSheet(service: service)
            }
        }
    }
}

struct SelahTrustCircleCreatorSheet: View {
    let service: SelahMediaService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🤝"
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Circle Name") {
                    TextField("e.g. Prayer Team", text: $name)
                }
                Section("Emoji") {
                    TextField("Emoji", text: $emoji)
                        .font(.largeTitle)
                }
            }
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        isSaving = true
                        Task {
                            _ = try? await service.createTrustCircle(name: name, memberIds: [], emoji: emoji)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
