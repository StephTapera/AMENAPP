import SwiftUI

/// Displays real-time processing job status for a Church Notes media job.
struct ChurchNotesProcessingStatusCard: View {

    let job: ChurchNoteProcessingJob
    var onReviewTapped: () -> Void
    var onRetryTapped: (() -> Void)?
    var onDismissTapped: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 10) {
                sourceIcon
                    .font(.callout)
                    .foregroundStyle(statusColor)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.sourceType.displayLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(job.status.displayLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                Spacer()

                statusIndicator
            }

            // Progress bar (shown only for in-flight states)
            if [.uploading, .processing, .queued].contains(job.status) {
                progressBar
            }

            // Safety warning (shown only when flagged)
            if job.safetyStatus == "flagged" {
                Label("Content flagged for review", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Safety warning: content was flagged for review")
            }

            // Error message
            if let err = job.errorMessage, job.status == .failed {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Action buttons
            actionRow
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    private var sourceIcon: some View {
        Image(systemName: job.sourceType.sfSymbol)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch job.status {
        case .queued, .uploading, .processing:
            ProgressView()
                .scaleEffect(0.85)
                .accessibilityLabel("Processing in progress")
        case .draftReady:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Draft ready for review")
        case .approved:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Draft approved")
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Draft rejected")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Processing failed")
        case .canceled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Canceled")
        }
    }

    private var progressBar: some View {
        let progress = job.progress / 100.0
        return VStack(alignment: .leading, spacing: 4) {
            if progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(statusColor)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: progress)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(statusColor)
            }
        }
        .accessibilityLabel("Progress: \(Int(progress * 100)) percent")
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            if job.status == .draftReady {
                Button("Review Draft") { onReviewTapped() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Review AI draft")
                    .accessibilityHint("Opens the draft for your review and approval before adding to notes")
            }

            if job.status == .failed, let retry = onRetryTapped {
                Button("Retry") { retry() }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Retry processing")
            }

            Spacer()

            if job.status.isTerminal, let dismiss = onDismissTapped {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss status")
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch job.status {
        case .queued, .uploading, .processing: return .accentColor
        case .draftReady:                       return .green
        case .approved:                         return .green
        case .rejected:                         return .secondary
        case .failed:                           return .red
        case .canceled:                         return .secondary
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Color(.secondarySystemBackground).opacity(0.92)
        }
    }

    private var accessibilityDescription: String {
        "\(job.sourceType.displayLabel). \(job.status.displayLabel)."
        + (job.status == .draftReady ? " Review draft to add to notes." : "")
        + (job.status == .failed ? " \(job.errorMessage ?? "Processing failed.")" : "")
    }
}

// MARK: - Job list (used in editor)

/// Shows all active processing jobs for a note in a compact list.
struct ChurchNotesProcessingJobList: View {

    let jobs: [ChurchNoteProcessingJob]
    var onReviewJob: (ChurchNoteProcessingJob) -> Void
    var onDismissJob: (ChurchNoteProcessingJob) -> Void

    var body: some View {
        if !jobs.isEmpty {
            VStack(spacing: 8) {
                ForEach(jobs, id: \.id) { job in
                    ChurchNotesProcessingStatusCard(
                        job: job,
                        onReviewTapped: { onReviewJob(job) },
                        onDismissTapped: { onDismissJob(job) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
