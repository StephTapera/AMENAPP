// CustomWorkflowBuilderView.swift
// AMENAPP
//
// Full custom workflow builder for Helix — triggers, steps, activation.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CustomWorkflowBuilderView: View {

    @ObservedObject var vm: HelixViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var workflowName: String = ""
    @State private var selectedTrigger: WorkflowTrigger = .manual
    @State private var cronDay: Int = 1            // Mon = 1
    @State private var cronHour: Int = 9
    @State private var steps: [WorkflowStep] = []
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    var body: some View {
        ZStack {
            Color(hex: "0A0A0F").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {

                    // Workflow name
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Workflow Name")
                        TextField("e.g. My Custom Workflow", text: $workflowName)
                            .font(AMENFont.regular(15))
                            .foregroundColor(.white)
                            .textFieldStyle(HelixTextFieldStyle())
                    }

                    // Trigger picker
                    triggerSection

                    // Cron picker (if scheduled)
                    if selectedTrigger == .scheduled {
                        cronSection
                    }

                    // Steps section
                    stepsSection

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AMENFont.regular(13))
                            .foregroundColor(Color(hex: "EF4444"))
                            .padding(.horizontal, 4)
                    }

                    // Save & Activate
                    Button {
                        saveAndActivate()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(isSaving ? "Saving..." : "Save & Activate")
                                .font(AMENFont.semiBold(16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            workflowName.trimmingCharacters(in: .whitespaces).isEmpty || steps.isEmpty
                            ? LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(
                                colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                                startPoint: .leading,
                                endPoint: .trailing
                              )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(CoCreationPressStyle())
                    .disabled(workflowName.trimmingCharacters(in: .whitespaces).isEmpty || steps.isEmpty || isSaving)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 50)
            }
        }
        .navigationTitle("Custom Workflow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: "0A0A0F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Trigger Section

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Trigger")

            LazyVStack(spacing: 10) {
                ForEach(WorkflowTrigger.allCases, id: \.self) { trigger in
                    let isSelected = selectedTrigger == trigger
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            selectedTrigger = trigger
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color(hex: "6B48FF").opacity(0.22) : Color.white.opacity(0.05))
                                    .frame(width: 44, height: 44)
                                Image(systemName: trigger.icon)
                                    .font(.systemScaled(18))
                                    .foregroundColor(isSelected ? Color(hex: "6B48FF") : .white.opacity(0.45))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trigger.label)
                                    .font(AMENFont.semiBold(14))
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                                Text(triggerDescription(trigger))
                                    .font(AMENFont.regular(12))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.systemScaled(18))
                                    .foregroundColor(Color(hex: "10B981"))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    isSelected ? Color(hex: "6B48FF").opacity(0.45) : Color.white.opacity(0.06),
                                    lineWidth: isSelected ? 1.5 : 0.5
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(CoCreationPressStyle())
                }
            }
        }
    }

    // MARK: - Cron Section

    private var cronSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Schedule")

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Day of the week")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    Picker("Day", selection: $cronDay) {
                        ForEach(0..<7) { i in
                            Text(days[i]).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .colorScheme(.dark)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Time (24h hour)")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    Stepper(
                        "\(String(format: "%02d", cronHour)):00",
                        value: $cronHour,
                        in: 0...23
                    )
                    .font(AMENFont.regular(15))
                    .foregroundColor(.white)
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

    // MARK: - Steps Section

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Steps")
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        steps.append(WorkflowStep(
                            order: steps.count,
                            type: .notify,
                            config: [:]
                        ))
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.systemScaled(12, weight: .semibold))
                        Text("Add Step")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundColor(Color(hex: "10B981"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(hex: "10B981").opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "10B981").opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(CoCreationPressStyle())
            }

            if steps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.systemScaled(28))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Tap \"Add Step\" to build your workflow")
                            .font(AMENFont.regular(13))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                }
                .padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepCard(index: index, step: $steps[index])
                    }
                }
            }
        }
    }

    // MARK: - Step Card

    @ViewBuilder
    private func stepCard(index: Int, step: Binding<WorkflowStep>) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // Order badge
                ZStack {
                    Circle()
                        .fill(Color(hex: "6B48FF").opacity(0.2))
                        .frame(width: 28, height: 28)
                    Text("\(index + 1)")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(Color(hex: "6B48FF"))
                }

                // Type picker
                Menu {
                    ForEach(WorkflowStepType.allCases, id: \.self) { type in
                        Button {
                            steps[index].type = type
                        } label: {
                            Label(type.label, systemImage: type.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: step.wrappedValue.type.icon)
                            .font(.systemScaled(13))
                        Text(step.wrappedValue.type.label)
                            .font(AMENFont.semiBold(13))
                        Image(systemName: "chevron.down")
                            .font(.systemScaled(11))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }

                Spacer()

                // Remove button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        steps.remove(at: index)
                        // Re-index
                        for i in 0..<steps.count {
                            steps[i].order = i
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundColor(Color(hex: "EF4444").opacity(0.7))
                }
                .buttonStyle(CoCreationPressStyle())
            }

            // Config fields
            VStack(spacing: 8) {
                if step.wrappedValue.type == .waitDelay {
                    // Delay minutes stepper
                    HStack {
                        Text("Delay (minutes)")
                            .font(AMENFont.regular(13))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Stepper(
                            "\(step.wrappedValue.delayMinutes ?? 30) min",
                            value: Binding(
                                get: { step.wrappedValue.delayMinutes ?? 30 },
                                set: { steps[index].delayMinutes = $0 }
                            ),
                            in: 1...10080,
                            step: 15
                        )
                        .font(AMENFont.regular(13))
                        .foregroundColor(.white)
                    }
                } else {
                    // Generic config text field
                    TextField("Config (key=value pairs)", text: Binding(
                        get: { step.wrappedValue.config["value"] ?? "" },
                        set: { steps[index].config["value"] = $0 }
                    ))
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white)
                    .textFieldStyle(HelixTextFieldStyle())
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.semiBold(14))
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 4)
    }

    private func triggerDescription(_ trigger: WorkflowTrigger) -> String {
        switch trigger {
        case .scheduled:  return "Runs at a specific day and time"
        case .event:      return "Triggered by a workspace event"
        case .manual:     return "Run manually on demand"
        case .aiDetected: return "AI detects a pattern and fires"
        }
    }

    // MARK: - Save

    private func saveAndActivate() {
        let trimmed = workflowName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !steps.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        var triggerConfig: [String: String] = [:]
        if selectedTrigger == .scheduled {
            triggerConfig["day"] = "\(cronDay)"
            triggerConfig["hour"] = "\(cronHour)"
        }

        let workflow = HelixWorkflow(
            workspaceId: "default",
            name: trimmed,
            description: "",
            triggerType: selectedTrigger,
            triggerConfig: triggerConfig,
            steps: steps,
            isActive: true,
            createdBy: Auth.auth().currentUser?.uid ?? "unknown"
        )

        Task {
            do {
                try await vm.createWorkflow(workflow)
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
