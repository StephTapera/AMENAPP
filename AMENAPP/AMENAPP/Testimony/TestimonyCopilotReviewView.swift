// TestimonyCopilotReviewView.swift
// AMENAPP — ARISE / OUTPOUR Creator Co-Pilot confirm-gate.
//
// This is the human gate. The co-pilot job parks at .creatorReview with inert,
// confidence-scored suggestions; NOTHING publishes until the creator explicitly
// selects artifacts and taps Confirm. Honors CalmCap CC4: no autoplay-chaining —
// clips are shown as static, tappable references, never auto-previewed.
//
// Captions are disclosed to the creator as AuthenticityKind.aiAssistedCaptions
// (label "AI-assisted captions"). Confidence is shown as a coarse qualitative band,
// never a numeric score (no vanity metric, CP-I2).

import SwiftUI

struct TestimonyCopilotReviewView: View {

    let job: CopilotJob

    /// Invoked only when the creator confirms a non-empty selection. The host wires this
    /// to the confirmation callable. Nothing in this view publishes on its own.
    let onConfirm: (CopilotConfirmation) -> Void
    let onDiscard: () -> Void

    @State private var selectedChapterIds: Set<String> = []
    @State private var selectedClipIds: Set<String> = []
    @State private var selectedQuestionIds: Set<String> = []
    @State private var selectedCaptionIds: Set<String> = []

    private var hasSelection: Bool {
        !(selectedChapterIds.isEmpty
            && selectedClipIds.isEmpty
            && selectedQuestionIds.isEmpty
            && selectedCaptionIds.isEmpty)
    }

    private var isReviewable: Bool {
        job.state == .creatorReview
    }

    var body: some View {
        NavigationStack {
            List {
                inertNoticeSection

                if isReviewable {
                    chaptersSection
                    clipsSection
                    questionsSection
                    captionsSection
                } else {
                    Section {
                        Text("This co-pilot run is not ready for review (state: \(job.state.rawValue)).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Review Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive, action: onDiscard)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                        .disabled(!isReviewable || !hasSelection)
                }
            }
            .safeAreaInset(edge: .bottom) {
                confirmFooter
            }
        }
    }

    // MARK: - Sections

    private var inertNoticeSection: some View {
        Section {
            Label {
                Text("Nothing publishes until you confirm. These are AI suggestions you can edit, accept, or discard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var chaptersSection: some View {
        Section("Suggested Chapters") {
            if job.suggestedChapters.isEmpty {
                emptyRow("No chapters suggested.")
            } else {
                ForEach(job.suggestedChapters) { chapter in
                    selectableRow(
                        isSelected: selectedChapterIds.contains(chapter.id),
                        confidence: chapter.confidence,
                        title: chapter.title,
                        subtitle: "\(timecode(chapter.startSeconds)) – \(timecode(chapter.endSeconds))",
                        detail: chapter.summary
                    ) {
                        toggle(chapter.id, in: &selectedChapterIds)
                    }
                }
            }
        }
    }

    private var clipsSection: some View {
        // CC4: clips are static references — no autoplay, no chaining.
        Section("Suggested Clips") {
            if job.suggestedClips.isEmpty {
                emptyRow("No clips suggested.")
            } else {
                ForEach(job.suggestedClips) { clip in
                    selectableRow(
                        isSelected: selectedClipIds.contains(clip.id),
                        confidence: clip.confidence,
                        title: clip.label,
                        subtitle: "\(timecode(clip.startSeconds)) – \(timecode(clip.endSeconds))",
                        detail: clip.scriptureRefs.joined(separator: ", ")
                    ) {
                        toggle(clip.id, in: &selectedClipIds)
                    }
                }
            }
        }
    }

    private var questionsSection: some View {
        Section("Discussion Questions") {
            if job.suggestedQuestions.isEmpty {
                emptyRow("No questions suggested.")
            } else {
                ForEach(job.suggestedQuestions) { question in
                    selectableRow(
                        isSelected: selectedQuestionIds.contains(question.id),
                        confidence: question.confidence,
                        title: question.prompt,
                        subtitle: question.scriptureRefs.joined(separator: ", "),
                        detail: nil
                    ) {
                        toggle(question.id, in: &selectedQuestionIds)
                    }
                }
            }
        }
    }

    private var captionsSection: some View {
        Section("Captions") {
            if job.suggestedCaptions.isEmpty {
                emptyRow("No captions suggested.")
            } else {
                ForEach(job.suggestedCaptions) { caption in
                    selectableRow(
                        isSelected: selectedCaptionIds.contains(caption.id),
                        confidence: caption.confidence,
                        title: caption.text,
                        subtitle: caption.language.uppercased(),
                        detail: disclosureLabel(for: caption.authenticityKind)
                    ) {
                        toggle(caption.id, in: &selectedCaptionIds)
                    }
                }
            }
        }
    }

    private var confirmFooter: some View {
        VStack(spacing: 8) {
            Text(hasSelection
                ? "Confirming will publish only the items you selected."
                : "Select at least one suggestion to confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: confirm) {
                Text("Confirm Selected")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReviewable || !hasSelection)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Row builder

    @ViewBuilder
    private func selectableRow(
        isSelected: Bool,
        confidence: Double,
        title: String,
        subtitle: String,
        detail: String?,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    confidenceBadge(confidence)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // Coarse qualitative band — never a numeric score (CP-I2, no vanity metric).
    @ViewBuilder
    private func confidenceBadge(_ confidence: Double) -> some View {
        let band: String = confidence >= 0.75 ? "High match"
            : confidence >= 0.4 ? "Possible match"
            : "Low match"
        Text(band)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Logic

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func confirm() {
        guard isReviewable, hasSelection else { return }
        let confirmation = CopilotConfirmation(
            jobId: job.jobId,
            ownerId: job.ownerId,
            acceptedChapterIds: Array(selectedChapterIds),
            acceptedClipIds: Array(selectedClipIds),
            acceptedQuestionIds: Array(selectedQuestionIds),
            acceptedCaptionIds: Array(selectedCaptionIds),
            confirmedAtUTC: Date().timeIntervalSince1970
        )
        onConfirm(confirmation)
    }

    private func disclosureLabel(for kind: CopilotAuthenticityKind) -> String {
        switch kind {
        case .aiAssistedCaptions: return "AI-assisted captions"
        case .aiAssistedTranslation: return "AI-assisted translation"
        case .transcriptApproved: return "Transcript approved"
        }
    }

    private func timecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
