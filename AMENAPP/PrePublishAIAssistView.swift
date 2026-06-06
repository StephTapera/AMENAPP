// PrePublishAIAssistView.swift
// AMENAPP
//
// Subtle Liquid Glass AI assist panel shown before posting.
// Appears as a compact expandable strip at the bottom of the composer.
// Not a banner — calm, private, smart.

import SwiftUI

// MARK: - AI Assist Action

struct AIAssistAction: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let appliesWhen: [String]   // postIntent values this action makes sense for
}

// MARK: - All Assist Actions

let allAssistActions: [AIAssistAction] = [
    AIAssistAction(icon: "wand.and.stars",                       label: "Make clearer",             appliesWhen: ["general", "reflection", "teaching"]),
    AIAssistAction(icon: "arrow.down.right.and.arrow.up.left",  label: "Shorten",                  appliesWhen: ["general", "reflection", "announcement"]),
    AIAssistAction(icon: "heart",                                label: "Make kinder",              appliesWhen: ["general", "question", "reflection"]),
    AIAssistAction(icon: "book",                                 label: "Add scripture",            appliesWhen: ["reflection", "testimony", "teaching", "prayerRequest"]),
    AIAssistAction(icon: "text.quote",                           label: "Summarize",                appliesWhen: ["sermonClip", "teaching", "resource"]),
    AIAssistAction(icon: "hands.sparkles",                       label: "Turn into prayer",         appliesWhen: ["general", "reflection", "testimony"]),
    AIAssistAction(icon: "star",                                 label: "Turn into testimony",      appliesWhen: ["general", "reflection", "gratitude"]),
    AIAssistAction(icon: "xmark.circle",                         label: "Remove accusatory tone",   appliesWhen: ["general", "question"]),
    AIAssistAction(icon: "list.bullet",                          label: "Extract key points",       appliesWhen: ["sermonClip", "teaching"]),
    AIAssistAction(icon: "lightbulb",                            label: "Add reflection prompt",    appliesWhen: ["teaching", "sermonClip", "testimony"]),
]

// MARK: - AI Transform

func applyAssist(action: AIAssistAction, to text: String) async -> String {
    // Build a system prompt and tone based on the action label.
    let systemPrompt: String
    let tone: String

    switch action.label.lowercased() {
    case let l where l.contains("professional") || l.contains("clearer"):
        systemPrompt = "Rewrite the following text in a professional, polished tone. Return only the rewritten text:"
        tone = "formal"
    case let l where l.contains("kinder") || l.contains("friendly"):
        systemPrompt = "Rewrite the following text in a warm, friendly, conversational tone. Return only the rewritten text:"
        tone = "warm"
    case let l where l.contains("shorten") || l.contains("concise"):
        systemPrompt = "Condense the following text to be more concise while keeping the key message. Return only the rewritten text:"
        tone = "warm"
    case let l where l.contains("grammar"):
        systemPrompt = "Fix any grammar and spelling errors in the following text. Return only the corrected text:"
        tone = "warm"
    case let l where l.contains("scripture"):
        systemPrompt = "Add a relevant scripture reference that complements the following text. Return only the updated text with the scripture included:"
        tone = "teaching"
    case let l where l.contains("prayer"):
        systemPrompt = "Rewrite the following text as a heartfelt prayer. Return only the prayer text:"
        tone = "encouraging"
    case let l where l.contains("testimony"):
        systemPrompt = "Rewrite the following text as a personal testimony of faith. Return only the rewritten text:"
        tone = "encouraging"
    case let l where l.contains("summarize") || l.contains("key points"):
        systemPrompt = "Summarize the following text into the key points. Return only the summary:"
        tone = "formal"
    case let l where l.contains("accusatory"):
        systemPrompt = "Remove any accusatory or judgmental tone from the following text while preserving the core message. Return only the rewritten text:"
        tone = "warm"
    case let l where l.contains("reflection"):
        systemPrompt = "Add a thought-provoking reflection prompt at the end of the following text. Return only the updated text:"
        tone = "encouraging"
    default:
        systemPrompt = "Improve the following text. Return only the improved text:"
        tone = "warm"
    }

    // Combine the system prompt with the post text as the topic string.
    // Clamp to 300 chars to satisfy AmenAIFeaturesService's input validation.
    let combined = "\(systemPrompt)\n\n\(text)"
    let topic = String(combined.prefix(300))

    do {
        let response = try await AmenAIFeaturesService.shared.generateCreatorDraft(
            type: "post_rewrite",
            topic: topic,
            audience: "faith community",
            tone: tone
        )
        return response.draft
    } catch {
        // Return original text unchanged on any error.
        return text
    }
}

