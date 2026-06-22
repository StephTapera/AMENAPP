import SwiftUI

struct RelationalGravityMapView: View {
    @StateObject private var service = RelationalGravityService.shared
    @State private var selectedNode: RelationalGravityNode?
    @State private var showAddNode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if service.nodes.isEmpty {
                    emptyState
                } else {
                    nodeList
                }
            }
            .navigationTitle("Relational Gravity")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddNode = true }) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Add relationship")
                }
            }
            .sheet(item: $selectedNode) { node in
                RelationshipDetailSheet(node: node)
            }
        }
    }

    private var nodeList: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Privacy banner
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Text("This is private. Only you can see this.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                ForEach(service.nodes) { node in
                    RelationshipStateCard(node: node, compact: false)
                        .padding(.horizontal, 20)
                        .onTapGesture { selectedNode = node }
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.systemScaled(40))
                .foregroundStyle(Color.secondary)
            Text("Your relational map is empty.")
                .font(.headline)
            Text("Track the health of your relationships privately.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

// MARK: - Relationship State Card

struct RelationshipStateCard: View {
    let node: RelationalGravityNode
    let compact: Bool

    var body: some View {
        HStack(spacing: 14) {
            // State indicator
            Circle()
                .fill(stateColor.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: node.currentState.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(stateColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(node.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text("\(node.currentState.displayName) · \(node.relationshipType.displayName)")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                if !compact && !node.unresolvedThreadIds.isEmpty {
                    Text("\(node.unresolvedThreadIds.count) unresolved")
                        .font(.caption)
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
            }

            Spacer()

            if !compact {
                scoreBar
            }
        }
        .padding(compact ? 12 : 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.displayName). Relationship state: \(node.currentState.displayName). Type: \(node.relationshipType.displayName).")
    }

    private var stateColor: Color {
        switch node.currentState {
        case .peaceful: return .green
        case .growing: return .blue
        case .tense: return .orange
        case .drifting: return .gray
        case .unresolved: return .red.opacity(0.7)
        case .needsPrayer: return .purple.opacity(0.7)
        }
    }

    private var scoreBar: some View {
        VStack(alignment: .trailing, spacing: 4) {
            miniBar(value: node.encouragementScore, color: .green, label: "Encourage")
            miniBar(value: node.conflictScore, color: .orange, label: "Conflict")
        }
    }

    private func miniBar(value: Double, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.systemScaled(8))
                .foregroundStyle(Color.secondary)
            Capsule()
                .fill(color.opacity(0.3))
                .frame(width: 40, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: 40 * value)
                }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Relationship Detail Sheet

struct RelationshipDetailSheet: View {
    let node: RelationalGravityNode
    @StateObject private var service = RelationalGravityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var reconciliationPrompt: String?
    @State private var isLoadingPrompt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    RelationshipStateCard(node: node, compact: false)
                        .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        actionButton(label: "Pray for \(node.displayName)", icon: "hands.sparkles") {
                            Task { await service.prayForPerson(node) }
                        }

                        if node.currentState == .tense || node.currentState == .unresolved {
                            actionButton(label: "Get reconciliation help", icon: "arrow.trianglehead.2.clockwise") {
                                Task { await loadReconciliationPrompt() }
                            }
                        }

                        if let prompt = reconciliationPrompt {
                            Text(prompt)
                                .font(.body)
                                .foregroundStyle(Color.primary)
                                .padding(16)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .navigationTitle(node.displayName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func actionButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(width: 28)
                Text(label)
                    .font(.body.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .foregroundStyle(Color.primary)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityLabel(label)
    }

    private func loadReconciliationPrompt() async {
        isLoadingPrompt = true
        reconciliationPrompt = await service.getReconciliationPrompt(for: node)
        isLoadingPrompt = false
    }
}
