// CatalogSearchView.swift
// AMEN Catalog — Universal Search
//
// Search returns PEOPLE + ORGANIZATIONS as primary results, then works.
// Never raw URLs. Result types: creator cards (person/org), work cards, topic chips.
//
// Search pipeline (mirrors CF): Algolia keyword → Pinecone semantic → Firestore fallback.
// Debounce: 0.3s. Min query: 2 characters.
//
// Liquid Glass: native search bar, system backgrounds, no gold/purple accent surfaces.

import SwiftUI
import FirebaseFunctions

// MARK: - Models

struct CatalogCreatorResult: Identifiable {
    let id: String
    let displayName: String
    let badge: String?
    let verified: Bool
    let workCount: Int
    let topics: [String]
    let avatarUrl: String?
    let entityType: String   // "person" | "organization"
    let bio: String
}

struct CatalogWorkResult: Identifiable {
    let id: String           // workId
    let creatorId: String
    let creatorName: String
    let title: String
    let type: String
    let topics: [String]
    let coverUrl: String?
    let publishedAt: Date?
}

struct TopicResult: Identifiable {
    let id: String           // topicId
    let topicName: String
    let workCount: Int
    let creatorCount: Int
    var isFollowed: Bool
}

struct CatalogSearchResults {
    var creators: [CatalogCreatorResult]
    var works: [CatalogWorkResult]
    var topics: [TopicResult]

    static let empty = CatalogSearchResults(creators: [], works: [], topics: [])
}

// MARK: - State

enum CatalogSearchState: Equatable {
    case idle
    case loading
    case results
    case empty
    case error(String)
}

// MARK: - ViewModel

@MainActor
final class CatalogSearchViewModel: ObservableObject {

    @Published var query: String = ""
    @Published var searchState: CatalogSearchState = .idle
    @Published var results: CatalogSearchResults = .empty

    private let functions = Functions.functions()
    private var debounceTask: Task<Void, Never>?

    func onQueryChanged(_ newQuery: String) {
        debounceTask?.cancel()
        let trimmed = newQuery.trimmingCharacters(in: .whitespaces)

        guard trimmed.count >= 2 else {
            searchState = .idle
            results = .empty
            return
        }

        searchState = .loading
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    func retry() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        Task { await performSearch(trimmed) }
    }

    private func performSearch(_ q: String) async {
        searchState = .loading
        do {
            let result = try await functions.httpsCallable("searchCatalog").call([
                "query": q,
                "limit": 20,
            ])
            guard let data = result.data as? [String: Any] else {
                searchState = .empty
                results = .empty
                return
            }
            let parsed = parseSearchResults(data)
            if parsed.creators.isEmpty && parsed.works.isEmpty && parsed.topics.isEmpty {
                searchState = .empty
            } else {
                searchState = .results
            }
            results = parsed
        } catch {
            searchState = .error(error.localizedDescription)
        }
    }

    // MARK: - Parsing

    private func parseSearchResults(_ data: [String: Any]) -> CatalogSearchResults {
        let creatorsRaw = data["creators"] as? [[String: Any]] ?? []
        let worksRaw    = data["works"] as? [[String: Any]] ?? []
        let topicsRaw   = data["topics"] as? [[String: Any]] ?? []

        let creators: [CatalogCreatorResult] = creatorsRaw.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            return CatalogCreatorResult(
                id:          id,
                displayName: d["displayName"] as? String ?? "Creator",
                badge:       d["badge"] as? String,
                verified:    d["verified"] as? Bool ?? false,
                workCount:   d["workCount"] as? Int ?? 0,
                topics:      d["topics"] as? [String] ?? [],
                avatarUrl:   d["avatarUrl"] as? String,
                entityType:  d["entityType"] as? String ?? "person",
                bio:         d["bio"] as? String ?? ""
            )
        }

        let works: [CatalogWorkResult] = worksRaw.compactMap { d in
            guard let id = d["workId"] as? String else { return nil }
            var publishedAt: Date?
            if let ms = d["publishedAt"] as? Double {
                publishedAt = Date(timeIntervalSince1970: ms / 1000)
            }
            return CatalogWorkResult(
                id:          id,
                creatorId:   d["creatorId"] as? String ?? "",
                creatorName: d["creatorName"] as? String ?? "",
                title:       d["title"] as? String ?? "",
                type:        d["type"] as? String ?? "article",
                topics:      d["topics"] as? [String] ?? [],
                coverUrl:    d["coverUrl"] as? String,
                publishedAt: publishedAt
            )
        }

        let topics: [TopicResult] = topicsRaw.compactMap { d in
            guard let id = d["topicId"] as? String else { return nil }
            return TopicResult(
                id:           id,
                topicName:    d["topicName"] as? String ?? id,
                workCount:    d["workCount"] as? Int ?? 0,
                creatorCount: d["creatorCount"] as? Int ?? 0,
                isFollowed:   false
            )
        }

        return CatalogSearchResults(creators: creators, works: works, topics: topics)
    }
}

// MARK: - Main View

struct CatalogSearchView: View {

