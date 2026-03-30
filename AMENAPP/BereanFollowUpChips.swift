// BereanFollowUpChips.swift
// AMEN Berean — Smart follow-up chips + thinking status rotator.
//
// BereanFollowUpChipRow  — horizontal scrolling chip strip that appears after
//                          each AI response. Staggered entrance. Mode-aware.
// BereanThinkingStatus   — animated rotating status text during generation.
//                          Replaces a generic spinner with contextual phrases.
//
// Usage — follow-up chips (place below last assistant bubble):
//   BereanFollowUpChipRow(
//       modeID: BereanModeStore.shared.selectedMode.id,
//       responseHint: lastResponseText,
//       onChipTap: { prompt in viewModel.send(prompt) }
//   )
//
// Usage — thinking status (shown while isGenerating):
//   if isGenerating {
//       BereanThinkingStatus(modeID: BereanModeStore.shared.selectedMode.id)
//           .padding(.leading, 16)
//   }

import SwiftUI

// MARK: - Follow-Up Chip Model

struct BereanResponseChip: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let prompt: String   // empty string = treat as a local action (save, copy, etc.)
}

// MARK: - Context-Aware Chip Sets

extension BereanResponseChip {
    /// Returns 4 chips appropriate for `modeID` and keywords in `responseHint`.
    static func chips(forModeID modeID: String, responseHint: String = "") -> [BereanResponseChip] {
        let lower = responseHint.lowercased()

        switch modeID {
        case "prayer":
            return [
                BereanResponseChip(icon: "hands.sparkles",         label: "Pray this now",   prompt: "Turn your response into a prayer I can pray right now."),
                BereanResponseChip(icon: "book.pages",              label: "Add scripture",   prompt: "Add a supporting Bible verse to this."),
                BereanResponseChip(icon: "heart",                   label: "More comfort",    prompt: "Give me a more comforting, encouraging version of this."),
                BereanResponseChip(icon: "bookmark",                label: "Save",            prompt: ""),
            ]
        case "study":
            return [
                BereanResponseChip(icon: "chevron.down.2",          label: "Go deeper",       prompt: "Go deeper into this — more detail and cross-references."),
                BereanResponseChip(icon: "character.magnify",       label: "Orig. language",  prompt: "What does the original Greek or Hebrew say in this passage?"),
                BereanResponseChip(icon: "list.bullet",             label: "Break it down",   prompt: "Break this into clear, practical steps I can apply."),
                BereanResponseChip(icon: "arrow.counterclockwise",  label: "Simplify",        prompt: "Explain this in simpler, everyday language."),
            ]
        case "social", "rewrite", "creator":
            return [
                BereanResponseChip(icon: "pencil.and.sparkles",     label: "Make shorter",    prompt: "Make this more concise while keeping the heart of it."),
                BereanResponseChip(icon: "heart.text.square",        label: "More grace",      prompt: "Rewrite this with even more warmth and grace."),
                BereanResponseChip(icon: "arrowshape.turn.up.left", label: "As a reply",      prompt: "Format this as a direct conversational reply."),
                BereanResponseChip(icon: "square.and.pencil",        label: "Use as post",     prompt: ""),
            ]
        case "church":
            return [
                BereanResponseChip(icon: "doc.plaintext",            label: "Add to notes",    prompt: "Format this as clean church notes."),
                BereanResponseChip(icon: "book.pages",               label: "Add scripture",   prompt: "Add supporting scripture references."),
                BereanResponseChip(icon: "person.2",                 label: "Share idea",      prompt: "Help me share this with my church community."),
                BereanResponseChip(icon: "calendar",                 label: "Plan next steps", prompt: "Turn this into an action plan for the week."),
            ]
        case "safety":
            return [
                BereanResponseChip(icon: "pencil.and.sparkles",     label: "Softer version",  prompt: "Write a softer, calmer version of this."),
                BereanResponseChip(icon: "checkmark.shield",         label: "Send-ready",      prompt: "Make this safe and appropriate to send."),
                BereanResponseChip(icon: "hand.raised",              label: "Remove edge",     prompt: "Remove any harsh or reactive language."),
                BereanResponseChip(icon: "bookmark",                 label: "Save",            prompt: ""),
            ]
        default:
            // Standard — adapt to response keywords
            var chips: [BereanResponseChip] = []
            if lower.contains("verse") || lower.contains("scripture") || lower.contains("romans") || lower.contains("psalm") {
                chips.append(BereanResponseChip(icon: "book.pages", label: "More verses",
                                                prompt: "Show me more related Bible verses on this topic."))
            }
            chips += [
                BereanResponseChip(icon: "arrow.counterclockwise.circle", label: "Simplify",
                                   prompt: "Explain this in simpler, everyday language."),
                BereanResponseChip(icon: "chevron.down.2",                label: "Go deeper",
                                   prompt: "Tell me more — go deeper into this topic."),
                BereanResponseChip(icon: "hands.sparkles",               label: "Make a prayer",
                                   prompt: "Turn this response into a prayer I can pray."),
                BereanResponseChip(icon: "square.and.pencil",             label: "Draft a post",
                                   prompt: "Turn this into a faith-inspired post I can share on AMEN."),
                BereanResponseChip(icon: "bookmark",                      label: "Save",        prompt: ""),
            ]
            return Array(chips.prefix(4))
        }
    }
}

