// WorkflowDetailView.swift
// AMENAPP
//
// WorkflowDetailView and WorkflowRunDetailView for the Helix system.

import SwiftUI
import FirebaseFirestore

// MARK: - WorkflowDetailView

struct WorkflowDetailView: View {

    let workflow: HelixWorkflow
    @ObservedObject var vm: HelixViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var runs: [HelixWorkflowRun] = []
    @State private var isLoadingRuns = true
    @State private var selectedRun: HelixWorkflowRun? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            Color(hex: "0A0A0F").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {

                    // Header card
                    headerCard

                    // Steps list
                    stepsSection

                    // Run history
                    runHistorySection

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 50)
            }
        }
        .navigationTitle(workflow.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color(hex: "0A0A0F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedRun) { run in
            WorkflowRunDetailView(run: run, workflow: workflow)
        }
        .confirmationDialog(
            "Delete \"\(workflow.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await vm.deleteWorkflow(workflow)
                    await MainActor.run { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This workflow and all its history will be permanently removed.")
        }
        .task {
            runs = await vm.loadWorkflowRuns(workflowId: workflow.id ?? "")
            isLoadingRuns = false
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "6B48FF").opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: workflow.triggerType.icon)
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "6B48FF"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(workflow.triggerType.label)
                            .font(AMENFont.regular(12))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Color(hex: "6B48FF").opacity(0.15))
                            .clipShape(Capsule())

                        Spacer()

                        // isActive toggle
                        Toggle("", isOn: Binding(
                            get: { workflow.isActive },
                            set: { _ in
                                Task { try? await vm.toggleWorkflow(workflow) }
                            }
                        ))
                        .labelsHidden()
                        .tint(Color(hex: "10B981"))
                    }

                    Text("\(workflow.runCount) total runs")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            if !workflow.description.isEmpty {
                Text(workflow.description)
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(spacing: 20) {
                if let lastRun = workflow.lastRunAt {
                    labelValue(label: "Last Run", value: lastRun.relativeDescription)
                }
                if let nextRun = workflow.nextRunAt {
                    labelValue(label: "Next Run", value: nextRun.relativeDescription)
                }
                if let created = workflow.createdAt {
                    labelValue(label: "Created", value: created.relativeDescription)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .font(AMENFont.semiBold(14))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(workflow.steps.sorted { $0.order < $1.order }.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 14) {
                        // Step connector
                        VStack(spacing: 0) {
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 1, height: 16)
                            }
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "6B48FF").opacity(0.18))
                                    .frame(width: 34, height: 34)
                                Image(systemName: step.type.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "6B48FF"))
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.type.label)
                                .font(AMENFont.semiBold(14))
                                .foregroundColor(.white)
                            // Config summary
                            let configSummary = step.config.compactMap { "\($0.key): \($0.value)" }.joined(separator: " · ")
                            if !configSummary.isEmpty {
                                Text(configSummary)
                                    .font(AMENFont.regular(12))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                            if let delay = step.delayMinutes, delay > 0 {
                                Text("Wait \(delay < 60 ? "\(delay) min" : "\(delay / 60) hr")")
                                    .font(AMENFont.regular(12))
                                    .foregroundColor(Color(hex: "F59E0B").opacity(0.8))
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Run History Section

    private var runHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Run History")
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("Last 10")
                    .font(AMENFont.regular(12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 4)

            if isLoadingRuns {
                HStack {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if runs.isEmpty {
                Text("No runs yet")
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                        Button {
                            selectedRun = run
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(run.status.color)
                                    .frame(width: 9, height: 9)

                                Text("Run #\(runs.count - index)")
                                    .font(AMENFont.semiBold(14))
                                    .foregroundColor(.white)

                                Spacer()

                                if let startedAt = run.startedAt {
                                    Text(startedAt.relativeDescription)
                                        .font(AMENFont.regular(12))
                                        .foregroundColor(.white.opacity(0.4))
                                }

                                Text(run.status.label)
                                    .font(AMENFont.regular(11))
                                    .foregroundColor(run.status.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(run.status.color.opacity(0.14))
                                    .clipShape(Capsule())

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.25))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(CoCreationPressStyle())
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Pause / Resume
            Button {
                Task { try? await vm.toggleWorkflow(workflow) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: workflow.isActive ? "pause.fill" : "play.fill")
                    Text(workflow.isActive ? "Pause" : "Resume")
                        .font(AMENFont.semiBold(14))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(hex: "6B48FF").opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "6B48FF").opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(CoCreationPressStyle())

            // Delete
            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Delete")
                        .font(AMENFont.semiBold(14))
                }
                .foregroundColor(Color(hex: "EF4444"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
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

    // MARK: - Helpers

    private func labelValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AMENFont.regular(11))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(AMENFont.semiBold(12))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}

// MARK: - WorkflowRunDetailView

struct WorkflowRunDetailView: View {

    let run: HelixWorkflowRun
    let workflow: HelixWorkflow

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Run summary header
                        runSummaryHeader

                        // Step results
                        stepsResultsSection

                        // Re-run button
                        Button {
                            // placeholder: trigger re-run via Cloud Function
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                Text("Re-run Workflow")
                                    .font(AMENFont.semiBold(16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "6B48FF"), Color(hex: "0EA5E9")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(CoCreationPressStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("Run Detail")
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

    // MARK: - Run Summary Header

    private var runSummaryHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(run.status.color.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: run.status == .completed ? "checkmark.circle.fill" : run.status == .failed ? "xmark.circle.fill" : "arrow.trianglehead.clockwise")
                    .font(.system(size: 28))
                    .foregroundColor(run.status.color)
            }

            Text(run.status.label)
                .font(AMENFont.bold(20))
                .foregroundColor(.white)

            HStack(spacing: 20) {
                if let start = run.startedAt {
                    VStack(spacing: 2) {
                        Text("Started")
                            .font(AMENFont.regular(11))
                            .foregroundColor(.white.opacity(0.4))
                        Text(start.formatted(date: .omitted, time: .shortened))
                            .font(AMENFont.semiBold(13))
                            .foregroundColor(.white)
                    }
                }
                if let end = run.completedAt {
                    VStack(spacing: 2) {
                        Text("Completed")
                            .font(AMENFont.regular(11))
                            .foregroundColor(.white.opacity(0.4))
                        Text(end.formatted(date: .omitted, time: .shortened))
                            .font(AMENFont.semiBold(13))
                            .foregroundColor(.white)
                    }
                }
                VStack(spacing: 2) {
                    Text("Steps")
                        .font(AMENFont.regular(11))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(run.stepResults.count)")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.white)
                }
            }

            if let error = run.errorMessage {
                Text(error)
                    .font(AMENFont.regular(13))
                    .foregroundColor(Color(hex: "EF4444"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "EF4444").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Steps Results

    private var stepsResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step Results")
                .font(AMENFont.semiBold(14))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 4)

            if run.stepResults.isEmpty {
                Text("No step data available")
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(run.stepResults) { result in
                        stepResultRow(result)
                    }
                }
            }
        }
    }

    private func stepResultRow(_ result: StepResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: result.status.icon)
                    .font(.system(size: 20))
                    .foregroundColor(result.status.color)

                // Match step label from workflow
                let stepLabel = workflow.steps.first(where: { $0.id == result.stepId })?.type.label ?? "Step"
                Text(stepLabel)
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.white)

                Spacer()

                if let completedAt = result.completedAt {
                    Text(completedAt.formatted(date: .omitted, time: .shortened))
                        .font(AMENFont.regular(11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            if let summary = result.resultSummary, !summary.isEmpty {
                Text(summary)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.leading, 32)
            }

            if let error = result.errorMessage, !error.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(AMENFont.regular(12))
                }
                .foregroundColor(Color(hex: "EF4444"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: "EF4444").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.leading, 32)
            }
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

// MARK: - Date extension (scoped to this file via fileprivate)

fileprivate extension Date {
    var relativeDescription: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
