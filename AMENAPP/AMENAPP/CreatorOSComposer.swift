// CreatorOSComposer.swift
// AMEN App — Creator OS bottom-sheet composer
//
// Provides AI-assisted content creation tools (captions, hooks, scripture,
// prayer, story). Gated by creatorOSComposerEnabled feature flag.

import SwiftUI
import FirebaseFunctions

// MARK: - Mode enum

enum CreatorOSMode: String, CaseIterable, Identifiable {
    case caption
    case hook
    case scripture
    case prayer
    case story

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .caption:   return "Caption"
        case .hook:      return "Hook"
        case .scripture: return "Scripture"
        case .prayer:    return "Prayer"
        case .story:     return "Story"
        }
    }

    var systemImage: String {
        switch self {
        case .caption:   return "text.bubble"
        case .hook:      return "bolt.fill"
        case .scripture: return "book.closed.fill"
        case .prayer:    return "hands.and.sparkles.fill"
        case .story:     return "scroll.fill"
        }
    }
}

// MARK: - Main view

struct CreatorOSComposer: View {
    @Binding var isPresented: Bool
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var selectedMode: CreatorOSMode = .caption
    @State private var inputText = ""
    @State private var generatedOutput = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let functions = Functions.functions()

    var body: some View {
        guard flags.creatorOSComposerEnabled else { return AnyView(EmptyView()) }
        return AnyView(content)
    }

    private var content: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CreatorOSMode.allCases) { mode in
                            modePill(mode)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }

                Divider()
                    .padding(.horizontal, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What are you creating?")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)

                            ZStack(alignment: .topLeading) {
                                if inputText.isEmpty {
                                    Text("Describe what you're creating...")
                                        .foregroundStyle(.tertiary)
                                        .font(.body)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                }
                                TextEditor(text: $inputText)
                                    .font(.body)
                                    .frame(minHeight: 96, maxHeight: 160)
                                    .scrollContentBackground(.hidden)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(reduceTransparency
                                          ? Color(.secondarySystemBackground)
                                          : Color(.secondarySystemBackground).opacity(0.8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.8)
                                    )
                            )
                            .padding(.horizontal, 18)
                        }

                        // Generate button
                        Button(action: generate) {
                            HStack(spacing: 8) {
                                if isGenerating {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.85)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(isGenerating ? "Generating…" : "Generate")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                        .padding(.horizontal, 18)

                        // Error
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 18)
                        }

                        // Output
                        if !generatedOutput.isEmpty {
                            outputCard
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Creator Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Mode pill

    private func modePill(_ mode: CreatorOSMode) -> some View {
        let isSelected = mode == selectedMode
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedMode = mode }
        } label: {
            Label(mode.displayLabel, systemImage: mode.systemImage)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Output card

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Generated", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Text(generatedOutput)
                .font(.body)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = generatedOutput
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy generated text")

                Button {
                    isPresented = false
                } label: {
                    Label("Use", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use generated text")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 18)
    }

    // MARK: - Generate action

    private func generate() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let callable = functions.httpsCallable("creatorOSGenerate")
                let result = try await callable.call(["mode": selectedMode.rawValue, "input": trimmed])
                if let data = result.data as? [String: Any],
                   let output = data["output"] as? String {
                    generatedOutput = output
                } else {
                    errorMessage = "Unexpected response from server."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
