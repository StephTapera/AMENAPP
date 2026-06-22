// FaithMusicGraphService.swift
// AMENAPP/MusicContentLayer
//
// In-memory Faith + Music knowledge graph service and recommendation UI.

import SwiftUI

// MARK: - Graph Types

enum FaithMusicGraphNodeType: String, Codable, Sendable {
    case song, album, artist, church, pastor, sermon, sermonSeries
    case scripture, topic, mood, community, post, event, playlist, prayerTheme

    var fallbackIcon: String {
        switch self {
        case .song:             return "music.note"
        case .album:            return "square.stack"
        case .artist:           return "person.fill"
        case .church:           return "building.columns.fill"
        case .pastor:           return "person.badge.key.fill"
        case .sermon:           return "mic.fill"
        case .sermonSeries:     return "list.bullet.rectangle.fill"
        case .scripture:        return "book.fill"
        case .topic:            return "tag.fill"
        case .mood:             return "face.smiling.fill"
        case .community:        return "person.3.fill"
        case .post:             return "square.and.pencil"
        case .event:            return "calendar"
        case .playlist:         return "music.note.list"
        case .prayerTheme:      return "hands.sparkles.fill"
        }
    }

    var displayLabel: String {
        switch self {
        case .song:             return "Song"
        case .album:            return "Album"
        case .artist:           return "Artist"
        case .church:           return "Church"
        case .pastor:           return "Pastor"
        case .sermon:           return "Sermon"
        case .sermonSeries:     return "Series"
        case .scripture:        return "Scripture"
        case .topic:            return "Topic"
        case .mood:             return "Mood"
        case .community:        return "Community"
        case .post:             return "Post"
        case .event:            return "Event"
        case .playlist:         return "Playlist"
        case .prayerTheme:      return "Prayer Theme"
        }
    }
}

struct FaithMusicGraphNode: Codable, Sendable, Identifiable {
    let id: String
    let type: FaithMusicGraphNodeType
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let deepLink: String
    let weight: Double         // engagement/relevance score
}

struct FaithMusicGraphEdge: Codable, Sendable, Identifiable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let relationLabel: String  // "featuredIn", "relatedTo", "sameArtist", "scriptureRef"
    let strength: Double       // 0.0–1.0
}

// MARK: - Faith Music Graph Service

@MainActor
final class FaithMusicGraphService: ObservableObject {

    @Published private(set) var recommendedNodes: [FaithMusicGraphNode] = []
    @Published private(set) var isLoading = false

    private var nodes: [String: FaithMusicGraphNode] = [:]
    private var edges: [FaithMusicGraphEdge] = []

    init() {
        seedMockData()
    }

    // MARK: - Public API

    func loadRelated(for nodeID: String, type: FaithMusicGraphNodeType) async {
        isLoading = true

        // Simulate lightweight async work (graph traversal)
        await Task.yield()

        let connectedEdges = edges.filter { $0.fromNodeID == nodeID || $0.toNodeID == nodeID }

        let connectedNodeIDs = connectedEdges.compactMap { edge -> String? in
            edge.fromNodeID == nodeID ? edge.toNodeID : edge.fromNodeID
        }

        // Build a map of nodeID -> max edge strength for sorting
        var strengthMap: [String: Double] = [:]
        for edge in connectedEdges {
            let targetID = edge.fromNodeID == nodeID ? edge.toNodeID : edge.fromNodeID
            strengthMap[targetID] = max(strengthMap[targetID] ?? 0, edge.strength)
        }

        let results: [FaithMusicGraphNode] = connectedNodeIDs
            .compactMap { nodes[$0] }
            .sorted { lhs, rhs in
                let lScore = (strengthMap[lhs.id] ?? 0) * lhs.weight
                let rScore = (strengthMap[rhs.id] ?? 0) * rhs.weight
                return lScore > rScore
            }

        recommendedNodes = results
        isLoading = false
    }

    func addNode(_ node: FaithMusicGraphNode) {
        nodes[node.id] = node
    }

    func addEdge(_ edge: FaithMusicGraphEdge) {
        edges.append(edge)
    }

