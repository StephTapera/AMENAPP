// CreationPromptBar.swift
// AMEN Creator — Sticky Refinement Prompt Bar
// Floating glass input bar at bottom of studio

import SwiftUI

struct CreationPromptBar: View {
    @ObservedObject var vm: SceneBuilderViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 12) {
                // Refinement history chips (latest 3)
                if !vm.refinementHistory.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.refinementHistory.suffix(3), id: \.self) { prev in
                                HStack(spacing: 5) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 9))
                                    Text(prev)
                                        .font(.custom("OpenSans-Regular", size: 11))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.gray.opacity(0.08))
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Input row
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)

                        TextField("Refine — e.g. \"Make it more hopeful\"", text: $vm.refinementInput)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .focused($isFocused)
                            .submitLabel(.send)
                            .onSubmit {
                                submitRefinement()
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.gray.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .strokeBorder(
                                        isFocused ? Color.black.opacity(0.2) : Color.black.opacity(0.1),
                                        lineWidth: 1
                                    )
                            )
                    )

                    // Send button
                    Button(action: submitRefinement) {
                        ZStack {
                            if vm.isRefining {
                                Circle()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                ProgressView().scaleEffect(0.75)
                            } else {
                                Circle()
                                    .fill(vm.refinementInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.1) : Color.black)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(vm.refinementInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : .white)
                            }
                        }
                    }
                    .disabled(vm.refinementInput.trimmingCharacters(in: .whitespaces).isEmpty || vm.isRefining)
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .padding(.bottom, 0)
    }

    private func submitRefinement() {
        let prompt = vm.refinementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isFocused = false
        vm.refine(with: prompt)
    }
}

// MARK: - Refinement Sheet (expanded)

struct CreationRefinementSheet: View {
    @ObservedObject var vm: SceneBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Quick suggestion chips
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Suggestions")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .padding(.horizontal, 20)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(CreationRefinementChip.suggestions) { chip in
                            RefinementChipTile(chip: chip) {
                                vm.applyRefinementChip(chip)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Divider().padding(.horizontal, 20)

                // Custom input
                VStack(alignment: .leading, spacing: 10) {
                    Text("Custom Instruction")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .padding(.horizontal, 20)

                    HStack(spacing: 12) {
                        TextField("Describe how to refine...", text: $vm.refinementInput)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.07))
                            )

                        Button {
                            let prompt = vm.refinementInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !prompt.isEmpty else { return }
                            vm.refine(with: prompt)
                            dismiss()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Color.black))
                                .foregroundStyle(.white)
                        }
                        .disabled(vm.refinementInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 20)
                }

                // History
                if !vm.refinementHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .padding(.horizontal, 20)

                        ForEach(vm.refinementHistory.suffix(5).reversed(), id: \.self) { past in
                            HStack(spacing: 12) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text(past)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    vm.refine(with: past)
                                    dismiss()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Refine Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Refinement Chip Tile

struct RefinementChipTile: View {
    let chip: CreationRefinementChip
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: chip.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(chip.label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
