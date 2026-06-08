// LiveSermonModeView.swift
// AMENAPP — ChurchNotesOS
// Full-screen live sermon note-taking with AI processing and mandatory approval.

import SwiftUI

struct LiveSermonModeView: View {
    let spaceId: String?
    let onSaveApproved: (SermonReviewDraft, [NoteBlock]) -> Void
    let onDismiss: () -> Void

    @State private var blocks: [NoteBlock] = []
    @State private var recordingState: RecordingState = .idle
    @State private var draft: SermonReviewDraft = .empty
    @State private var showDraftReview = false
    @State private var isProcessing = false
    @State private var sermonTitle = ""
    @FocusState private var titleFocused: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum RecordingState { case idle, recording, processing }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Main content
                VStack(spacing: 0) {
                    // Title field
                    TextField("Sermon title…", text: $sermonTitle)
                        .font(.title3.weight(.semibold))
                        .focused($titleFocused)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .accessibilityLabel("Sermon title")

                    Divider().opacity(0.3)

                    // Live mode banner
                    liveBanner

                    // Notes area
                    if blocks.isEmpty {
                        emptyStatePrompt
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(blocks) { block in
                                    NoteBlockRow(block: block)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 120)
                        }
                    }
                }

                // Bottom chrome
                VStack(spacing: 0) {
                    NoteBlockComposer { blockType in
                        insertBlock(blockType)
                    }
                    .padding(.horizontal, 8)

                    recordingControls
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
                .background {
                    if reduceTransparency {
                        Color(.systemBackground)
                    } else {
                        Rectangle().fill(.regularMaterial)
                    }
                }
            }
            .navigationTitle("Live Sermon Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
            .sheet(isPresented: $showDraftReview) {
                SermonReviewDraftReviewCard(
                    draft: $draft,
                    onApproveAndSave: { approvedDraft in
                        onSaveApproved(approvedDraft, blocks)
                        showDraftReview = false
                        onDismiss()
                    },
                    onDiscard: {
                        showDraftReview = false
                        draft = .empty
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var liveBanner: some View {
        HStack(spacing: 10) {
            switch recordingState {
            case .idle:
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
                Text("Tap Record to capture your sermon notes with AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .recording:
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(reduceMotion ? 1 : 1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(),
                        value: recordingState
                    )
                Text("Recording…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                // Waveform bars (static if reduce motion)
                WaveformBars(isAnimating: !reduceMotion)
            case .processing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating summary, questions, and prayer…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(recordingState == .recording ? Color.red.opacity(0.08) : Color.clear)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: recordingState)
    }

    @ViewBuilder
    private var emptyStatePrompt: some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.systemScaled(40))
                .foregroundStyle(.quaternary)
            Text("Your notes will appear here.\nUse the block row below to add structure.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        Spacer()
    }

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: 12) {
            switch recordingState {
            case .idle:
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                        recordingState = .recording
                    }
                } label: {
                    Label("Record", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start recording")

            case .recording:
                Button {
                    Task { await processRecording() }
                } label: {
                    Label("Stop & Process", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording and process with AI")

            case .processing:
                Label("Processing…", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
        }
    }

    // MARK: - Actions

    private func insertBlock(_ type: NoteBlockType) {
        let block = NoteBlock(id: UUID().uuidString, type: type, content: "")
        blocks.append(block)
    }

    private func processRecording() async {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            recordingState = .processing
        }
        // Simulate AI processing (real implementation calls Firebase callable)
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        draft = SermonReviewDraft(
            summary: sermonTitle.isEmpty
                ? "A powerful message was shared today. Key themes included faith, community, and God's provision."
                : "Pastor shared a powerful message in '\(sermonTitle)' about faith and community.",
            discussionQuestions: [
                "How has this message challenged your thinking this week?",
                "What one action will you take based on today's sermon?",
                "How can we as a community apply this teaching together?"
            ],
            closingPrayer: "Lord, let the seeds planted today take root in our hearts. Guide us to live out what we have heard. Amen.",
            speakerName: nil,
            seriesTitle: sermonTitle.isEmpty ? nil : sermonTitle
        )
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            recordingState = .idle
            showDraftReview = true
        }
    }
}

// MARK: - Note Block Model

struct NoteBlock: Identifiable {
    let id: String
    var type: NoteBlockType
    var content: String
}

// MARK: - Note Block Row

private struct NoteBlockRow: View {
    let block: NoteBlock

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.type.icon)
                .font(.systemScaled(13))
                .foregroundStyle(block.type.accent)
                .frame(width: 20, alignment: .center)
                .padding(.top, 3)
            Text(block.content.isEmpty ? block.type.displayName + "…" : block.content)
                .font(.body)
                .foregroundStyle(block.content.isEmpty ? .quaternary : .primary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Waveform Bars (decorative)

private struct WaveformBars: View {
    let isAnimating: Bool
    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5, 1.0, 0.6, 0.8, 0.45]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 3, height: 16 * height)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.4 + Double(index) * 0.1).repeatForever(autoreverses: true)
                            : nil,
                        value: heights[index]
                    )
            }
        }
        .onAppear {
            guard isAnimating else { return }
            for i in heights.indices {
                heights[i] = CGFloat.random(in: 0.2...1.0)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LiveSermonModeView(
        spaceId: nil,
        onSaveApproved: { _, _ in },
        onDismiss: {}
    )
}
