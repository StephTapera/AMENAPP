//
//  SelahTransformationCards.swift
//  AMENAPP
//
//  NotebookLM-style transformation cards — transform study content into
//  devotionals, prayer guides, study outlines, memory cards, journal
//  prompts, and share snippets.
//

import SwiftUI

struct SelahTransformationCardsView: View {
    let content: String
    let scriptureRefs: [String]
    var onSave: ((SelahTransformationOutput) -> Void)? = nil

    @ObservedObject private var selahService = SelahService.shared
    @State private var selectedType: SelahTransformationType?
    @State private var streamedOutput = ""
    @State private var isStreaming = false
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("TRANSFORM")
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text("Turn your study into something new")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            // Type picker grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(SelahTransformationType.allCases) { type in
                    TransformationTypeCard(
                        type: type,
                        isSelected: selectedType == type,
                        isDisabled: isStreaming && selectedType != type
                    ) {
                        guard !isStreaming else { return }
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                            selectedType = type
                        }
                        startTransformation(type)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Output area
            if selectedType != nil {
                outputSection
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let type = selectedType {
                HStack {
                    Image(systemName: type.icon)
                        .font(.systemScaled(13))
                        .foregroundStyle(type.accentColor)
                    Text(type.rawValue)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()

                    if isStreaming {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }

            if !streamedOutput.isEmpty {
                Text(streamedOutput)
                    .font(.systemScaled(14))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                // Action buttons
                if !isStreaming {
                    actionButtons
                }
            } else if isStreaming {
                SelahThinkingDots()
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.40), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            // Copy
            Button {
                UIPasteboard.general.string = streamedOutput
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    Text(showCopied ? "Copied" : "Copy")
                }
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)

            // Save to Notes
            Button {
                guard let type = selectedType else { return }
                let output = SelahTransformationOutput(
                    type: type,
                    content: streamedOutput,
                    scriptureRefs: scriptureRefs
                )
                onSave?(output)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "note.text.badge.plus")
                    Text("Save")
                }
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Logic

    private func startTransformation(_ type: SelahTransformationType) {
        isStreaming = true
        streamedOutput = ""

        Task {
            do {
                let stream = selahService.transform(
                    content: content,
                    scriptureRefs: scriptureRefs,
                    to: type
                )

                for try await chunk in stream {
                    streamedOutput += chunk
                }
                isStreaming = false
            } catch {
                isStreaming = false
            }
        }
    }
}

// MARK: - Transformation Type Card

private struct TransformationTypeCard: View {
    let type: SelahTransformationType
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: type.icon)
                    .font(.systemScaled(20))
                    .foregroundStyle(isSelected ? type.accentColor : .secondary)

                Text(type.rawValue)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(type.description)
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(type.accentColor.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(type.accentColor.opacity(0.25), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                }
            }
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