    func search(query: String) async -> [FaithMusicGraphNode] {
        await Task.yield()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Array(nodes.values)
        }
        let lower = query.lowercased()
        return nodes.values.filter { node in
            node.title.lowercased().contains(lower) ||
            (node.subtitle?.lowercased().contains(lower) ?? false)
        }
    }

    // MARK: - Seed Data

    private func seedMockData() {
        // 10 Song nodes
        let songs: [FaithMusicGraphNode] = [
            .init(id: "song-1",  type: .song, title: "Way Maker",          subtitle: "Sinach",                    artworkURL: nil, deepLink: "amen://music/song-1",  weight: 0.95),
            .init(id: "song-2",  type: .song, title: "Goodness of God",    subtitle: "Bethel Music",              artworkURL: nil, deepLink: "amen://music/song-2",  weight: 0.92),
            .init(id: "song-3",  type: .song, title: "Oceans",             subtitle: "Hillsong United",           artworkURL: nil, deepLink: "amen://music/song-3",  weight: 0.90),
            .init(id: "song-4",  type: .song, title: "What a Beautiful Name", subtitle: "Hillsong Worship",       artworkURL: nil, deepLink: "amen://music/song-4",  weight: 0.93),
            .init(id: "song-5",  type: .song, title: "Reckless Love",      subtitle: "Cory Asbury",               artworkURL: nil, deepLink: "amen://music/song-5",  weight: 0.88),
            .init(id: "song-6",  type: .song, title: "New Wine",           subtitle: "Hillsong Worship",          artworkURL: nil, deepLink: "amen://music/song-6",  weight: 0.85),
            .init(id: "song-7",  type: .song, title: "King of Kings",      subtitle: "Hillsong Worship",          artworkURL: nil, deepLink: "amen://music/song-7",  weight: 0.87),
            .init(id: "song-8",  type: .song, title: "Evidence",           subtitle: "Josh Baldwin",              artworkURL: nil, deepLink: "amen://music/song-8",  weight: 0.82),
            .init(id: "song-9",  type: .song, title: "Holy Forever",       subtitle: "Brian Johnson",             artworkURL: nil, deepLink: "amen://music/song-9",  weight: 0.84),
            .init(id: "song-10", type: .song, title: "Battle Belongs",     subtitle: "Phil Wickham",              artworkURL: nil, deepLink: "amen://music/song-10", weight: 0.86),
        ]

        // 5 Sermon nodes
        let sermons: [FaithMusicGraphNode] = [
            .init(id: "sermon-1", type: .sermon, title: "Walking in Faith",       subtitle: "Pastor James Merritt", artworkURL: nil, deepLink: "amen://sermon/sermon-1", weight: 0.91),
            .init(id: "sermon-2", type: .sermon, title: "The Power of Praise",    subtitle: "Pastor Sarah Jakes",   artworkURL: nil, deepLink: "amen://sermon/sermon-2", weight: 0.89),
            .init(id: "sermon-3", type: .sermon, title: "Grace Abounding",        subtitle: "Charles Spurgeon",     artworkURL: nil, deepLink: "amen://sermon/sermon-3", weight: 0.88),
            .init(id: "sermon-4", type: .sermon, title: "Fear Not",               subtitle: "Max Lucado",           artworkURL: nil, deepLink: "amen://sermon/sermon-4", weight: 0.87),
            .init(id: "sermon-5", type: .sermon, title: "The Father's Heart",     subtitle: "Tim Keller",           artworkURL: nil, deepLink: "amen://sermon/sermon-5", weight: 0.93),
        ]

        // 4 Church nodes
        let churches: [FaithMusicGraphNode] = [
            .init(id: "church-1", type: .church, title: "Elevation Church",      subtitle: "Charlotte, NC",        artworkURL: nil, deepLink: "amen://church/church-1", weight: 0.94),
            .init(id: "church-2", type: .church, title: "Hillsong Church",        subtitle: "Sydney, AU",           artworkURL: nil, deepLink: "amen://church/church-2", weight: 0.92),
            .init(id: "church-3", type: .church, title: "Bethel Church",          subtitle: "Redding, CA",          artworkURL: nil, deepLink: "amen://church/church-3", weight: 0.91),
            .init(id: "church-4", type: .church, title: "Life.Church",            subtitle: "Edmond, OK",           artworkURL: nil, deepLink: "amen://church/church-4", weight: 0.90),
        ]

        // 5 Scripture topic nodes
        let scriptureTopics: [FaithMusicGraphNode] = [
            .init(id: "scripture-1", type: .scripture, title: "Psalm 23",       subtitle: "The Lord is my shepherd", artworkURL: nil, deepLink: "amen://scripture/psalm-23",    weight: 0.97),
            .init(id: "scripture-2", type: .scripture, title: "Isaiah 40:31",   subtitle: "Those who hope in the Lord", artworkURL: nil, deepLink: "amen://scripture/isaiah-40-31", weight: 0.95),
            .init(id: "scripture-3", type: .scripture, title: "Philippians 4:13", subtitle: "I can do all things",   artworkURL: nil, deepLink: "amen://scripture/phil-4-13",   weight: 0.96),
            .init(id: "scripture-4", type: .scripture, title: "Romans 8:28",    subtitle: "All things work together",  artworkURL: nil, deepLink: "amen://scripture/romans-8-28", weight: 0.94),
            .init(id: "scripture-5", type: .scripture, title: "John 3:16",      subtitle: "For God so loved the world", artworkURL: nil, deepLink: "amen://scripture/john-3-16", weight: 0.99),
        ]

        for node in songs + sermons + churches + scriptureTopics {
            nodes[node.id] = node
        }

        // Seed edges
        let seedEdges: [FaithMusicGraphEdge] = [
            .init(id: "e-1",  fromNodeID: "song-1",    toNodeID: "scripture-1", relationLabel: "scriptureRef",  strength: 0.9),
            .init(id: "e-2",  fromNodeID: "song-2",    toNodeID: "scripture-4", relationLabel: "scriptureRef",  strength: 0.85),
            .init(id: "e-3",  fromNodeID: "song-3",    toNodeID: "sermon-1",   relationLabel: "featuredIn",     strength: 0.8),
            .init(id: "e-4",  fromNodeID: "song-4",    toNodeID: "church-2",   relationLabel: "relatedTo",      strength: 0.95),
            .init(id: "e-5",  fromNodeID: "song-6",    toNodeID: "church-2",   relationLabel: "sameArtist",     strength: 0.93),
            .init(id: "e-6",  fromNodeID: "song-7",    toNodeID: "church-2",   relationLabel: "sameArtist",     strength: 0.91),
            .init(id: "e-7",  fromNodeID: "sermon-2",  toNodeID: "scripture-3", relationLabel: "scriptureRef",  strength: 0.88),
            .init(id: "e-8",  fromNodeID: "sermon-3",  toNodeID: "scripture-5", relationLabel: "scriptureRef",  strength: 0.90),
            .init(id: "e-9",  fromNodeID: "church-1",  toNodeID: "sermon-4",   relationLabel: "featuredIn",     strength: 0.85),
            .init(id: "e-10", fromNodeID: "church-3",  toNodeID: "song-2",     relationLabel: "relatedTo",      strength: 0.88),
            .init(id: "e-11", fromNodeID: "scripture-2", toNodeID: "song-5",   relationLabel: "relatedTo",      strength: 0.82),
            .init(id: "e-12", fromNodeID: "sermon-5",  toNodeID: "scripture-5", relationLabel: "scriptureRef",  strength: 0.94),
            .init(id: "e-13", fromNodeID: "song-9",    toNodeID: "church-3",   relationLabel: "relatedTo",      strength: 0.86),
            .init(id: "e-14", fromNodeID: "song-10",   toNodeID: "sermon-2",   relationLabel: "featuredIn",     strength: 0.79),
            .init(id: "e-15", fromNodeID: "church-4",  toNodeID: "sermon-1",   relationLabel: "featuredIn",     strength: 0.83),
        ]
        edges = seedEdges
    }
}

