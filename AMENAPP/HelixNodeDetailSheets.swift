// HelixNodeDetailSheets.swift
// AMENAPP
//
// HelixNodeDetailSheet and HelixAddNodeSheet for the Helix org graph.

import SwiftUI
import FirebaseFirestore

// MARK: - HelixNodeDetailSheet

struct HelixNodeDetailSheet: View {

    let node: HelixNode
    let allNodes: [HelixNode]

    @Environment(\.dismiss) private var dismiss

    private var connectedNodes: [HelixNode] {
        allNodes.filter { n in
            guard let id = n.id else { return false }
            return node.connectedNodeIds.contains(id)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Header
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(node.type.color.opacity(0.18))
                                    .frame(width: 80, height: 80)
                                Image(systemName: node.type.icon)
                                    .font(.systemScaled(34))
                                    .foregroundColor(node.type.color)
                            }

                            Text(node.label)
                                .font(AMENFont.bold(22))
                                .foregroundColor(.white)

                            // Health badge
                            HStack(spacing: 5) {
                                Image(systemName: node.health.icon)
                                    .font(.systemScaled(12))
                                Text(node.health.label)
                                    .font(AMENFont.semiBold(12))
                            }
                            .foregroundColor(node.health.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(node.health.color.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // Description
                        if let desc = node.description, !desc.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(AMENFont.semiBold(13))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(desc)
                                    .font(AMENFont.regular(15))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }

                        // Connected To
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connected to")
                                .font(AMENFont.semiBold(13))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 4)

                            if node.connectedNodeIds.isEmpty {
                                Text("No connections yet")
                                    .font(AMENFont.regular(14))
                                    .foregroundColor(.white.opacity(0.35))
                                    .padding(.horizontal, 4)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(node.connectedNodeIds, id: \.self) { connectedId in
                                        let connectedNode = allNodes.first { $0.id == connectedId }
                                        HStack(spacing: 10) {
                                            let type = connectedNode?.type ?? .project
                                            ZStack {
                                                Circle()
                                                    .fill(type.color.opacity(0.18))
                                                    .frame(width: 34, height: 34)
                                                Image(systemName: type.icon)
                                                    .font(.systemScaled(14))
                                                    .foregroundColor(type.color)
                                            }
                                            Text(connectedNode?.label ?? "Node \(connectedId.prefix(6))")
                                                .font(AMENFont.regular(14))
                                                .foregroundColor(.white)
                                            Spacer()
                                            if let health = connectedNode?.health {
                                                Circle()
                                                    .fill(health.color)
                                                    .frame(width: 8, height: 8)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }

                        // Last Activity
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last activity")
                                .font(AMENFont.semiBold(13))
                                .foregroundColor(.white.opacity(0.5))
                            if let created = node.createdAt {
                                Text(created.formatted(date: .abbreviated, time: .shortened))
                                    .font(AMENFont.regular(14))
                                    .foregroundColor(.white.opacity(0.7))
                            } else {
                                Text("Unknown")
                                    .font(AMENFont.regular(14))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                        // Actions
                        HStack(spacing: 12) {
                            Button {
                                // placeholder: navigate to edit
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                    Text("Edit")
                                        .font(AMENFont.semiBold(14))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "6B48FF").opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(hex: "6B48FF").opacity(0.4), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(CoCreationPressStyle())

                            Button {
                                // placeholder: delete action
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                    Text("Delete")
                                        .font(AMENFont.semiBold(14))
                                }
                                .foregroundColor(Color(hex: "EF4444"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "EF4444").opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(hex: "EF4444").opacity(0.3), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(CoCreationPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(node.type.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "6B48FF"))
                }
            }
            .toolbarBackground(Color(hex: "0A0A0F"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - HelixAddNodeSheet

struct HelixAddNodeSheet: View {

    @ObservedObject var vm: HelixViewModel
    let workspaceId: String

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: HelixNodeType = .project
    @State private var label: String = ""
    @State private var description: String = ""
    @State private var selectedHealth: HelixHealth = .onTrack
    @State private var selectedConnections: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var typePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Node Type")
                .font(AMENFont.semiBold(13))
                .foregroundColor(.white.opacity(0.5))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(HelixNodeType.allCases, id: \.self) { type in
                    let isSelected = selectedType == type
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedType = type
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.icon)
                                .font(.systemScaled(22))
                                .foregroundColor(isSelected ? type.color : .white.opacity(0.5))
                            Text(type.label)
                                .font(AMENFont.regular(12))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isSelected ? type.color.opacity(0.18) : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? type.color.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .scaleEffect(isSelected ? 1.04 : 1.0)
                    }
                    .buttonStyle(CoCreationPressStyle())
                }
            }
        }
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Label")
                .font(AMENFont.semiBold(13))
                .foregroundColor(.white.opacity(0.5))
            TextField("Node label...", text: $label)
                .font(AMENFont.regular(15))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description (optional)")
                .font(AMENFont.semiBold(13))
                .foregroundColor(.white.opacity(0.5))
            TextField("Short description...", text: $description, axis: .vertical)
                .font(AMENFont.regular(15))
                .foregroundColor(.white)
                .lineLimit(3, reservesSpace: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        if selectedType == .project || selectedType == .goal {
            VStack(alignment: .leading, spacing: 10) {
                Text("Health")
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.white.opacity(0.5))

                HStack(spacing: 8) {
                    ForEach(HelixHealth.allCases, id: \.self) { health in
                        let isSelected = selectedHealth == health
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedHealth = health
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: health.icon)
                                    .font(.systemScaled(11))
                                Text(health.label)
                                    .font(AMENFont.regular(12))
                            }
                            .foregroundColor(isSelected ? health.color : .white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(isSelected ? health.color.opacity(0.18) : Color.white.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? health.color.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(CoCreationPressStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectSection: some View {
        let validNodes = vm.nodes.filter { $0.id != nil }
        if !validNodes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connect to")
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.white.opacity(0.5))

                LazyVStack(spacing: 8) {
                    ForEach(validNodes) { existingNode in
                        let nodeId = existingNode.id!
                        let isConnected = selectedConnections.contains(nodeId)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if isConnected {
                                    selectedConnections.remove(nodeId)
                                } else {
                                    selectedConnections.insert(nodeId)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: existingNode.type.icon)
                                    .font(.systemScaled(14))
                                    .foregroundColor(existingNode.type.color)
                                Text(existingNode.label)
                                    .font(AMENFont.regular(14))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
                                    .font(.systemScaled(18))
                                    .foregroundColor(isConnected ? Color(hex: "10B981") : .white.opacity(0.25))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        isConnected ? Color(hex: "10B981").opacity(0.4) : Color.white.opacity(0.06),
                                        lineWidth: 0.5
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(CoCreationPressStyle())
                    }
                }
            }
        }
    }

    private var addNodeButton: some View {
        Button {
            addNode()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
                Text(isSaving ? "Adding..." : "Add Node")
                    .font(AMENFont.semiBold(16))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: label.trimmingCharacters(in: .whitespaces).isEmpty
                        ? [Color.gray.opacity(0.3), Color.gray.opacity(0.3)]
                        : [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(CoCreationPressStyle())
        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
        .padding(.top, 4)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        typePickerSection
                        labelSection
                        descriptionSection
                        healthSection
                        connectSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(AMENFont.regular(13))
                                .foregroundColor(Color(hex: "EF4444"))
                                .padding(.horizontal, 4)
                        }

                        addNodeButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .toolbarBackground(Color(hex: "0A0A0F"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func addNode() {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        let node = HelixNode(
            workspaceId: workspaceId,
            type: selectedType,
            label: trimmed,
            description: description.isEmpty ? nil : description,
            connectedNodeIds: Array(selectedConnections),
            health: selectedHealth
        )

        Task {
            do {
                try await vm.createNode(node)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

