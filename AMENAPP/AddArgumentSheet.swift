// AddArgumentSheet.swift — AMEN App
// Sheet for composing and submitting a new argument node in a discussion thread.

import SwiftUI

struct AddArgumentSheet: View {
    @ObservedObject var vm: ReasoningViewModel
    var parentNodeId: String? = nil

    @State private var claimText = ""
    @State private var evidenceText = ""
    @State private var selectedType: DiscussionNode.NodeType = .argument
    @State private var isScreening = false
    @State private var isPosting = false
    @State private var showFlagWarning = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Node type picker
                        nodeTypePicker

                        // Claim editor
                        claimEditor

                        // Evidence editor
                        evidenceEditor

                        // Flag warning (shown after screening if flags exist)
                        if showFlagWarning && !vm.manipulationFlags.isEmpty {
                            flagWarningCard
                        }

                        // Action buttons
                        actionButtons
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Add Your View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.black.opacity(0.7))
                            .font(.systemScaled(15, weight: .medium))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Node Type Picker

    private var nodeTypePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(.black.opacity(0.5))
                .padding(.top, 4)

            HStack(spacing: 8) {
                ForEach([DiscussionNode.NodeType.argument, .counterargument, .evidence, .viewUpdate], id: \.self) { type in
                    typeTab(type)
                }
            }
        }
    }

    private func typeTab(_ type: DiscussionNode.NodeType) -> some View {
        let isSelected = selectedType == type
        let accent = accentColor(for: type)

        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                selectedType = type
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.systemScaled(13, weight: .medium))
                Text(type.label)
                    .font(.systemScaled(10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(isSelected ? accent : .black.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.15) : Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? accent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Claim Editor

    private var claimEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Argument")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(.black.opacity(0.5))

            ZStack(alignment: .topLeading) {
                if claimText.isEmpty {
                    Text("State your argument clearly...")
                        .font(.systemScaled(15))
                        .foregroundColor(.black.opacity(0.25))
                        .padding(.top, 12)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $claimText)
                    .font(.systemScaled(15))
                    .foregroundColor(.black.opacity(0.9))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                claimText.isEmpty ? Color.black.opacity(0.08) : accentColor(for: selectedType).opacity(0.3),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    // MARK: - Evidence Editor

    private var evidenceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evidence / Sources")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            ZStack(alignment: .topLeading) {
                if evidenceText.isEmpty {
                    Text("Sources or evidence... (optional)")
                        .font(.systemScaled(14))
                        .foregroundColor(.black.opacity(0.2))
                        .padding(.top, 10)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $evidenceText)
                    .font(.systemScaled(14))
                    .foregroundColor(.black.opacity(0.75))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 64)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Flag Warning Card

    private var flagWarningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                Text("Heads up")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
            }

            Text("Our AI flagged some potential issues in your argument:")
                .font(.systemScaled(13))
                .foregroundColor(.black.opacity(0.65))

            AMENFlowLayout(spacing: 6) {
                ForEach(vm.manipulationFlags, id: \.self) { flag in
                    Text(flag.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.15))
                                .overlay(Capsule().strokeBorder(Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.3), lineWidth: 1))
                        )
                }
            }

            Text("This is just a flag, not a block. You can still post.")
                .font(.systemScaled(12))
                .foregroundColor(.black.opacity(0.45))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.2), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Check Argument button
            Button {
                Task {
                    isScreening = true
                    vm.manipulationFlags = []
                    showFlagWarning = false
                    await vm.screenArgument(claimText)
                    isScreening = false
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        showFlagWarning = !vm.manipulationFlags.isEmpty
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isScreening {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.systemScaled(14))
                    }
                    Text(isScreening ? "Checking..." : "Check Argument")
                        .font(.systemScaled(15, weight: .semibold))
                }
                .foregroundColor(.black.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.black.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isScreening || isPosting)
            .opacity(claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

            // Post button
            Button {
                Task {
                    isPosting = true
                    let evidenceItems = evidenceText
                        .split(separator: "\n")
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    await vm.postNode(
                        claim: claimText,
                        evidence: evidenceItems,
                        type: selectedType,
                        parentId: parentNodeId
                    )
                    isPosting = false
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if isPosting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.systemScaled(14))
                    }
                    Text(isPosting ? "Posting..." : "Post")
                        .font(.systemScaled(15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.55, green: 0.25, blue: 1.0), Color(red: 0.35, green: 0.15, blue: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.purple.opacity(0.4), radius: 10, x: 0, y: 5)
                )
            }
            .buttonStyle(.plain)
            .disabled(claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting || isScreening)
            .opacity(claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
    }

    // MARK: - Helpers

    private func accentColor(for type: DiscussionNode.NodeType) -> Color {
        switch type {
        case .argument:        return Color(red: 0.55, green: 0.25, blue: 1.0)
        case .counterargument: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .evidence:        return Color(red: 0.25, green: 0.88, blue: 0.56)
        case .viewUpdate:      return Color.black.opacity(0.65)
        }
    }
}