// MARK: - Faith Music Recommendation Row

struct FaithMusicRecommendationRow: View {
    let nodes: [FaithMusicGraphNode]
    let title: String
    let onNodeTap: (FaithMusicGraphNode) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 20)

            if nodes.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(nodes) { node in
                    NodeCard(node: node, reduceTransparency: reduceTransparency)
                        .onTapGesture {
                            onNodeTap(node)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(node.type.displayLabel): \(node.title)\(node.subtitle.map { ", \($0)" } ?? "")")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Double tap to open \(node.title)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No recommendations yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .accessibilityLabel("No recommendations available")
    }
}

// MARK: - Node Card

private struct NodeCard: View {
    let node: FaithMusicGraphNode
    let reduceTransparency: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Artwork / fallback
            ZStack {
                if let artworkURL = node.artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            fallbackArtwork
                        }
                    }
                } else {
                    fallbackArtwork
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Title
            Text(node.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)

            // Type pill
            Text(node.type.displayLabel)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(Color.accentColor)
        }
        .padding(10)
        .background {
            if reduceTransparency {
                Color(.secondarySystemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private var fallbackArtwork: some View {
        ZStack {
            Color.accentColor.opacity(0.12)
            Image(systemName: node.type.fallbackIcon)
                .font(.title2)
                .foregroundStyle(Color.accentColor.opacity(0.7))
        }
    }
}

// MARK: - Preview

#Preview("Faith Music Recommendations") {
    let service = FaithMusicGraphService()
    ScrollView {
        VStack(spacing: 24) {
            FaithMusicRecommendationRow(
                nodes: Array(
                    [
                        FaithMusicGraphNode(id: "s1", type: .song,    title: "Way Maker",           subtitle: "Sinach",           artworkURL: nil, deepLink: "", weight: 0.9),
                        FaithMusicGraphNode(id: "s2", type: .sermon,  title: "Walking in Faith",    subtitle: "Pastor James",     artworkURL: nil, deepLink: "", weight: 0.88),
                        FaithMusicGraphNode(id: "s3", type: .church,  title: "Elevation Church",    subtitle: "Charlotte, NC",    artworkURL: nil, deepLink: "", weight: 0.92),
                        FaithMusicGraphNode(id: "s4", type: .scripture, title: "Psalm 23",          subtitle: "The Lord is my shepherd", artworkURL: nil, deepLink: "", weight: 0.97),
                    ]
                ),
                title: "Related Content",
                onNodeTap: { node in print("Tapped: \(node.title)") }
            )

            FaithMusicRecommendationRow(
                nodes: [],
                title: "Trending Now",
                onNodeTap: { _ in }
            )
        }
        .padding(.vertical, 20)
    }
    .environmentObject(service)
    .background(Color(.systemGroupedBackground))
}
