// HelixRootView.swift
// AMENAPP
//
// Root view for the Helix workspace automation system.

import SwiftUI
import FirebaseFirestore

// MARK: - HelixRootView

struct HelixRootView: View {

    @StateObject private var vm = HelixViewModel()
    @State private var showWorkflowBuilder = false

    // Sample run data for illustration until live runs are loaded
    private let sampleRuns: [(name: String, status: RunStatus, minutesAgo: Int)] = [
        ("Weekly Check-in", .completed, 12),
        ("New Member Welcome", .completed, 47),
        ("Inactivity Nudge", .running, 2),
        ("Meeting Follow-up", .failed, 130)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Org Graph card
                        NavigationLink(destination: HelixGraphView(vm: vm)) {
                            orgGraphCard
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Active runs section
                        activeRunsSection

                        // Workflows section
                        workflowsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }

                // FAB
                fabButton
            }
            .navigationTitle("Helix")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(hex: "0A0A0F"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showWorkflowBuilder) {
                WorkflowBuilderView(vm: vm)
            }
        }
        .task {
            vm.loadWorkflows(workspaceId: "default")
            vm.loadNodes(workspaceId: "default")
        }
    }

    // MARK: - Org Graph Card

    private var orgGraphCard: some View {
        HStack(spacing: 14) {
            // Mini graph canvas preview
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 72, height: 72)

                Canvas { ctx, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let r: CGFloat = 26

                    let samplePositions: [CGPoint] = (0..<5).map { i in
                        let angle = Double(i) * (2 * .pi / 5) - .pi / 2
                        return CGPoint(
                            x: cx + r * CGFloat(cos(angle)),
                            y: cy + r * CGFloat(sin(angle))
                        )
                    }

                    let edges = [(0,1),(1,2),(2,3),(3,4),(4,0),(0,2)]
                    for (a, b) in edges {
                        var path = Path()
                        path.move(to: samplePositions[a])
                        path.addLine(to: samplePositions[b])
                        ctx.stroke(path, with: .color(.white.opacity(0.15)), lineWidth: 1)
                    }

                    let nodeColors: [Color] = [
                        Color(hex: "6B48FF"),
                        Color(hex: "0EA5E9"),
                        Color(hex: "10B981"),
                        Color(hex: "F59E0B"),
                        Color(hex: "EC4899")
                    ]
                    for (i, pos) in samplePositions.enumerated() {
                        let rect = CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)
                        ctx.fill(Path(ellipseIn: rect), with: .color(nodeColors[i % nodeColors.count]))
                    }
                }
                .frame(width: 72, height: 72)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Org Graph")
                        .font(AMENFont.semiBold(16))
                        .foregroundColor(.white)
                    Text("\(vm.nodes.count) nodes")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "6B48FF").opacity(0.25))
                        .clipShape(Capsule())
                }
                Text("View Full Graph")
                    .font(AMENFont.regular(13))
                    .foregroundColor(Color(hex: "6B48FF"))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Active Runs Section

    private var activeRunsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Runs")
                .font(AMENFont.semiBold(15))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 4)

            LazyVStack(spacing: 8) {
                ForEach(sampleRuns, id: \.name) { run in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(run.status.color)
                            .frame(width: 8, height: 8)

                        Text(run.name)
                            .font(AMENFont.regular(14))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(run.minutesAgo < 60
                             ? "\(run.minutesAgo)m ago"
                             : "\(run.minutesAgo / 60)h ago")
                            .font(AMENFont.regular(12))
                            .foregroundColor(.white.opacity(0.4))

                        Text(run.status.label)
                            .font(AMENFont.regular(11))
                            .foregroundColor(run.status.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(run.status.color.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Workflows Section

    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workflows")
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(vm.workflows.count)")
                    .font(AMENFont.regular(13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 4)

            if vm.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if vm.workflows.isEmpty {
                emptyWorkflowState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(vm.workflows) { workflow in
                        NavigationLink(destination: WorkflowDetailView(workflow: workflow, vm: vm)) {
                            WorkflowRowView(workflow: workflow, vm: vm)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyWorkflowState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.systemScaled(40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Automate your workspace")
                .font(AMENFont.semiBold(16))
                .foregroundColor(.white)

            Text("Create workflows to send check-ins, welcome new members, and surface insights — automatically.")
                .font(AMENFont.regular(14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            showWorkflowBuilder = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color(hex: "10B981").opacity(0.4), radius: 12, y: 4)

                Image(systemName: "plus")
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(CoCreationPressStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }
}

// MARK: - WorkflowRowView

struct WorkflowRowView: View {

    let workflow: HelixWorkflow
    @ObservedObject var vm: HelixViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Trigger icon
            ZStack {
                Circle()
                    .fill(Color(hex: "6B48FF").opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: workflow.triggerType.icon)
                    .font(.systemScaled(16))
                    .foregroundColor(Color(hex: "6B48FF"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(workflow.name)
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let lastRun = workflow.lastRunAt {
                    Text("Last run \(lastRun.relativeDescription)")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Text(workflow.triggerType.label)
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            // isActive toggle
            Toggle("", isOn: Binding(
                get: { workflow.isActive },
                set: { _ in
                    Task {
                        try? await vm.toggleWorkflow(workflow)
                    }
                }
            ))
            .labelsHidden()
            .tint(Color(hex: "10B981"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Date extension

private extension Date {
    var relativeDescription: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
