import SwiftUI

struct KnowledgeMapView: View {

    let creatorId: String

    @StateObject private var vm: CatalogViewModel
    @State private var selectedTopic: String? = nil
    @State private var topicWorks: [CatalogWork] = []
    @State private var isLoadingTopic = false
    @State private var isLocked = false

    init(creatorId: String) {
        self.creatorId = creatorId
        _vm = StateObject(wrappedValue: CatalogViewModel(creatorId: creatorId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLocked {
                    CatalogEntitlementGateView(feature: .knowledgeMap)
                } else {
                    mapContent
                }
            }
            .padding(16)
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private var mapContent: some View {
        switch vm.state {
        case .loading:
            loadingView

        case .empty:
            emptyView

        case .syncing:
            syncingView

        case .populated:
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Knowledge Topics")
                        .font(.systemScaled(17, weight: .semibold))
                    Text("Tap a topic to explore related works")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }

                topicCapsules

                if let topic = selectedTopic {
                    topicDetailSection(topic: topic)
                }
            }

        case .error(let message):
            errorView(message: message)

        case .locked:
            CatalogEntitlementGateView(feature: .knowledgeMap)
        }
    }

    // MARK: - Topic Capsules (FlowLayout approximation)

    private var topicCapsules: some View {
        let nodes = vm.knowledgeNodes
        return FlowCapsuleLayout(nodes: nodes, selectedTopic: $selectedTopic) { topic in
            Task {
                isLoadingTopic = true
                topicWorks = await CatalogService.shared.fetchWorksByTopic(creatorId: creatorId, topic: topic)
                isLoadingTopic = false
            }
        }
    }

    // MARK: - Topic Detail

    @ViewBuilder
    private func topicDetailSection(topic: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(topic)
                    .font(.systemScaled(15, weight: .semibold))
                Spacer()
                Button {
                    selectedTopic = nil
                    topicWorks = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if isLoadingTopic {
                HStack {
                    ProgressView()
                    Text("Loading works...")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }
            } else if topicWorks.isEmpty {
                Text("No published works in this topic.")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topicWorks) { work in
                    topicWorkRow(work: work)
                }
            }
        }
        .padding(14)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func topicWorkRow(work: CatalogWork) -> some View {
        HStack(spacing: 10) {
            Image(systemName: work.type.icon)
                .font(.systemScaled(14, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(work.title)
                    .font(.systemScaled(13, weight: .medium))
                    .lineLimit(1)
                Text(work.type.displayName)
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Mapping knowledge...")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No topics yet")
                .font(.systemScaled(16, weight: .medium))
            Text("Topics will appear as this creator publishes more works.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var syncingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Building knowledge map...")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Couldn't load knowledge map")
                .font(.systemScaled(16, weight: .medium))
            Text(message)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await vm.load() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - FlowCapsuleLayout

struct FlowCapsuleLayout: View {

    let nodes: [KnowledgeNode]
    @Binding var selectedTopic: String?
    var onSelect: (String) -> Void

    var body: some View {
        if nodes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.systemScaled(36))
                    .foregroundStyle(.secondary)
                Text("No topics found")
                    .font(.subheadline.bold())
                Text("Try a different search or explore all content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(nodes) { node in
                    topicCapsule(node: node)
                }
            }
        }
    }

    private func topicCapsule(node: KnowledgeNode) -> some View {
        let isSelected = selectedTopic == node.topic
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if selectedTopic == node.topic {
                    selectedTopic = nil
                } else {
                    selectedTopic = node.topic
                    onSelect(node.topic)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(node.topic)
                    .font(.systemScaled(13, weight: .medium))
                    .lineLimit(1)
                Text("\(node.workCount)")
                    .font(.systemScaled(11))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(isSelected ? Color(UIColor.systemBackground).opacity(0.25) : .secondary.opacity(0.15)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(.primary)
                } else {
                    Capsule().fill(.secondary.opacity(0.08))
                }
            }
            .foregroundStyle(isSelected ? Color(UIColor.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
    }
}
