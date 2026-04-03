// WorkflowConfigView.swift
// AMENAPP
//
// Configuration view for activating a workflow from a template.

import SwiftUI
import FirebaseFirestore

struct WorkflowConfigView: View {

    let template: WorkflowTemplate
    @ObservedObject var vm: HelixViewModel

    @Environment(\.dismiss) private var dismiss

    // Weekly Check-in config
    @State private var circleName: String = ""
    @State private var checkInDay: Int = 1        // 0=Sun..6=Sat
    @State private var checkInHour: Int = 9
    @State private var questionStyle: String = "Gentle"

    // New Member Welcome config
    @State private var welcomeMessage: String = "Welcome to our community! We're so glad you're here. 🙏"
    @State private var isImprovingMessage = false

    // Generic config
    @State private var workflowName: String = ""
    @State private var workflowDescription: String = ""

    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var didSave = false

    private let questionStyles = ["Gentle", "Reflective", "Challenging"]
    private let days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]

    var body: some View {
        ZStack {
            Color(hex: "0A0A0F").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {

                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(template.name)
                            .font(AMENFont.bold(20))
                            .foregroundColor(.white)
                        Text(template.description)
                            .font(AMENFont.regular(14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                    // Template-specific config
                    configSection

                    // Workflow preview
                    previewSection

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AMENFont.regular(13))
                            .foregroundColor(Color(hex: "EF4444"))
                            .padding(.horizontal, 4)
                    }

                    // Activate button
                    Button {
                        activate()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(isSaving ? "Activating..." : "Activate Workflow")
                                .font(AMENFont.semiBold(16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(CoCreationPressStyle())
                    .disabled(isSaving)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Configure")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: "0A0A0F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            workflowName = template.name
            workflowDescription = template.description
        }
    }

    // MARK: - Config section

    @ViewBuilder
    private var configSection: some View {
        switch template.id {
        case "weekly_checkin":
            weeklyCheckInConfig
        case "new_member_welcome":
            newMemberWelcomeConfig
        default:
            genericConfig
        }
    }

    // MARK: - Weekly Check-in Config

    private var weeklyCheckInConfig: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Configuration")

            VStack(spacing: 12) {
                // Circle / group name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Circle or Group Name")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    TextField("e.g. Young Adults Group", text: $circleName)
                        .font(AMENFont.regular(15))
                        .foregroundColor(.white)
                        .textFieldStyle(HelixTextFieldStyle())
                }

                // Day picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send on day")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    Picker("Day", selection: $checkInDay) {
                        ForEach(0..<7) { i in
                            Text(days[i]).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .colorScheme(.dark)
                }

                // Time picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send at hour (24h)")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    Stepper(
                        "\(String(format: "%02d", checkInHour)):00",
                        value: $checkInHour,
                        in: 0...23
                    )
                    .font(AMENFont.regular(15))
                    .foregroundColor(.white)
                }

                // Question style
                VStack(alignment: .leading, spacing: 8) {
                    Text("Question style")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    HStack(spacing: 8) {
                        ForEach(questionStyles, id: \.self) { style in
                            let isSelected = questionStyle == style
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    questionStyle = style
                                }
                            } label: {
                                Text(style)
                                    .font(AMENFont.regular(13))
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Color(hex: "6B48FF").opacity(0.3) : Color.white.opacity(0.06))
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color(hex: "6B48FF").opacity(0.6) : Color.clear, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(CoCreationPressStyle())
                        }
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
    }

    // MARK: - New Member Welcome Config

    private var newMemberWelcomeConfig: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Configuration")

            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome Message")
                    .font(AMENFont.regular(12))
                    .foregroundColor(.white.opacity(0.45))

                TextEditor(text: $welcomeMessage)
                    .font(AMENFont.regular(15))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 100)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    improveWithAI()
                } label: {
                    HStack(spacing: 6) {
                        if isImprovingMessage {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.systemScaled(13))
                        }
                        Text(isImprovingMessage ? "Improving..." : "AI Improve")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundColor(Color(hex: "6B48FF"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "6B48FF").opacity(0.14))
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "6B48FF").opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(CoCreationPressStyle())
                .disabled(isImprovingMessage)
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

    // MARK: - Generic Config

    private var genericConfig: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Configuration")

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workflow Name")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    TextField("Name", text: $workflowName)
                        .font(AMENFont.regular(15))
                        .foregroundColor(.white)
                        .textFieldStyle(HelixTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                    TextField("Short description...", text: $workflowDescription, axis: .vertical)
                        .font(AMENFont.regular(15))
                        .foregroundColor(.white)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(HelixTextFieldStyle())
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

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("This workflow will…")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(template.steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 12) {
                        // Step number
                        ZStack {
                            Circle()
                                .fill(Color(hex: "6B48FF").opacity(0.2))
                                .frame(width: 26, height: 26)
                            Text("\(index + 1)")
                                .font(AMENFont.semiBold(12))
                                .foregroundColor(Color(hex: "6B48FF"))
                        }

                        Image(systemName: step.type.icon)
                            .font(.systemScaled(14))
                            .foregroundColor(.white.opacity(0.6))

                        Text(step.type.label)
                            .font(AMENFont.regular(14))
                            .foregroundColor(.white.opacity(0.85))

                        if let delay = step.delayMinutes, delay > 0 {
                            Spacer()
                            Text("after \(delay < 60 ? "\(delay)m" : "\(delay / 60)h")")
                                .font(AMENFont.regular(11))
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }

                    if index < template.steps.count - 1 {
                        HStack {
                            Spacer().frame(width: 12)
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1, height: 16)
                                .padding(.leading, 12)
                            Spacer()
                        }
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
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.semiBold(13))
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func activate() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await vm.createFromTemplate(template, workspaceId: "default")
                await MainActor.run {
                    isSaving = false
                    didSave = true
                    // Pop to root by dismissing the sheet chain
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

    private func improveWithAI() {
        isImprovingMessage = true
        // Placeholder: simulate an AI improvement delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            welcomeMessage = "Welcome to our beloved community! We are truly blessed to have you join us. May this space be a source of encouragement, growth, and connection as we walk together in faith. 🙏✨"
            isImprovingMessage = false
        }
    }
}

// MARK: - HelixTextFieldStyle

struct HelixTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
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

