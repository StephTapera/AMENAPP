// ContentScriptureMatchView.swift
// AMEN App — Community Around Content OS / Berean Connector
//
// Displays Berean-matched scripture connections for a ContentObject.
// Gated by CommunityOSFlag.bereanContentConnector.

import SwiftUI

// MARK: - ContentScriptureMatchView

struct ContentScriptureMatchView: View {

    let contentObject: ContentObject

    // MARK: State

    @State private var verses: [BereanScriptureChip] = []
    @State private var isExpanded: Bool = true
    @State private var isLoading: Bool = true

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        guard CommunityOSFlagService.shared.isEnabled(.bereanContentConnector) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                if isExpanded {
                    expandedContent
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(reduceMotion ? .none : AppAnimation.stateChange, value: isExpanded)
            .task { await loadVerses() }
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))

                Text("Scripture Connections")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .animation(reduceMotion ? .none : AppAnimation.stateChange, value: isExpanded)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scripture Connections, \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") scripture connections")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        if isLoading {
            loadingState
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else if verses.isEmpty {
            emptyState
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(verses, id: \.reference) { chip in
                    ScriptureChipRow(chip: chip)

                    if chip.reference != verses.last?.reference {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        HStack(spacing: 10) {
            RotatingSpinner()
                .accessibilityHidden(true)

            Text("Berean is discovering connections\u{2026}")
                .font(.systemScaled(13))
                .foregroundStyle(Color(.secondaryLabel))

            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityLabel("Loading scripture connections")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.systemScaled(14))
                .foregroundStyle(Color(.secondaryLabel))

            Text("No connections found")
                .font(.systemScaled(13))
                .foregroundStyle(Color(.secondaryLabel))

            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityLabel("No scripture connections found")
    }

    // MARK: - Data Loading

    private func loadVerses() async {
        isLoading = true
        let result = await BereanContentConnector.shared.findVerses(for: contentObject)
        verses = result
        isLoading = false
        dlog("[ContentScriptureMatchView] Loaded \(result.count) verses for '\(contentObject.title)'")
    }
}

// MARK: - ScriptureChipRow

private struct ScriptureChipRow: View {

    let chip: BereanScriptureChip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(chip.reference)
                    .font(.systemScaled(13, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Spacer()

                if !chip.translation.isEmpty {
                    Text(chip.translation)
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }

            if !chip.text.isEmpty {
                Text(chip.text)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: chip))
    }

    private func accessibilityLabel(for chip: BereanScriptureChip) -> String {
        if chip.text.isEmpty {
            return "Scripture: \(chip.reference)."
        }
        return "Scripture: \(chip.reference). \(chip.text)"
    }
}

// MARK: - RotatingSpinner

/// A lightweight spinning SF symbol that respects reduce-motion.
private struct RotatingSpinner: View {

    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "sparkle")
            .font(.systemScaled(14))
            .foregroundStyle(Color(.secondaryLabel))
            .rotationEffect(.degrees(reduceMotion ? 0 : angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: 1.6)
                    .repeatForever(autoreverses: false)
                ) {
                    angle = 360
                }
            }
    }
}
