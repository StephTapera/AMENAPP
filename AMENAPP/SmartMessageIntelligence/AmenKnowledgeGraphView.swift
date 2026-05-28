import SwiftUI

struct AmenKnowledgeGraphView: View {
    let personalNodes: [SmartKnowledgeNode]
    let spaceNodes: [SmartKnowledgeNode]
    var onAskBerean: (SmartKnowledgeNode) -> Void
    var onSearchRelated: (SmartKnowledgeNode) -> Void

    @State private var scope: SmartKnowledgeScope = .user

    var body: some View {
        List {
            Section {
                Picker("Memory", selection: $scope) {
                    Text("Personal").tag(SmartKnowledgeScope.user)
                    Text("Space").tag(SmartKnowledgeScope.space)
                }
                .pickerStyle(.segmented)
            }
            Section(scope == .user ? "Personal Memory" : "Shared Space Memory") {
                let activeNodes = scope == .user ? personalNodes : spaceNodes
                if activeNodes.isEmpty {
                    Text("No memory nodes yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(activeNodes) { node in
                        AmenKnowledgeNodeCard(node: node, onAskBerean: onAskBerean, onSearchRelated: onSearchRelated)
                    }
                }
            }
        }
        .navigationTitle("Knowledge Graph")
    }
}

struct AmenKnowledgeNodeCard: View {
    let node: SmartKnowledgeNode
    var onAskBerean: (SmartKnowledgeNode) -> Void
    var onSearchRelated: (SmartKnowledgeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(node.title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Text(node.nodeType.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            if !node.summary.isEmpty {
                Text(node.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            if !node.scriptureRefs.isEmpty { chipRow(node.scriptureRefs, icon: "book") }
            if !node.topics.isEmpty { chipRow(node.topics, icon: "tag") }
            HStack {
                Button("Ask Berean", systemImage: "sparkles") { onAskBerean(node) }
                Button("Search Related", systemImage: "magnifyingglass") { onSearchRelated(node) }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch node.nodeType {
        case "scripture": return "book"
        case "prayer": return "hands.sparkles"
        case "study": return "book.closed"
        case "question": return "questionmark.bubble"
        default: return "circle.hexagongrid"
        }
    }

    private func chipRow(_ items: [String], icon: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(items.prefix(8), id: \.self) { item in
                    Label(item, systemImage: icon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
        }
    }
}
