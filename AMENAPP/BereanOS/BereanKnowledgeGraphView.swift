// BereanKnowledgeGraphView.swift
// AMENAPP — Berean OS

import SwiftUI

struct BereanKnowledgeGraphView: View {
    @StateObject private var service = BereanKnowledgeGraphService.shared

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.bereanOSKnowledgeGraphEnabled {
                mainContent
            } else {
                ContentUnavailableView(
                    "Knowledge Graph",
                    systemImage: "network",
                    description: Text("Coming soon")
                )
            }
        }
        .navigationTitle("Knowledge Graph")
        .navigationBarTitleDisplayMode(.large)
    }

    private var mainContent: some View {
        List(service.nodes) { node in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: nodeIcon(node.nodeType))
                        .foregroundStyle(Color.accentColor)
                    Text(node.title)
                        .font(.headline)
                }
                Text(node.nodeType.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !node.linkedNodeIds.isEmpty {
                    Text("\(node.linkedNodeIds.count) connection(s)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func nodeIcon(_ type: BereanKnowledgeNodeType) -> String {
        switch type {
        case .concept:   return "lightbulb.fill"
        case .scripture: return "book.fill"
        case .person:    return "person.fill"
        case .event:     return "calendar"
        case .place:     return "mappin.circle.fill"
        case .theme:     return "tag.fill"
        case .question:  return "questionmark.circle.fill"
        }
    }
}
