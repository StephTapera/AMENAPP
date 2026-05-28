import SwiftUI
import FirebaseAuth

struct AmenUniversalContentFeedView: View {
    enum Surface: String {
        case home
        case profile
        case search
    }

    let surface: Surface
    let ownerId: String?
    let query: String?

    @State private var nodes: [ContentNode] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    init(surface: Surface = .home, ownerId: String? = nil, query: String? = nil) {
        self.surface = surface
        self.ownerId = ownerId
        self.query = query
    }

    var body: some View {
        Group {
            if !AMENFeatureFlags.shared.universalContentModelEnabled {
                unavailableState(
                    title: "Universal content is unavailable",
                    systemImage: "switch.2",
                    message: "This surface is still gated for rollout. Existing Amen feeds remain available."
                )
            } else if Auth.auth().currentUser == nil {
                unavailableState(
                    title: "Sign in to view content",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    message: "Amen only loads universal content for authenticated sessions."
                )
            } else if isLoading && !hasLoaded {
                loadingState
            } else if let errorMessage {
                errorState(errorMessage)
            } else if nodes.isEmpty {
                emptyState
            } else {
                contentList
            }
        }
        .task(id: loadIdentity) {
            await loadContent()
        }
        .refreshable {
            await loadContent(force: true)
        }
    }

    private var loadIdentity: String {
        [surface.rawValue, ownerId ?? "", query ?? ""].joined(separator: ":")
    }

    private var contentList: some View {
        VStack(spacing: 0) {
            ForEach(nodes) { node in
                AmenContentRenderer(node: node)
                    .padding(.horizontal, surface == .home ? 0 : 16)
                    .padding(.vertical, surface == .home ? 0 : 8)

                if AMENFeatureFlags.shared.postDividerEnabled {
                    FeedPostDivider()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading content...")
                .font(.systemScaled(14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading universal content")
    }

    private var emptyState: some View {
        unavailableState(
            title: emptyTitle,
            systemImage: "doc.text.magnifyingglass",
            message: emptyMessage
        )
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label("Couldn’t load content", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }

            Button("Retry") {
                Task { await loadContent(force: true) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Retry loading universal content")
        }
        .padding(.vertical, 32)
    }

    private func unavailableState(title: String, systemImage: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, surface == .home ? 48 : 24)
    }

    @MainActor
    private func loadContent(force: Bool = false) async {
        guard AMENFeatureFlags.shared.universalContentModelEnabled else {
            nodes = []
            hasLoaded = true
            return
        }

        guard Auth.auth().currentUser != nil else {
            nodes = []
            hasLoaded = true
            return
        }

        if isLoading && !force { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let service = AmenUniversalContentService.shared
            switch surface {
            case .home:
                nodes = try await service.fetchFeed(limit: 30)
                AMENAnalyticsService.shared.track(.homeFeedLoadSucceeded(postCount: nodes.count))
            case .profile:
                guard let ownerId, !ownerId.isEmpty else {
                    nodes = []
                    return
                }
                nodes = try await service.fetchProfileContent(ownerId: ownerId, limit: 40)
            case .search:
                let trimmed = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    nodes = []
                    return
                }
                nodes = try await service.keywordSearch(trimmed, limit: 20)
            }
        } catch {
            errorMessage = error.localizedDescription
            if surface == .home {
                AMENAnalyticsService.shared.track(.homeFeedLoadFailed(reason: String(error.localizedDescription.prefix(80))))
            }
        }
    }

    private var emptyTitle: String {
        switch surface {
        case .home: return "No approved content yet"
        case .profile: return "No published universal content"
        case .search: return "No universal content found"
        }
    }

    private var emptyMessage: String {
        switch surface {
        case .home:
            return "Approved public content will appear here after moderation."
        case .profile:
            return "Published profile content appears here after it passes moderation."
        case .search:
            return "Try another term, or search existing Amen results below."
        }
    }

    private var accessibilityTitle: String {
        switch surface {
        case .home: return "Universal content feed"
        case .profile: return "Universal profile content"
        case .search: return "Universal search content results"
        }
    }
}
