// HelixGraphView.swift
// AMENAPP
//
// Full-screen interactive org graph canvas for Helix, plus HelixGraphViewModel.

import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - HelixGraphViewModel

class HelixGraphViewModel: ObservableObject {

    @Published var nodes: [HelixNode] = []
    @Published var edges: [HelixEdge] = []
    @Published var selectedNodeId: String? = nil
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published var activeTypeFilters: Set<HelixNodeType> = Set(HelixNodeType.allCases)

    // MARK: - Load

    func load(nodes: [HelixNode]) {
        self.nodes = nodes
        self.edges = computeEdges(from: nodes)
        dlog("HelixGraphViewModel: loaded \(nodes.count) nodes, \(edges.count) edges")
    }

    // MARK: - Edges

    private func computeEdges(from nodes: [HelixNode]) -> [HelixEdge] {
        var result: [HelixEdge] = []
        for node in nodes {
            guard let sourceId = node.id else { continue }
            for targetId in node.connectedNodeIds {
                result.append(HelixEdge(sourceId: sourceId, targetId: targetId))
            }
        }
        return result
    }

    // MARK: - Position

    func position(for nodeId: String, in size: CGSize) -> CGPoint {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let count = max(nodes.count, 1)
        let angle = Double(index) * (2 * .pi / Double(count)) - (.pi / 2)
        let radius = min(size.width, size.height) * 0.34
        return CGPoint(
            x: size.width / 2 + radius * CGFloat(cos(angle)),
            y: size.height / 2 + radius * CGFloat(sin(angle))
        )
    }

    // MARK: - Hit Test

    func nodeId(at point: CGPoint, in size: CGSize) -> String? {
        let hitRadius: CGFloat = 28
        for node in nodes {
            guard let id = node.id else { continue }
            let pos = position(for: id, in: size)
            let dx = point.x - pos.x
            let dy = point.y - pos.y
            if sqrt(dx * dx + dy * dy) <= hitRadius {
                return id
            }
        }
        return nil
    }

    // MARK: - Filtered Nodes

    var visibleNodes: [HelixNode] {
        nodes.filter { activeTypeFilters.contains($0.type) }
    }
}

// MARK: - HelixGraphView

struct HelixGraphView: View {

    @ObservedObject var vm: HelixViewModel
    @StateObject private var graphVM = HelixGraphViewModel()

    @State private var showAddNode = false
    @State private var selectedNode: HelixNode? = nil
    @State private var canvasSize: CGSize = .zero

    // Gesture state
    @GestureState private var magnifyState: CGFloat = 1.0
    @GestureState private var dragState: CGSize = .zero

