// CreationPublishView.swift
// AMEN Creator — Publish Flow
// Safety check → destination selection → confirm → publish

import SwiftUI

struct CreationPublishView: View {
    @ObservedObject var vm: SceneBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var safetyChecked = false
    @State private var runningCheck = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text("Ready to Publish")
                        .font(.custom("OpenSans-Bold", size: 22))
                    Text("Review your content before sending it to AMEN")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)

                ScrollView {
                    VStack(spacing: 20) {

                        // Plan summary
                        if let plan = vm.scenePlan {
                            planSummaryCard(plan)
                        }

                        // Safety status
                        safetyCard

                        // Segment summary
                        segmentSummaryCard

                        // Publish destination
                        destinationCard

                        // Publish button
                        publishButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if !safetyChecked {
                    runningCheck = true
                    await vm.runSafetyCheck()
                    safetyChecked = true
                    runningCheck = false
                }
            }
        }
    }

    // MARK: - Plan Summary Card

    private func planSummaryCard(_ plan: ScenePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content Summary")
                .font(.custom("OpenSans-Bold", size: 15))

            HStack(spacing: 16) {
                ToneBadge(tone: plan.tone)
                DurationBadge(seconds: plan.targetDuration)
                Text("\(vm.timelineSegments.count) segments")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
            }

            if let title = plan.titleSuggestion {
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                )
        )
    }

    // MARK: - Safety Card

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Safety Check")
                    .font(.custom("OpenSans-Bold", size: 15))
                Spacer()
                if runningCheck {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Checking...")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            CreationSafetyBanner(status: vm.safetyStatus)

            if vm.safetyStatus != .approved {
                Button {
                    Task { await vm.runSafetyCheck() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.systemScaled(12))
                        Text("Re-check")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.04))
        )
    }

    // MARK: - Segment Summary

    private var segmentSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Segments")
                .font(.custom("OpenSans-Bold", size: 15))

            ForEach(vm.timelineSegments) { segment in
                HStack(spacing: 12) {
                    Image(systemName: segment.kind.icon)
                        .font(.systemScaled(14))
                        .foregroundStyle(segment.kind.color)
                        .frame(width: 28)

                    Text(segment.kind.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 13))

                    Spacer()

                    DurationBadge(seconds: segment.duration)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.04))
        )
    }

    // MARK: - Destination Card

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Publish To")
                .font(.custom("OpenSans-Bold", size: 15))

            // AMEN Feed (auto-enabled for now)
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "a.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(.teal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AMEN Feed")
                        .font(.custom("OpenSans-Bold", size: 14))
                    Text("Your content will appear in your followers' feeds")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(.teal)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.teal.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.04))
        )
    }

    // MARK: - Publish Button

    private var publishButton: some View {
        VStack(spacing: 12) {
            switch vm.publishState {
            case .idle, .validating:
                GlassCreationButton(
                    label: "Publish to AMEN",
                    icon: "paperplane.fill",
                    style: .primary,
                    isDisabled: vm.safetyStatus == .blocked || runningCheck
                ) {
                    vm.executePublish(destinations: ["amen_feed"])
                }

            case .uploading(let progress):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.black)
                    Text("Uploading... \(Int(progress * 100))%")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }

            case .publishing:
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.85)
                    Text("Publishing...")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.secondary)
                }

            case .success:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.systemScaled(20))
                    Text("Published successfully!")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    GlassCreationButton(label: "Try Again", icon: "arrow.clockwise", style: .primary) {
                        vm.executePublish(destinations: ["amen_feed"])
                    }
                }
            }
        }
    }
}

// MARK: - Safety Sheet

struct CreationSafetySheet: View {
    @ObservedObject var vm: SceneBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.systemScaled(36))
                        .foregroundStyle(.orange)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Content Review")
                        .font(.custom("OpenSans-Bold", size: 22))
                    Text("Your content requires a review before publishing. Please check the details below.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Divider().padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 16) {
                    Text("What to do")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        SafetyGuideRow(icon: "pencil.circle.fill", color: .blue, text: "Review your text overlays and captions for anything that may be inappropriate")
                        SafetyGuideRow(icon: "photo.circle.fill", color: .purple, text: "Ensure all images and videos are appropriate for a faith community")
                        SafetyGuideRow(icon: "arrow.clockwise.circle.fill", color: .teal, text: "After making edits, run the safety check again from the publish screen")
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                GlassCreationButton(label: "Edit Content", icon: "pencil") {
                    dismiss()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct SafetyGuideRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(22))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            Spacer()
        }
    }
}