    @StateObject private var vm = CatalogSearchViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCreator: CatalogCreatorResult?
    @State private var selectedWork: CatalogWorkResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchResultsBody
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $vm.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "People, works, topics..."
            )
            .onChange(of: vm.query) { _, newValue in
                vm.onQueryChanged(newValue)
            }
            .sheet(item: $selectedWork) { work in
                CatalogWorkDetailSheet(work: work)
            }
        }
    }

    @ViewBuilder
    private var searchResultsBody: some View {
        switch vm.searchState {
        case .idle:
            idleHint
        case .loading:
            searchSkeleton
        case .results:
            resultsList
        case .empty:
            emptyState
        case .error(let msg):
            errorState(msg)
        }
    }

    // MARK: - Idle hint

    private var idleHint: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Search for people, organizations,\nbooks, podcasts, sermons, and more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Results list

    private var resultsList: some View {
        List {
            // People & Organizations section (primary)
            if !vm.results.creators.isEmpty {
                Section("People & Organizations") {
                    ForEach(vm.results.creators) { creator in
                        NavigationLink {
                            CatalogPillView(
                                creatorId: creator.id,
                                creatorName: creator.displayName
                            )
                        } label: {
                            CreatorResultRow(creator: creator)
                        }
                    }
                }
            }

            // Works section (secondary)
            if !vm.results.works.isEmpty {
                Section("Works") {
                    ForEach(vm.results.works) { work in
                        Button {
                            selectedWork = work
                        } label: {
                            WorkResultRow(work: work)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Topics section
            if !vm.results.topics.isEmpty {
                Section("Topics") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(vm.results.topics) { topic in
                                CatalogTopicChip(topic: topic)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Loading skeleton

    private var searchSkeleton: some View {
        List {
            Section("People & Organizations") {
                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            }
            Section("Works") {
                ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
            }
        }
        .listStyle(.insetGrouped)
        .allowsHitTesting(false)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No results for \"\(vm.query)\"")
                .font(.headline)
            Text("Try a different spelling or search for a topic.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Error state

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Search unavailable")
                .font(.headline)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { vm.retry() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Creator Result Row

private struct CreatorResultRow: View {
    let creator: CatalogCreatorResult

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let url = creator.avatarUrl, let imgURL = URL(string: url) {
                    AsyncImage(url: imgURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarPlaceholder
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(creator.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if creator.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }

                    if creator.entityType == "organization" {
                        Image(systemName: "building.2")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(workCountLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if !creator.topics.isEmpty {
                    Text(creator.topics.prefix(3).joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var avatarPlaceholder: some View {
        Image(systemName: creator.entityType == "organization" ? "building.2" : "person.circle")
            .font(.system(size: 22))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(Circle())
    }

    private var workCountLabel: String {
        let count = creator.workCount
        if count == 0 { return "Creator" }
        return "\(count) published \(count == 1 ? "work" : "works")"
    }

    private var accessibilityLabel: String {
        var label = creator.displayName
        if creator.verified { label += ", verified" }
        label += ", \(workCountLabel)"
        return label
    }
}

// MARK: - Work Result Row

private struct WorkResultRow: View {
    let work: CatalogWorkResult

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            Group {
                if let url = work.coverUrl, let imgURL = URL(string: url) {
                    AsyncImage(url: imgURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        workIconPlaceholder
                    }
                } else {
                    workIconPlaceholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(work.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    WorkTypeBadge(type: work.type)
                    Text(work.creatorName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(work.title), \(work.type), by \(work.creatorName)")
    }

    private var workIconPlaceholder: some View {
        Image(systemName: workIcon(for: work.type))
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: 48, height: 48)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workIcon(for type: String) -> String {
        switch type {
        case "book":    return "book"
        case "album":   return "music.note"
        case "podcast": return "mic"
        case "episode": return "waveform"
        case "video":   return "play.rectangle"
        case "sermon":  return "cross"
        case "article": return "doc.text"
        case "course":  return "graduationcap"
        case "event":   return "calendar"
        default:        return "square.and.arrow.up"
        }
    }
}

// MARK: - Work Type Badge

private struct WorkTypeBadge: View {
    let type: String

    var body: some View {
        Text(type.capitalized)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

// MARK: - Topic Chip

private struct CatalogTopicChip: View {
    let topic: TopicResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(topic.topicName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            if topic.creatorCount > 0 {
                Text("\(topic.creatorCount) creator\(topic.creatorCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("\(topic.topicName), \(topic.creatorCount) creators")
    }
}

// MARK: - Skeleton Row

private struct SkeletonRow: View {
    @State private var opacity: Double = 0.4

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 120, height: 12)
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                opacity = 0.9
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Work Detail Sheet (minimal wrapper — full detail owned by existing Catalog layer)

private struct CatalogWorkDetailSheet: View {
    let work: CatalogWorkResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Group {
                        if let url = work.coverUrl, let imgURL = URL(string: url) {
                            AsyncImage(url: imgURL) { img in img.resizable().scaledToFill() }
                            placeholder: { coverPlaceholder }
                        } else {
                            coverPlaceholder
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.title)
                            .font(.headline)
                        Text("By \(work.creatorName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        WorkTypeBadge(type: work.type)
                    }
                }
                .padding()

                if !work.topics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(work.topics, id: \.self) { topic in
                                Text(topic)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .navigationTitle("Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var coverPlaceholder: some View {
        Image(systemName: "doc.text")
            .font(.system(size: 28))
            .foregroundStyle(.secondary)
            .frame(width: 72, height: 72)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