// MARK: - BereanFollowUpChipRow

struct BereanFollowUpChipRow: View {
    let modeID: String
    var responseHint: String = ""
    var onChipTap: (String) -> Void
    var onSaveAction: (() -> Void)? = nil

    @State private var visibleCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var chips: [BereanResponseChip] {
        BereanResponseChip.chips(forModeID: modeID, responseHint: responseHint)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.element.id) { idx, chip in
                    chipButton(chip, index: idx)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .onAppear { animateIn() }
    }

    @ViewBuilder
    private func chipButton(_ chip: BereanResponseChip, index: Int) -> some View {
        let isVisible = index < visibleCount

        Button {
            if chip.prompt.isEmpty {
                onSaveAction?()
            } else {
                onChipTap(chip.prompt)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: chip.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(chip.label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color(white: 0.20))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
                    .overlay(Capsule().strokeBorder(Color(white: 0, opacity: 0.08), lineWidth: 0.5))
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : 10)
        .animation(.spring(response: 0.38, dampingFraction: 0.72).delay(Double(index) * 0.06), value: visibleCount)
    }

    private func animateIn() {
        if reduceMotion {
            visibleCount = chips.count
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation { visibleCount = chips.count }
            }
        }
    }
}

// MARK: - BereanThinkingStatus

/// Animated thinking indicator shown during AI generation.
/// Rotates through context-aware status phrases with a soft spinning ring.
/// Replaces a plain "…" or spinner during streaming.
///
/// Drop directly above or below the loading indicator:
/// ```swift
/// if isGenerating {
///     BereanThinkingStatus(modeID: currentModeID)
/// }
/// ```
struct BereanThinkingStatus: View {
    let modeID: String

    @State private var phraseIndex = 0
    @State private var animRing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phrases: [String] {
        switch modeID {
        case "prayer":     return ["Praying with you…", "Crafting a prayer…", "Finding the right words…", "Preparing something meaningful…"]
        case "study":      return ["Searching scripture…", "Cross-referencing passages…", "Reviewing context…", "Comparing translations…"]
        case "deep":       return ["Thinking carefully…", "Weighing the nuance…", "Considering multiple angles…", "Preparing a thoughtful answer…"]
        case "social":     return ["Checking the tone…", "Finding the right approach…", "Drafting a kind response…", "Reviewing for clarity…"]
        case "safety":     return ["Reviewing the tone…", "Checking for civility…", "Considering how this lands…", "Preparing a safer version…"]
        case "church":     return ["Reviewing church context…", "Organizing the content…", "Structuring your notes…", "Preparing guidance…"]
        case "rewrite":    return ["Softening the tone…", "Finding better words…", "Rewriting with grace…", "Almost ready…"]
        case "creator":    return ["Sharpening the draft…", "Crafting the post…", "Polishing the language…", "Almost ready…"]
        default:           return ["Thinking…", "Searching scripture and context…", "Preparing a thoughtful response…", "Checking scripture…", "Drafting carefully…"]
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Spinning ring
            if !reduceMotion {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    Circle()
                        .trim(from: 0, to: 0.70)
                        .stroke(Color.primary.opacity(0.42), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(animRing ? 360 : 0))
                        .animation(.linear(duration: 0.90).repeatForever(autoreverses: false), value: animRing)
                }
            }

            Text(phrases[phraseIndex])
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal:   .opacity.combined(with: .move(edge: .top))
                ))
                .id(phraseIndex)
                .animation(.easeInOut(duration: 0.28), value: phraseIndex)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .overlay(Capsule().strokeBorder(Color(white: 0, opacity: 0.06), lineWidth: 0.5))
        )
        .onAppear {
            animRing = true
            startRotation()
        }
    }

    private func startRotation() {
        guard !reduceMotion else { return }
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .milliseconds(2400))
                withAnimation(.easeInOut(duration: 0.32)) {
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            }
        }
    }
}

// MARK: - Response Action Bar

/// Compact action row shown below completed AI responses.
/// Copy, Save, Share, Read Aloud, Add to Project, Turn into Prayer.
struct BereanResponseActionBar: View {
    var onCopy: () -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onTurnIntoPrayer: (() -> Void)? = nil
    var onAddToProject: (() -> Void)? = nil
    @State private var copiedFeedback = false

    var body: some View {
        HStack(spacing: 0) {
            actionButton("doc.on.doc", label: copiedFeedback ? "Copied!" : "Copy") {
                onCopy()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { copiedFeedback = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.8))
                    withAnimation { copiedFeedback = false }
                }
            }
            Divider().frame(height: 18).padding(.vertical, 2)
            actionButton("bookmark", label: "Save")     { onSave() }
            Divider().frame(height: 18).padding(.vertical, 2)
            actionButton("square.and.arrow.up", label: "Share") { onShare() }
            if let prayer = onTurnIntoPrayer {
                Divider().frame(height: 18).padding(.vertical, 2)
                actionButton("hands.sparkles", label: "Pray") { prayer() }
            }
            if let project = onAddToProject {
                Divider().frame(height: 18).padding(.vertical, 2)
                actionButton("folder.badge.plus", label: "Project") { project() }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0, opacity: 0.07), lineWidth: 0.5))
    }

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