    private func graphCanvas(in canvasSize: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            let visibleIds = Set(graphVM.visibleNodes.compactMap { $0.id })

            // Draw edges
            for edge in graphVM.edges {
                guard visibleIds.contains(edge.sourceId),
                      visibleIds.contains(edge.targetId) else { continue }

                let from = graphVM.position(for: edge.sourceId, in: canvasSize)
                let to   = graphVM.position(for: edge.targetId, in: canvasSize)

                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                ctx.stroke(
                    path,
                    with: .color(.white.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                )
            }

            // Draw nodes
            for node in graphVM.visibleNodes {
                guard let id = node.id else { continue }
                let pos = graphVM.position(for: id, in: canvasSize)
                let isSelected = graphVM.selectedNodeId == id
                let diameter: CGFloat = isSelected ? 52 : 40

                // Glow for selected
                if isSelected {
                    let glowRect = CGRect(
                        x: pos.x - 30, y: pos.y - 30,
                        width: 60, height: 60
                    )
                    ctx.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(node.type.color.opacity(0.3))
                    )
                }

                // Node circle
                let rect = CGRect(
                    x: pos.x - diameter / 2,
                    y: pos.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(node.type.color))

                // Health ring
                let ringRect = CGRect(
                    x: pos.x - diameter / 2 - 2,
                    y: pos.y - diameter / 2 - 2,
                    width: diameter + 4,
                    height: diameter + 4
                )
                ctx.stroke(
                    Path(ellipseIn: ringRect),
                    with: .color(node.health.color.opacity(0.7)),
                    lineWidth: 2
                )
            }
        }
        .scaleEffect(graphVM.scale * magnifyState)
        .offset(
            x: graphVM.offset.width + dragState.width,
            y: graphVM.offset.height + dragState.height
        )
        .gesture(
            MagnificationGesture()
                .updating($magnifyState) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    graphVM.scale = max(0.3, min(graphVM.scale * value, 4.0))
                }
        )
        .simultaneousGesture(
            DragGesture()
                .updating($dragState) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    graphVM.offset = CGSize(
                        width: graphVM.offset.width + value.translation.width,
                        height: graphVM.offset.height + value.translation.height
                    )
                }
        )
    }

    private func nodeLabelsOverlay(in size: CGSize) -> some View {
        ForEach(graphVM.visibleNodes) { node in
            if let id = node.id {
                let pos = graphVM.position(for: id, in: size)
                Text(node.label)
                    .font(AMENFont.regular(11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .position(
                        x: (pos.x + graphVM.offset.width + dragState.width) * (graphVM.scale * magnifyState),
                        y: ((pos.y + 28) + graphVM.offset.height + dragState.height) * (graphVM.scale * magnifyState)
                    )
            }
        }
    }

    private func tapGestureOverlay(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { tapPoint in
                // Invert transform to find canvas coordinates
                let currentScale = graphVM.scale * magnifyState
                let adjustedPoint = CGPoint(
                    x: tapPoint.x / currentScale - graphVM.offset.width - dragState.width,
                    y: tapPoint.y / currentScale - graphVM.offset.height - dragState.height
                )
                if let hitId = graphVM.nodeId(at: adjustedPoint, in: size) {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        graphVM.selectedNodeId = hitId
                    }
                    selectedNode = graphVM.nodes.first { $0.id == hitId }
                } else {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        graphVM.selectedNodeId = nil
                    }
                }
            }
    }

    private var zoomControls: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                            graphVM.scale = min(graphVM.scale * 1.25, 4.0)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 36, height: 36)
                    }
                    Divider().background(Color.white.opacity(0.1))
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                            graphVM.scale = max(graphVM.scale * 0.8, 0.3)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 36, height: 36)
                    }
                }
                .foregroundColor(.white)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.trailing, 16)
                .padding(.top, 16)
            }
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                // Type filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(HelixNodeType.allCases, id: \.self) { type in
                            let isActive = graphVM.activeTypeFilters.contains(type)
                            Button {
                                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7))) {
                                    if isActive {
                                        graphVM.activeTypeFilters.remove(type)
                                    } else {
                                        graphVM.activeTypeFilters.insert(type)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: type.icon)
                                        .font(.systemScaled(12))
                                    Text(type.label)
                                        .font(AMENFont.regular(13))
                                }
                                .foregroundColor(isActive ? .white : .white.opacity(0.4))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isActive ? type.color.opacity(0.25) : Color.white.opacity(0.06))
                                .overlay(
                                    Capsule()
                                        .stroke(isActive ? type.color.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(CoCreationPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Add Node button
                Button {
                    showAddNode = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("+ Add Node")
                            .font(AMENFont.semiBold(14))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(CoCreationPressStyle())
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
            .background(.thinMaterial)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 0.5),
                alignment: .top
            )
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "0A0A0F").ignoresSafeArea()

            GeometryReader { geo in
                let size = geo.size

                ZStack {
                    graphCanvas(in: size)
                    nodeLabelsOverlay(in: size)
                    tapGestureOverlay(in: size)
                }
                .frame(width: size.width, height: size.height)
                .onAppear {
                    canvasSize = size
                }
            }

            zoomControls
            bottomBar
        }
        .navigationTitle("Org Graph")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: "0A0A0F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedNode) { node in
            HelixNodeDetailSheet(node: node, allNodes: vm.nodes, vm: vm)
        }
        .sheet(isPresented: $showAddNode) {
            HelixAddNodeSheet(vm: vm, workspaceId: "default")
        }
        .onChange(of: vm.nodes) { newNodes in
            graphVM.load(nodes: newNodes)
        }
        .onAppear {
            graphVM.load(nodes: vm.nodes)
        }
    }
}
