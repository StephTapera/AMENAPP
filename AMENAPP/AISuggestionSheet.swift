//
//  AISuggestionSheet.swift
//  AMENAPP
//
//  Half-sheet for Berean AI collaboration prompts within a co-creation session.
//

import SwiftUI
import Combine

// MARK: - AI Preset Prompt Model

private struct AIPreset: Identifiable {
    let id = UUID()
    let label: String
    let icon:  String
}

// MARK: - AISuggestionSheet

struct AISuggestionSheet: View {

    @ObservedObject var vm: CoCreationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var customPrompt: String  = ""
    @State private var selectedPreset: String? = nil

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    private let presets: [AIPreset] = [
        AIPreset(label: "Continue this idea",       icon: "arrow.right.circle.fill"),
        AIPreset(label: "Suggest a Scripture",      icon: "book.fill"),
        AIPreset(label: "Rewrite more powerfully",  icon: "bolt.fill"),
        AIPreset(label: "Add a bridge",             icon: "music.note"),
        AIPreset(label: "Summarize so far",         icon: "text.badge.checkmark"),
        AIPreset(label: "Rhyme this line",          icon: "waveform"),
    ]

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    // Effective prompt to use for the request
    private var effectivePrompt: String {
        if let p = selectedPreset, !p.isEmpty { return p }
        return customPrompt
    }

    var body: some View {
        NavigationStack {
            ZStack {
                amenDark.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // ── Preset Grid ───────────────────────────────
                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(presets) { preset in
                                PresetButton(
                                    preset: preset,
                                    isSelected: selectedPreset == preset.label,
                                    amenPurple: amenPurple
                                ) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        selectedPreset = selectedPreset == preset.label
                                            ? nil
                                            : preset.label
                                        customPrompt = ""
                                    }
                                }
                            }
                        }

                        // ── Custom Prompt ─────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Or ask something specific…")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.white.opacity(0.55))

                            TextField("e.g. Make this more joyful", text: $customPrompt)
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                                .onChange(of: customPrompt) { val in
                                    if !val.isEmpty { selectedPreset = nil }
                                }
                        }

                        // ── Ask AI Button ─────────────────────────────
                        Button {
                            guard !effectivePrompt.isEmpty else { return }
                            Task { await vm.getAISuggestion(prompt: effectivePrompt) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.systemScaled(16, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                Text("Ask Berean AI")
                                    .font(AMENFont.bold(16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [amenPurple, Color(red: 0.60, green: 0.28, blue: 0.90)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: amenPurple.opacity(0.45), radius: 12, y: 5)
                            )
                        }
                        .disabled(effectivePrompt.isEmpty || vm.isLoadingAI)
                        .opacity(effectivePrompt.isEmpty ? 0.45 : 1.0)
                        .buttonStyle(CoCreationPressStyle())

                        // ── Loading ───────────────────────────────────
                        if vm.isLoadingAI {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(amenPurple)
                                    .scaleEffect(1.3)
                                Text("Berean is thinking…")
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }

                        // ── Suggestion Result ─────────────────────────
                        if !vm.aiSuggestion.isEmpty && !vm.isLoadingAI {
                            SuggestionResultCard(
                                suggestion: vm.aiSuggestion,
                                amenPurple: amenPurple
                            ) {
                                vm.insertAISuggestion()
                                dismiss()
                            } onTryAgain: {
                                Task { await vm.getAISuggestion(prompt: effectivePrompt) }
                            }
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Ask Berean AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.systemScaled(22))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let preset: AIPreset
    let isSelected: Bool
    let amenPurple: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: preset.icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .white : amenPurple)
                    .frame(width: 22)

                Text(preset.label)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? amenPurple : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? amenPurple.opacity(0) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: isSelected ? amenPurple.opacity(0.35) : .clear,
                radius: 8, y: 3
            )
        }
        .buttonStyle(CoCreationPressStyle())
    }
}

// MARK: - Suggestion Result Card

private struct SuggestionResultCard: View {
    let suggestion: String
    let amenPurple: Color
    let onInsert: () -> Void
    let onTryAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(amenPurple)
                Text("Berean's Suggestion")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text(suggestion)
                .font(AMENFont.regular(15))
                .foregroundStyle(.white)
                .lineSpacing(5)

            HStack(spacing: 12) {
                // Insert button
                Button(action: onInsert) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.systemScaled(14))
                            .symbolRenderingMode(.hierarchical)
                        Text("Insert into Canvas")
                            .font(AMENFont.semiBold(14))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(amenPurple)
                            .shadow(color: amenPurple.opacity(0.35), radius: 8, y: 3)
                    )
                }
                .buttonStyle(CoCreationPressStyle())

                // Try again ghost
                Button(action: onTryAgain) {
                    Text("Try Again")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(CoCreationPressStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(amenPurple.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}
