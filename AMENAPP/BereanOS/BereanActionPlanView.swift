import SwiftUI

// MARK: - BereanActionPlanView

struct BereanActionPlanView: View {
    let projectId: String

    @StateObject private var service = BereanActionPlanService.shared
    @State private var goal = ""
    @State private var selectedPlanType: BereanActionPlanType = .thirtyDay
    @State private var generateError: Error?
    @State private var showError = false
    @State private var isLoading = true

    private var featureEnabled: Bool {
        AMENFeatureFlags.shared.bereanOSActionPlannerEnabled
    }

    var body: some View {
        Group {
            if !featureEnabled {
                featureDisabledView
            } else {
                mainContent
            }
        }
        .navigationTitle("Action Planner")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $showError, presenting: generateError) { _ in
            Button("OK", role: .cancel) {}
        } message: { err in
            Text(err.localizedDescription)
        }
        .task {
            do {
                try await service.fetchPlans(projectId: projectId)
            } catch {
                // Non-fatal: plans will be empty
            }
            isLoading = false
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        List {
            planGeneratorSection

            if service.isGenerating {
                Section {
                    HStack {
                        ProgressView()
                        Text("Generating your plan...")
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                }
            }

            if isLoading {
                Section {
                    ProgressView("Loading plans...")
                        .frame(maxWidth: .infinity)
                }
            } else {
                plansSection
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Generator Section

    private var planGeneratorSection: some View {
        Section("New Plan") {
            Picker("Plan Type", selection: $selectedPlanType) {
                ForEach(BereanActionPlanType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Plan duration")

            TextField("What's your goal?", text: $goal, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityLabel("Goal description")

            Button {
                Task { await generatePlan() }
            } label: {
                HStack {
                    Spacer()
                    Text("Generate Plan")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || service.isGenerating)
            .accessibilityHint("Generates a milestone-based action plan using AI")
        }
    }

    // MARK: - Plans Section

    private var plansSection: some View {
        ForEach(service.plans) { plan in
            PlanCard(plan: plan, projectId: projectId)
        }
    }

    // MARK: - Feature Disabled

    private var featureDisabledView: some View {
        ContentUnavailableView(
            "Action Planner Coming Soon",
            systemImage: "checklist",
            description: Text("This feature is not yet available. Check back soon.")
        )
    }

    // MARK: - Actions

    private func generatePlan() async {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else { return }
        do {
            _ = try await service.generatePlan(
                goal: trimmedGoal,
                planType: selectedPlanType,
                projectId: projectId
            )
            goal = ""
        } catch {
            generateError = error
            showError = true
        }
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let plan: BereanActionPlan
    let projectId: String

    private var completedMilestones: Int {
        plan.milestones.filter { $0.status == .complete }.count
    }

    private var totalMilestones: Int { plan.milestones.count }

    private var overallProgress: Double {
        guard totalMilestones > 0 else { return 0 }
        return Double(completedMilestones) / Double(totalMilestones)
    }

    var body: some View {
        Section {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title)
                            .font(.headline)
                        Text(plan.planType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(completedMilestones)/\(totalMilestones)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: overallProgress)
                    .accessibilityLabel("Overall progress: \(Int(overallProgress * 100)) percent")
            }
            .padding(.vertical, 4)

            // Milestones
            ForEach(plan.milestones) { milestone in
                MilestoneRow(
                    milestone: milestone,
                    planId: plan.id,
                    projectId: projectId
                )
            }

            // Risks
            if !plan.risks.isEmpty {
                DisclosureGroup("Risks") {
                    ForEach(plan.risks, id: \.self) { risk in
                        Label(risk, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding(.vertical, 2)
                    }
                }
                .accessibilityLabel("Risks: \(plan.risks.count) items")
            }

            // Success Metrics
            if !plan.successMetrics.isEmpty {
                DisclosureGroup("Success Metrics") {
                    ForEach(plan.successMetrics, id: \.self) { metric in
                        Label(metric, systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .padding(.vertical, 2)
                    }
                }
                .accessibilityLabel("Success metrics: \(plan.successMetrics.count) items")
            }
        }
    }
}

// MARK: - MilestoneRow

private struct MilestoneRow: View {
    let milestone: BereanMilestone
    let planId: String
    let projectId: String

    @StateObject private var service = BereanActionPlanService.shared
    @State private var isExpanded = false

    private var completedTasks: Int {
        milestone.tasks.filter { $0.status == .complete }.count
    }
    private var totalTasks: Int { milestone.tasks.count }

    private var taskProgress: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            taskListContent
        } label: {
            milestoneLabel
        }
        .accessibilityLabel("\(milestone.title). Status: \(milestone.status.rawValue). \(completedTasks) of \(totalTasks) tasks complete.")
    }

    private var milestoneLabel: some View {
        HStack(spacing: 8) {
            statusIcon(for: milestone.status)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.title)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    if let due = milestone.dueDate {
                        Text(dateFormatter.string(from: due))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !milestone.dependsOnIds.isEmpty {
                        Text("\(milestone.dependsOnIds.count) dependency")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if totalTasks > 0 {
                    ProgressView(value: taskProgress)
                        .tint(progressTint(for: milestone.status))
                        .accessibilityLabel("\(Int(taskProgress * 100)) percent of tasks complete")
                }
            }

            Spacer()

            StatusBadge(status: milestone.status)
        }
        .padding(.vertical, 2)
    }

    private var taskListContent: some View {
        ForEach(milestone.tasks) { task in
            TaskRow(
                task: task,
                planId: planId,
                milestoneId: milestone.id,
                projectId: projectId
            )
        }
    }

    private func statusIcon(for status: BereanTaskStatus) -> some View {
        Image(systemName: status == .complete ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(status == .complete ? Color.green : Color.secondary)
    }

    private func progressTint(for status: BereanTaskStatus) -> Color {
        switch status {
        case .complete: return .green
        case .blocked: return .red
        case .inProgress: return .blue
        default: return .accentColor
        }
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let status: BereanTaskStatus

    var label: String {
        switch status {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .blocked: return "Blocked"
        case .complete: return "Complete"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch status {
        case .notStarted: return .secondary
        case .inProgress: return .blue
        case .blocked: return .red
        case .complete: return .green
        case .cancelled: return .gray
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(label)")
    }
}

// MARK: - TaskRow

private struct TaskRow: View {
    let task: BereanOSTask
    let planId: String
    let milestoneId: String
    let projectId: String

    @StateObject private var service = BereanActionPlanService.shared
    @State private var isToggling = false

    private var isComplete: Bool { task.status == .complete }

    var body: some View {
        Button {
            guard !isToggling else { return }
            Task {
                isToggling = true
                defer { isToggling = false }
                let newStatus: BereanTaskStatus = isComplete ? .notStarted : .complete
                try? await service.updateTaskStatus(
                    planId: planId,
                    milestoneId: milestoneId,
                    taskId: task.id,
                    status: newStatus,
                    projectId: projectId
                )
            }
        } label: {
            HStack(spacing: 10) {
                if isToggling {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isComplete ? Color.green : Color.secondary)
                        .frame(width: 20, height: 20)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline)
                        .strikethrough(isComplete)
                        .foregroundStyle(isComplete ? .secondary : .primary)

                    HStack(spacing: 6) {
                        PriorityBadge(priority: task.priority)

                        if let assignedTo = task.assignedTo, !assignedTo.isEmpty {
                            Text(assignedTo)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title). \(isComplete ? "Complete" : "Incomplete"). Priority: \(task.priority.rawValue).")
        .accessibilityHint(isComplete ? "Tap to mark incomplete" : "Tap to mark complete")
    }
}

// MARK: - PriorityBadge

private struct PriorityBadge: View {
    let priority: BereanTaskPriority

    var label: String {
        switch priority {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("\(label) priority")
    }
}