// MARK: - AI Assist Chip

private struct AIAssistChip: View {
    let action: AIAssistAction
    let isProcessing: Bool
    let onTap: () -> Void

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.systemScaled(13, weight: .medium))
                Text(action.label)
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.7))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
            }
            .opacity(isProcessing ? pulseOpacity : 1.0)
        }
        .buttonStyle(.plain)
        .onChange(of: isProcessing) { _, processing in
            if processing {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.4
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    pulseOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Result Preview Card

private struct ResultPreviewCard: View {
    let previewText: String
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }

            Text(previewText)
                .font(.systemScaled(14, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    onApply()
                } label: {
                    Text("Apply")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.82))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onDiscard()
                } label: {
                    Text("Discard")
                        .font(.systemScaled(13, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Pre-Publish AI Assist View

struct PrePublishAIAssistView: View {
    @Binding var postText: String
    let detectedIntent: String
    let onApply: (String) -> Void

    @StateObject private var entitlements = AmenAccountEntitlementService.shared
    @State private var showWritingCoachPaywall = false

    @State private var isExpanded: Bool = false
    @State private var isProcessing: Bool = false
    @State private var resultPreview: String? = nil
    @State private var activeActionId: UUID? = nil

    private var relevantActions: [AIAssistAction] {
        allAssistActions.filter { $0.appliesWhen.contains(detectedIntent) }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Result preview card (shown above the assist strip)
            if let preview = resultPreview {
                ResultPreviewCard(
                    previewText: preview,
                    onApply: {
                        onApply(preview)
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                            resultPreview = nil
                            activeActionId = nil
                            isExpanded = false
                        }
                    },
                    onDiscard: {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                            resultPreview = nil
                            activeActionId = nil
                        }
                    }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: resultPreview != nil)
            }

            // Collapsed pill or expanded card
            if isExpanded {
                expandedPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            } else {
                collapsedPill
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: Collapsed Pill

    private var collapsedPill: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))

                Text("AI Assist")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.6))

                Image(systemName: "chevron.up")
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Expanded Panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Pre-publish assist")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
                        isExpanded = false
                        resultPreview = nil
                        activeActionId = nil
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }

            // Action chips — horizontal scroll
            if relevantActions.isEmpty {
                Text("No suggestions for this post type.")
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.black.opacity(0.35))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(relevantActions) { action in
                            AIAssistChip(
                                action: action,
                                isProcessing: isProcessing && activeActionId == action.id
                            ) {
                                guard !isProcessing else { return }
                                if entitlements.hasAccess(to: .aiWritingCoach) {
                                    runAssist(action: action)
                                } else {
                                    showWritingCoachPaywall = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .sheet(isPresented: $showWritingCoachPaywall) {
                    AmenAccountPaywallView(
                        requiredTier: .amenPlus,
                        feature: "AI Writing Coach"
                    ) { showWritingCoachPaywall = false }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
        }
    }

    // MARK: Run Assist

    private func runAssist(action: AIAssistAction) {
        activeActionId = action.id
        isProcessing = true
        resultPreview = nil

        Task {
            let result = await applyAssist(action: action, to: postText)
            await MainActor.run {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                    resultPreview = result
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("AI Assist — Expanded / Reflection Intent") {
    ZStack {
        Color(white: 0.96).ignoresSafeArea()

        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                // Simulated post composer text area
                VStack(alignment: .leading, spacing: 6) {
                    Text("Composer")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("God has been teaching me so much about patience this season. It hasn't been easy, but I'm learning to trust the process even when I can't see where it's going.")
                        .font(.systemScaled(15))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.55))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                                )
                        )
                }

                // AI Assist panel — starts expanded in preview
                PrePublishAIAssistViewPreviewWrapper()
            }
            .padding(16)
        }
    }
}

/// Wrapper to start expanded for the preview
private struct PrePublishAIAssistViewPreviewWrapper: View {
    @State private var text = "God has been teaching me so much about patience this season. It hasn't been easy, but I'm learning to trust the process even when I can't see where it's going."

    var body: some View {
        PrePublishAIAssistView(
            postText: $text,
            detectedIntent: "reflection",
            onApply: { transformed in
                text = transformed
                print("Applied: \(transformed)")
            }
        )
        .onAppear {
            // Simulate expanded by default — tap the pill in the preview to expand
        }
    }
}
