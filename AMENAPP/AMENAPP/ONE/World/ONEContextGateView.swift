// ONEContextGateView.swift
// ONE — Context gate: three checks required before comment is enabled.
// P3-F | Honest design: if user hasn't engaged, comment is blocked — not throttled.
//
// Three checks:
//   1. sourceRead  — user taps "View Source" and confirms
//   2. watchPassed — for video: watched ≥30%; for text-only: auto-passes
//   3. provenanceAcknowledged — user expands provenance label and dismisses

import SwiftUI

struct ONEContextGateView: View {
    let item: ONEFeedItemViewModel
    let gateStatus: ONEContextGateStatus
    var onSourceRead: () -> Void
    var onWatchProgress: (Double) -> Void
    var onProvenanceAcknowledged: () -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localStatus: ONEContextGateStatus
    @State private var commentText = ""
    @State private var showProvenanceDetail = false
    @State private var watchSimProgress: Double = 0
    @State private var isWatching: Bool = false
    @State private var showWhyExpanded = false

    init(
        item: ONEFeedItemViewModel,
        gateStatus: ONEContextGateStatus,
        onSourceRead: @escaping () -> Void,
        onWatchProgress: @escaping (Double) -> Void,
        onProvenanceAcknowledged: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.gateStatus = gateStatus
        self.onSourceRead = onSourceRead
        self.onWatchProgress = onWatchProgress
        self.onProvenanceAcknowledged = onProvenanceAcknowledged
        self.onDismiss = onDismiss
        _localStatus = State(initialValue: gateStatus)
        // Text-only items auto-pass the watch check
        var seed = gateStatus
        if !item.hasVideo { seed.watchFraction = 1.0 }
        _localStatus = State(initialValue: seed)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ONE.Spacing.lg) {
                    headerSection
                    gateRows
                    if localStatus.allPassed { commentSection }
                    whySection
                    Color.clear.frame(height: ONE.Spacing.xl)
                }
                .padding(ONE.Spacing.lg)
            }
            .navigationTitle("Know before you respond")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showProvenanceDetail) { provenanceDetailSheet }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.xs) {
            Text("ONE asks you to engage with content before commenting.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Gate rows

    private var gateRows: some View {
        VStack(spacing: ONE.Spacing.sm) {
            gateRow(
                passed: localStatus.sourceRead,
                icon: "doc.text.fill",
                title: "Read the source",
                actionLabel: localStatus.sourceRead ? "Read ✓" : "View Source →",
                actionDisabled: localStatus.sourceRead
            ) {
                onSourceRead()
                withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                    localStatus.sourceRead = true
                }
            }

            if item.hasVideo {
                videoWatchRow
            } else {
                gateRow(
                    passed: true,
                    icon: "checkmark.circle.fill",
                    title: "Watched enough",
                    actionLabel: "Text only — passes automatically",
                    actionDisabled: true
                ) {}
            }

            gateRow(
                passed: localStatus.provenanceAcknowledged,
                icon: "camera.badge.clock.fill",
                title: "Acknowledged provenance",
                actionLabel: localStatus.provenanceAcknowledged ? "Acknowledged ✓" : "View Label →",
                actionDisabled: localStatus.provenanceAcknowledged
            ) {
                showProvenanceDetail = true
            }
        }
    }

    private func gateRow(
        passed: Bool,
        icon: String,
        title: String,
        actionLabel: String,
        actionDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: ONE.Spacing.md) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(passed ? ONE.Colors.repairGreen : Color.secondary)
                .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: passed)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button(actionLabel) { action() }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(actionDisabled ? .secondary : AmenTheme.Colors.amenGold)
                .disabled(actionDisabled)
        }
        .padding(ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(passed
                      ? ONE.Colors.repairGreen.opacity(0.06)
                      : Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)\(passed ? ", completed" : ", not yet completed")")
    }

    private var videoWatchRow: some View {
        HStack(spacing: ONE.Spacing.md) {
            Image(systemName: localStatus.watchPassed ? "checkmark.circle.fill" : "play.circle")
                .font(.system(size: 20))
                .foregroundStyle(localStatus.watchPassed ? ONE.Colors.repairGreen : .secondary)
                .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: localStatus.watchPassed)

            VStack(alignment: .leading, spacing: 4) {
                Text("Watched 30% of video")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(localStatus.watchPassed
                                  ? ONE.Colors.repairGreen
                                  : AmenTheme.Colors.amenGold)
                            .frame(width: geo.size.width * min(watchSimProgress, 1.0))
                            .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: watchSimProgress)
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            if localStatus.watchPassed {
                Text("Done ✓")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Button("Watch →") { startWatchSim() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .disabled(isWatching)
            }
        }
        .padding(ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(localStatus.watchPassed
                      ? ONE.Colors.repairGreen.opacity(0.06)
                      : Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Watch 30% of video\(localStatus.watchPassed ? ", completed" : ", not yet completed")")
    }

    private func startWatchSim() {
        guard !isWatching else { return }
        isWatching = true
        Task { @MainActor in
            while watchSimProgress < 0.30 {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms ticks
                watchSimProgress = min(1.0, watchSimProgress + 0.015)
                onWatchProgress(watchSimProgress)
                localStatus.watchFraction = watchSimProgress
            }
            isWatching = false
        }
    }

    // MARK: - Comment section (unlocked when gate passes)

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
            Text("Add your comment")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            TextEditor(text: $commentText)
                .font(.system(size: 14))
                .frame(minHeight: 80)
                .padding(ONE.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityLabel("Comment text field")
            Button("Post Comment") {
                onDismiss()
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ONE.Spacing.sm)
            .background(
                Capsule()
                    .fill(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? Color.secondary.opacity(0.3)
                          : AmenTheme.Colors.amenGold)
            )
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Post comment")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    // MARK: - Why section

    private var whySection: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.xs) {
            Button {
                withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                    showWhyExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Why does this matter?")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showWhyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Why does this matter?")
            .accessibilityHint(showWhyExpanded ? "Collapse explanation" : "Expand explanation")

            if showWhyExpanded {
                Text("Reactions without engagement degrade public conversation. ONE believes a comment carries more weight — and is kinder — when you've actually spent time with what you're responding to.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Provenance detail sheet

    private var provenanceDetailSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ONE.Spacing.lg) {
                let cls = item.provenance.displayClassification
                HStack(spacing: ONE.Spacing.md) {
                    Image(systemName: cls.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cls.displayLabel)
                            .font(.system(size: 18, weight: .semibold))
                        Text(cls.accessibilityLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
                    confidenceRow
                    if let note = item.provenance.processorNote {
                        labelRow("Processor", value: note)
                    }
                    labelRow("C2PA", value: item.provenance.c2paPayload != nil ? "Available" : "Not available")
                }
                Spacer()
                Button("Acknowledged") {
                    onProvenanceAcknowledged()
                    withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                        localStatus.provenanceAcknowledged = true
                    }
                    showProvenanceDetail = false
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ONE.Spacing.sm)
                .background(Capsule().fill(AmenTheme.Colors.amenGold))
                .accessibilityLabel("Acknowledge provenance information")
            }
            .padding(ONE.Spacing.lg)
            .navigationTitle("Content Provenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showProvenanceDetail = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var confidenceRow: some View {
        HStack {
            Text("Confidence")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AmenTheme.Colors.amenGold)
                        .frame(width: geo.size.width * Double(item.provenance.confidence))
                }
            }
            .frame(width: 80, height: 6)
            Text(String(format: "%.0f%%", item.provenance.confidence * 100))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
    }

    private func labelRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
