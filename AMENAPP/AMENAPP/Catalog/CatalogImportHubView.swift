import SwiftUI
import FirebaseFunctions

struct CatalogImportHubView: View {

    let creatorId: String

    @State private var connectedSources: [ConnectedSource] = []
    @State private var isLoadingConnect = false
    @State private var connectingSourceId: String? = nil
    @State private var showManualAdd = false
    @State private var importJobs: [ImportJob] = []
    @State private var reviewWorks: [CatalogWork] = []
    @State private var isLoadingReview = false
    @State private var errorMessage: String? = nil
    @State private var isLocked = false

    private let functions = Functions.functions()

    var body: some View {
        if isLocked {
            CatalogEntitlementGateView(feature: .catalogCreate)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sourcesSection
                    importStatusSection
                    reviewQueueSection
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .task { await loadReviewQueue() }
            .sheet(isPresented: $showManualAdd) {
                ManualWorkEntryView(creatorId: creatorId) {
                    await loadReviewQueue()
                }
            }
        }
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connect Sources")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button {
                    showManualAdd = true
                } label: {
                    Label("Add Manually", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 10) {
                ForEach(availableSources) { source in
                    sourceRow(source: source)
                }
            }
        }
    }

    private func sourceRow(source: ImportSource) -> some View {
        let isConnected = connectedSources.contains(where: { $0.sourceId == source.id })
        let isConnecting = connectingSourceId == source.id
        return HStack(spacing: 12) {
            Image(systemName: source.icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(size: 14, weight: .medium))
                if source.comingSoon {
                    Text("Coming soon")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if source.comingSoon {
                Text("Soon")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.secondary.opacity(0.1)))
            } else if isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13))
                    Text("Connected")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    Task { await connectSource(sourceId: source.id) }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Connect")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isConnecting)
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Import Status

    @ViewBuilder
    private var importStatusSection: some View {
        if !importJobs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Import Progress")
                    .font(.system(size: 17, weight: .semibold))

                ForEach(importJobs) { job in
                    importJobRow(job: job)
                }
            }
        }
    }

    private func importJobRow(job: ImportJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.sourceName)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(job.status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: job.progress)
                .tint(.primary)
        }
        .padding(12)
        .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Review Queue

    private var reviewQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Queue")
                .font(.system(size: 17, weight: .semibold))

            if isLoadingReview {
                HStack {
                    ProgressView()
                    Text("Loading...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else if reviewWorks.isEmpty {
                Text("No works pending review.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(reviewWorks) { work in
                        reviewWorkRow(work: work)
                    }
                }
            }
        }
    }

    private func reviewWorkRow(work: CatalogWork) -> some View {
        HStack(spacing: 12) {
            Image(systemName: work.type.icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(work.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(work.reviewState.rawValue.capitalized)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                if work.reviewState != .published {
                    Button("Review") {
                        Task {
                            try? await CatalogService.shared.advanceReviewState(workId: work.id)
                            await loadReviewQueue()
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
                }
                if work.reviewState == .approved {
                    Button("Publish") {
                        Task {
                            try? await CatalogService.shared.publishWork(workId: work.id)
                            await loadReviewQueue()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12))
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Actions

    private func connectSource(sourceId: String) async {
        connectingSourceId = sourceId
        defer { connectingSourceId = nil }
        do {
            _ = try await functions.httpsCallable("connectSource").call(["sourceId": sourceId, "creatorId": creatorId])
            connectedSources.append(ConnectedSource(sourceId: sourceId))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadReviewQueue() async {
        isLoadingReview = true
        let all = await CatalogService.shared.fetchWorks(creatorId: creatorId, type: nil)
        reviewWorks = all.filter { $0.reviewState != .published }
        isLoadingReview = false
    }

    // MARK: - Static Data

    private var availableSources: [ImportSource] {
        [
            ImportSource(id: "spotify", name: "Spotify", icon: "music.note", comingSoon: false),
            ImportSource(id: "youtube", name: "YouTube", icon: "play.rectangle", comingSoon: false),
            ImportSource(id: "apple_music", name: "Apple Music", icon: "music.note.list", comingSoon: true),
            ImportSource(id: "google_books", name: "Google Books", icon: "book", comingSoon: false),
            ImportSource(id: "podcast_rss", name: "Podcast RSS", icon: "mic", comingSoon: false),
            ImportSource(id: "substack", name: "Substack", icon: "doc.text", comingSoon: false)
        ]
    }
}

// MARK: - Supporting Types

private struct ImportSource: Identifiable {
    let id: String
    let name: String
    let icon: String
    let comingSoon: Bool
}

private struct ConnectedSource: Identifiable {
    let id = UUID()
    let sourceId: String
}

private struct ImportJob: Identifiable {
    let id = UUID()
    let sourceName: String
    let status: String
    let progress: Double
}

// MARK: - ManualWorkEntryView

struct ManualWorkEntryView: View {

    let creatorId: String
    var onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: WorkType = .book
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var topics: String = ""
    @State private var links: [DraftLink] = [DraftLink()]
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Work Type", selection: $selectedType) {
                        ForEach(WorkType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                }

                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Topics (comma separated)", text: $topics)
                }

                Section("Links") {
                    ForEach($links) { $link in
                        VStack(spacing: 6) {
                            TextField("Platform (e.g. Spotify)", text: $link.platform)
                            TextField("URL", text: $link.url)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                        }
                    }
                    Button("Add Link") {
                        links.append(DraftLink())
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                    }
                }
            }
            .navigationTitle("Add Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let functions = Functions.functions()
            let topicList = topics.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let linkData = links.filter { !$0.url.isEmpty }.map { ["kind": "read", "platform": $0.platform, "url": $0.url] }
            _ = try await functions.httpsCallable("createCatalogWork").call([
                "creatorId": creatorId,
                "type": selectedType.rawValue,
                "title": title,
                "description": description,
                "topics": topicList,
                "links": linkData
            ])
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DraftLink: Identifiable {
    let id = UUID()
    var platform: String = ""
    var url: String = ""
}
