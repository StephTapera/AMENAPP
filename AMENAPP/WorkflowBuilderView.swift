// WorkflowBuilderView.swift
// AMENAPP
//
// Template picker and entry point for building new Helix workflows.

import SwiftUI
import FirebaseFirestore

// MARK: - WorkflowBuilderView

struct WorkflowBuilderView: View {

    @ObservedObject var vm: HelixViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplate: WorkflowTemplate? = nil
    @State private var showCustomBuilder = false

    private let templateIcons: [String: String] = [
        "weekly_checkin":    "heart.text.square.fill",
        "new_member_welcome":"hand.wave.fill",
        "inactivity_nudge":  "bell.badge.fill",
        "meeting_followup":  "person.2.wave.2.fill",
        "goal_progress":     "target"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Section header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Start from a template")
                                .font(AMENFont.bold(20))
                                .foregroundColor(.white)
                            Text("Pick a pre-built workflow and customise it for your workspace.")
                                .font(AMENFont.regular(14))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                        // Template cards
                        LazyVStack(spacing: 14) {
                            ForEach(WorkflowTemplate.all) { template in
                                NavigationLink(
                                    destination: WorkflowConfigView(template: template, vm: vm)
                                ) {
                                    TemplateCardView(
                                        template: template,
                                        icon: templateIcons[template.id] ?? "wand.and.stars"
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        // Custom builder link
                        NavigationLink(destination: CustomWorkflowBuilderView(vm: vm)) {
                            HStack(spacing: 10) {
                                Image(systemName: "hammer.fill")
                                    .font(.systemScaled(15))
                                    .foregroundColor(Color(hex: "6B48FF"))
                                Text("Advanced: Build Custom")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundColor(Color(hex: "6B48FF"))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "6B48FF").opacity(0.25), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("New Workflow")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - TemplateCardView

private struct TemplateCardView: View {

    let template: WorkflowTemplate
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "10B981").opacity(0.3), Color(hex: "0EA5E9").opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.systemScaled(22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        Image(systemName: template.triggerType.icon)
                            .font(.systemScaled(11))
                        Text(template.triggerType.label)
                            .font(AMENFont.regular(12))
                    }
                    .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }

            Text(template.description)
                .font(AMENFont.regular(13))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(2)

            // Steps preview
            HStack(spacing: 6) {
                ForEach(template.steps.prefix(4)) { step in
                    HStack(spacing: 4) {
                        Image(systemName: step.type.icon)
                            .font(.systemScaled(10))
                        Text(step.type.label)
                            .font(AMENFont.regular(11))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                if template.steps.count > 4 {
                    Text("+\(template.steps.count - 4)")
                        .font(AMENFont.regular(11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            // Use Template button
            HStack {
                Spacer()
                Text("Use Template")
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
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
