// BereanMemoryStripView.swift
// AMENAPP
//
// Collapsible horizontal thread-memory node strip shown above the session counter bar.

import SwiftUI

struct BereanMemoryNode: Identifiable {
    let id: UUID
    let emoji: String
    let label: String
    let messageIndex: Int
    let color: Color
    let borderColor: Color
}

struct BereanMemoryStripView: View {
    let nodes: [BereanMemoryNode]
    let onNodeTap: (BereanMemoryNode) -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Expand/collapse header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    isExpanded.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Text("🧠")
                        .font(.system(size: 13))
                    Text("Context window")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("·  \(nodes.count) topic\(nodes.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            // Node strip
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                            HStack(spacing: 0) {
                                VStack(spacing: 3) {
                                    Circle()
                                        .fill(node.color)
                                        .frame(width: 36, height: 36)
                                        .overlay(Circle().strokeBorder(node.borderColor, lineWidth: 1.5))
                                        .overlay(Text(node.emoji).font(.system(size: 15)))
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            onNodeTap(node)
                                        }
                                    Text(node.label)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color(.secondaryLabel))
                                        .lineLimit(1)
                                        .frame(width: 44)
                                }
                                .frame(width: 44)

                                if index < nodes.count - 1 {
                                    Rectangle()
                                        .fill(Color(.separator))
                                        .frame(width: 16, height: 1.5)
                                        .offset(y: -10)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Topic classifier

func bereanTopicMeta(for text: String) -> (emoji: String, label: String, color: Color, border: Color) {
    let lower = text.lowercased()
    if lower.contains("faith") || lower.contains("scripture") || lower.contains("bible") || lower.contains("god") || lower.contains("jesus") {
        return ("✝️", "Faith", Color.purple.opacity(0.1), Color.purple.opacity(0.4))
    } else if lower.contains("business") || lower.contains("revenue") || lower.contains("startup") || lower.contains("market") {
        return ("💼", "Business", Color.green.opacity(0.1), Color.green.opacity(0.4))
    } else if lower.contains("ai") || lower.contains("tech") || lower.contains("software") || lower.contains("code") {
        return ("⚡", "Tech", Color.blue.opacity(0.1), Color.blue.opacity(0.4))
    } else if lower.contains("prayer") || lower.contains("pray") {
        return ("🙏", "Prayer", Color.red.opacity(0.08), Color.red.opacity(0.35))
    } else if lower.contains("habit") || lower.contains("life") || lower.contains("relationship") {
        return ("🌱", "Life", Color(hex: "#e07050").opacity(0.1), Color(hex: "#e07050").opacity(0.4))
    }
    return ("💬", "General", Color(.systemGray5), Color(.separator))
}
