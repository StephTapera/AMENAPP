// FaithIntelView.swift
// AMEN Universal Accessibility Engine — A6 Faith Intelligence UI

import SwiftUI

// MARK: - FaithIntelOverlay

/// Inline overlay showing detected scripture reference chips for a piece of post text.
/// Only rendered when a11yFaithIntel is enabled and refs are present.
struct FaithIntelOverlay: View {
    let result: FaithIntelResult?

    @State private var selectedRef: FaithIntelScriptureRef?
    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared

    var body: some View {
        let isEnabled = flags.a11yFaithIntelEnabled
        let hasRefs   = !(result?.detectedRefs.isEmpty ?? true)

        if isEnabled, hasRefs, let result {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(result.detectedRefs, id: \.canonicalRef) { ref in
                        ScriptureRefChip(ref: ref) {
                            selectedRef = ref
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .accessibilityLabel("Scripture references detected in this post")
            .sheet(item: $selectedRef) { ref in
                ScriptureRefCard(ref: ref, relatedPassages: result.relatedPassages)
            }
        }
    }
}

// MARK: - ScriptureRefChip

/// Small pill showing a book icon and canonical reference label.
struct ScriptureRefChip: View {
    let ref: FaithIntelScriptureRef
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "book.closed.fill")
                    .font(.caption2.weight(.medium))
                Text(ref.canonicalRef)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.amenPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.amenPurple.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.amenPurple.opacity(0.3), lineWidth: 0.5)
            )
        }
        .accessibilityLabel("Scripture: \(ref.canonicalRef)")
        .accessibilityHint("Tap to read verse")
    }
}

// MARK: - ScriptureRefCard

/// Full sheet showing verse text, canonical reference, related passages, and AI badge.
struct ScriptureRefCard: View {
    let ref: FaithIntelScriptureRef
    let relatedPassages: [FaithIntelScriptureRef]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Canonical reference headline
                    Text(ref.canonicalRef)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    // Verse text
                    Text(ref.verseText)
                        .font(.title3.weight(.regular))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Verse: \(ref.verseText)")

                    Divider()

                    // Related passages
                    if !relatedPassages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Related Passages")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(relatedPassages, id: \.canonicalRef) { passage in
                                RelatedPassageRow(passage: passage)
                            }
                        }

                        Divider()
                    }

                    // AI Assisted badge at bottom
                    HStack {
                        Spacer()
                        AIContributionBadge()
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle(ref.book)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - RelatedPassageRow

private struct RelatedPassageRow: View {
    let passage: FaithIntelScriptureRef

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.amenPurple.opacity(0.7))
                    Text(passage.canonicalRef)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Related passage: \(passage.canonicalRef)")
            .accessibilityHint(isExpanded ? "Collapse verse" : "Expand to read verse")

            if isExpanded {
                Text(passage.verseText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityLabel("Verse: \(passage.verseText)")
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - FaithIntelScriptureRef + Identifiable

extension FaithIntelScriptureRef: Identifiable {
    var id: String { canonicalRef }
}

