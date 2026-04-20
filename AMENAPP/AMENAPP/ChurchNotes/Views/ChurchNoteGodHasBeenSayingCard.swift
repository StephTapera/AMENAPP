// ChurchNoteGodHasBeenSayingCard.swift
// AMENAPP
//
// "God Has Been Saying…" — the signature intelligence feature.
//
// This view surfaces recurring themes, scriptures, and reflection patterns
// from the user's church notes over time.
//
// IMPORTANT FRAMING RULES (non-negotiable):
//   - Never implies divine certainty or speaks on God's behalf.
//   - Language is always reflective and transparent:
//     "Your notes often return to…" not "God is telling you…"
//   - User can dismiss, control, or restore this view.
//   - All data is private — never shown to others.
//
// Appears as:
//   1. A compact card in the notes list (ChurchNoteGodHasBeenSayingCard)
//   2. A full detail sheet (ChurchNoteGodHasBeenSayingDetailView)

import SwiftUI

// MARK: - Compact Card (for notes list)

struct ChurchNoteGodHasBeenSayingCard: View {

    let summary: ChurchNotesSummary
    let onViewDetail: () -> Void
    let onDismiss: () -> Void

    @State private var isDismissed = false

    var body: some View {
        if !isDismissed && summary.hasContent {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                    .padding(16)

                if !summary.reflectionStatement.isEmpty {
                    Text(summary.reflectionStatement)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if !summary.topThemes.isEmpty {
                    themeRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }

                Divider()
                    .padding(.horizontal, 16)

                cardFooter
                    .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ChurchNotesDesignTokens.Radius.card, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Patterns in your notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text("Themes that keep appearing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                withAnimation(ChurchNotesAnimationTokens.sectionExpand) {
                    isDismissed = true
                }
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss patterns card")
        }
    }

    // MARK: - Theme Row

    private var themeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(summary.topThemes.prefix(5)) { theme in
                    themeChip(theme)
                }
            }
        }
    }

    private func themeChip(_ theme: CNThemePattern) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(theme.theme)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(theme.noteCount) note\(theme.noteCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(theme.theme): appeared in \(theme.noteCount) notes")
    }

    // MARK: - Footer

    private var cardFooter: some View {
        Button(action: onViewDetail) {
            HStack {
                Text("See full pattern summary")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View full pattern summary")
    }
}

// MARK: - Full Detail View

struct ChurchNoteGodHasBeenSayingDetailView: View {

    let summary: ChurchNotesSummary
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    frameStatement
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if !summary.topThemes.isEmpty {
                        themesSection
                            .padding(.horizontal, 16)
                    }

                    if !summary.repeatedScriptures.isEmpty {
                        scripturesSection
                            .padding(.horizontal, 16)
                    }

                    if let posture = summary.postureTrend {
                        postureSection(posture)
                            .padding(.horizontal, 16)
                    }

                    noteCadenceSection
                        .padding(.horizontal, 16)

                    privacyFooter
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Patterns in your notes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Frame Statement

    private var frameStatement: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("A quiet reflection")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            if !summary.reflectionStatement.isEmpty {
                Text(summary.reflectionStatement)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("This is based on the themes, tags, and scriptures in your own notes — not a prediction or promise. Only you can see this.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Themes Section

    private var themesSection: some View {
        sectionCard(title: "Recurring themes", icon: "tag.fill") {
            VStack(spacing: 0) {
                ForEach(Array(summary.topThemes.enumerated()), id: \.element.id) { index, theme in
                    themeRow(theme, isLast: index == summary.topThemes.count - 1)
                }
            }
        }
    }

    private func themeRow(_ theme: CNThemePattern, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(theme.theme)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if theme.isRecurring {
                            Text("Recurring")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                    Text(theme.summaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Quiet frequency bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: CGFloat(min(theme.noteCount, 6)) * 8, height: 4)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            if !isLast {
                Divider().padding(.horizontal, 16)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(theme.theme): \(theme.summaryLabel)")
    }

    // MARK: - Scriptures Section

    private var scripturesSection: some View {
        sectionCard(title: "Scriptures you return to", icon: "book.fill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(summary.repeatedScriptures) { ref in
                        scriptureChip(ref)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func scriptureChip(_ ref: CNScripturePattern) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ref.reference)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(ref.timesAttached)×")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ref.reference): attached \(ref.timesAttached) times")
    }

    // MARK: - Posture Section

    private func postureSection(_ posture: CNPostureSignal) -> some View {
        sectionCard(title: "A possible tone", icon: posture.icon) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: posture.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(posture.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Detected from common patterns in your note language")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)

                Divider().padding(.horizontal, 14)

                Text(posture.suggestedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Note Cadence

    private var noteCadenceSection: some View {
        sectionCard(title: "Your note rhythm", icon: "chart.line.uptrend.xyaxis") {
            HStack(spacing: 0) {
                cadenceStat(
                    label: "Last 30 days",
                    value: "\(summary.noteCountLast30Days)",
                    sub: "note\(summary.noteCountLast30Days == 1 ? "" : "s")"
                )
                Divider().frame(height: 44)
                cadenceStat(
                    label: "All time",
                    value: "\(summary.noteCountAllTime)",
                    sub: "note\(summary.noteCountAllTime == 1 ? "" : "s")"
                )
            }
            .padding(.vertical, 12)
        }
    }

    private func cadenceStat(label: String, value: String, sub: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(sub)")
    }

    // MARK: - Privacy Footer

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("This summary is private and only visible to you.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Section Card helper

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            content()
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

#if DEBUG
struct ChurchNoteGodHasBeenSayingCard_Previews: PreviewProvider {

    static let sampleSummary = ChurchNotesSummary(
        id: "preview",
        topThemes: [
            CNThemePattern(id: "trust", theme: "Trust", noteCount: 5, recentNoteIds: [], firstSeenAt: .now, lastSeenAt: .now),
            CNThemePattern(id: "surrender", theme: "Surrender", noteCount: 4, recentNoteIds: [], firstSeenAt: .now, lastSeenAt: .now),
            CNThemePattern(id: "waiting", theme: "Waiting", noteCount: 3, recentNoteIds: [], firstSeenAt: .now, lastSeenAt: .now),
        ],
        repeatedScriptures: [
            CNScripturePattern(reference: "Psalm 46:10", book: "Psalms", timesAttached: 3, lastSeenAt: .now),
            CNScripturePattern(reference: "Romans 8:28", book: "Romans", timesAttached: 2, lastSeenAt: .now),
        ],
        postureTrend: .expectant,
        noteCountLast30Days: 8,
        noteCountAllTime: 24,
        reflectionStatement: "Your recent notes often return to trust, surrender, and waiting.",
        generatedAt: .now,
        showInsights: true,
        dismissedAt: nil
    )

    static var previews: some View {
        Group {
            ScrollView {
                VStack {
                    ChurchNoteGodHasBeenSayingCard(
                        summary: sampleSummary,
                        onViewDetail: {},
                        onDismiss: {}
                    )
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .previewDisplayName("Compact card")

            ChurchNoteGodHasBeenSayingDetailView(
                summary: sampleSummary,
                onDismiss: {}
            )
            .previewDisplayName("Full detail view")
        }
    }
}
#endif
