// ArgumentNodeView.swift — AMEN App
// Recursive glass card for displaying argument tree nodes.

import SwiftUI

struct ArgumentNodeView: View {
    let node: DiscussionNode
    let depth: Int
    @ObservedObject var vm: ReasoningViewModel
    let onReply: (String) -> Void
    /// IDs of ancestor nodes in the current render path — prevents circular-reference stack overflow.
    var seenIds: Set<String> = []

    // Maximum nesting depth to display
    private let maxDisplayDepth = 3

    // MARK: - Accent color for node type

    private var accentColor: Color {
        switch node.nodeType {
        case .argument:        return Color(red: 0.55, green: 0.25, blue: 1.0)
        case .counterargument: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .evidence:        return Color(red: 0.25, green: 0.88, blue: 0.56)
        case .viewUpdate:      return Color.black.opacity(0.55)
        }
    }

    private var nodeTypeColor: Color {
        switch node.nodeType {
        case .argument:        return Color(red: 0.55, green: 0.25, blue: 1.0)
        case .counterargument: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .evidence:        return Color(red: 0.25, green: 0.88, blue: 0.56)
        case .viewUpdate:      return Color.black.opacity(0.45)
        }
    }

    // MARK: - Time ago helper

    private var timeAgo: String {
        guard let date = node.createdAt else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nodeCard

            // Recursive children — only if within display depth and not circular
            if depth < maxDisplayDepth, let currentId = node.id, !seenIds.contains(currentId) {
                let nextSeenIds = seenIds.union([currentId])
                let childNodes = vm.children(of: currentId)
                    .filter { child in
                        guard let childId = child.id else { return false }
                        return !nextSeenIds.contains(childId)
                    }
                if !childNodes.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(childNodes) { child in
                            ArgumentNodeView(
                                node: child,
                                depth: depth + 1,
                                vm: vm,
                                onReply: onReply,
                                seenIds: nextSeenIds
                            )
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.top, 6)
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
    }

    // MARK: - Node Card

    private var nodeCard: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left accent bar
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                // Author row
                authorRow

                // Claim text
                Text(node.claim)
                    .font(.systemScaled(15))
                    .foregroundColor(.black.opacity(0.86))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                // Evidence bullets
                if !node.evidence.isEmpty {
                    evidenceBullets
                }

                // AI manipulation flags
                if !node.aiManipulationFlags.isEmpty {
                    manipulationFlags
                }

                // Action row
                actionRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.90), location: 0.0),
                                    .init(color: Color.white.opacity(0.72), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Author Row

    private var authorRow: some View {
        HStack(spacing: 8) {
            // Avatar
            Circle()
                .fill(accentColor.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String((node.authorName ?? "?").prefix(1)).uppercased())
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundColor(accentColor)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(node.authorName ?? "Anonymous")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.9))

                // Node type label
                HStack(spacing: 4) {
                    Image(systemName: node.nodeType.icon)
                        .font(.systemScaled(9))
                        .foregroundColor(nodeTypeColor)
                    Text(node.nodeType.label)
                        .font(.systemScaled(11))
                        .foregroundColor(nodeTypeColor)
                }
            }

            Spacer()

            if !timeAgo.isEmpty {
                Text(timeAgo)
                    .font(.systemScaled(11))
                    .foregroundColor(.black.opacity(0.35))
            }
        }
    }

    // MARK: - Evidence Bullets

    private var evidenceBullets: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(node.evidence, id: \.self) { item in
                HStack(alignment: .top, spacing: 5) {
                    Text("•")
                        .font(.systemScaled(11))
                        .foregroundColor(.black.opacity(0.4))
                    Text(item)
                        .font(.systemScaled(12))
                        .italic()
                        .foregroundColor(.black.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Manipulation Flags

    private var manipulationFlags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(node.aiManipulationFlags, id: \.self) { flag in
                    HStack(spacing: 4) {
                        Text("⚠")
                            .font(.systemScaled(10))
                        Text(flag.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.systemScaled(11, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.13))
                            .overlay(Capsule().strokeBorder(Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.25), lineWidth: 1))
                    )
                }
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 18) {
            // Upvote
            Button {
                Task { await vm.upvote(nodeId: node.id ?? "") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.systemScaled(12, weight: .semibold))
                    Text("\(node.votes)")
                        .font(.systemScaled(12, weight: .medium))
                }
                .foregroundColor(.black.opacity(0.55))
            }
            .buttonStyle(.plain)

            // Reply
            Button {
                if let nodeId = node.id {
                    onReply(nodeId)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.systemScaled(12))
                    Text("Reply")
                        .font(.systemScaled(12))
                }
                .foregroundColor(.black.opacity(0.45))
            }
            .buttonStyle(.plain)

            // "I changed my view" — only show for non-viewUpdate nodes
            if node.nodeType != .viewUpdate {
                Spacer()
                Button {
                    // Handled by showing AddArgumentSheet with .viewUpdate type pre-selected
                    if let nodeId = node.id {
                        onReply(nodeId)
                    }
                } label: {
                    Text("I changed my view")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundColor(Color(red: 0.25, green: 0.88, blue: 0.56).opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}
