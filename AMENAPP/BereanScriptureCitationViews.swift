
//  BereanScriptureCitationViews.swift
//  AMENAPP
//
//  Tappable Scripture citation chips for Berean AI responses.
//  Chips appear in a horizontal scroll; tapping one expands a verse
//  card inline below the chip row. Verse text is fetched lazily via
//  YouVersionBibleService and cached in-memory.
//
//  No modifications to BereanInteractiveUI, BereanOrchestrator, or BereanRAGService.

import SwiftUI

// MARK: - ScriptureCitationRow

/// Drop-in replacement for the existing VerseReferenceChip horizontal ScrollView.
/// Keeps the horizontal chip row and appends an animated verse card below
/// whenever a chip is selected.
struct ScriptureCitationRow: View {
    let references: [String]

    @State private var expandedRef: String?

    private let chipSpring = Animation.spring(response: 0.38, dampingFraction: 0.76)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Chip row ─────────────────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(references, id: \.self) { ref in
                        ScriptureCitationChip(
                            reference: ref,
                            isExpanded: expandedRef == ref
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(chipSpring) {
                                expandedRef = (expandedRef == ref) ? nil : ref
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // ── Expanded verse card ───────────────────────────────────────
            if let ref = expandedRef {
                ScriptureVerseCard(reference: ref)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top))
                                .combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                                .combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                    )
            }
        }
        .padding(.top, 14)
    }
}

// MARK: - ScriptureCitationChip

struct ScriptureCitationChip: View {
    let reference: String
    let isExpanded: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    private let chipBlue = Color(red: 0.48, green: 0.65, blue: 1.0)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 10, weight: .medium))

                Text(reference)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(chipBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(chipBlue.opacity(isExpanded ? 0.18 : 0.10))
                    .overlay(
                        Capsule()
                            .stroke(chipBlue.opacity(isExpanded ? 0.5 : 0.28), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(_ChipButtonStyle())
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isExpanded)
    }
}

private struct _ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - ScriptureVerseCard

struct ScriptureVerseCard: View {
    let reference: String

    @State private var passage: ScripturePassage?
    @State private var isLoading = true
    @State private var failed = false

    private let chipBlue = Color(red: 0.48, green: 0.65, blue: 1.0)

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if failed {
                errorView
            } else if let p = passage {
                verseView(p)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(chipBlue.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(chipBlue.opacity(0.18), lineWidth: 1)
                )
        )
        .task(id: reference) { await loadVerse() }
    }

    // ── Subviews ──────────────────────────────────────────────────────────

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.75)
                .tint(chipBlue)
            Text("Loading verse…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var errorView: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Verse unavailable")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func verseView(_ p: ScripturePassage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(p.reference)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(chipBlue)

                Spacer(minLength: 4)

                Text(p.version.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(chipBlue.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(chipBlue.opacity(0.12)))
            }

            Text(p.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(white: 0.22))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // ── Fetch ─────────────────────────────────────────────────────────────

    private func loadVerse() async {
        // Check lightweight in-memory cache first
        if let cached = BereanVerseCache.shared.get(reference) {
            passage = cached
            isLoading = false
            return
        }
        do {
            let p = try await YouVersionBibleService.shared.fetchVerse(reference: reference)
            BereanVerseCache.shared.set(reference, passage: p)
            await MainActor.run {
                passage = p
                isLoading = false
            }
        } catch {
            await MainActor.run {
                failed = true
                isLoading = false
            }
        }
    }
}

// MARK: - BereanVerseCache

/// Thread-safe in-memory cache for fetched ScripturePassage objects.
/// Intentionally separate from YouVersionBibleService's internal cache
/// so we don't reach into its private state.
final class BereanVerseCache {
    static let shared = BereanVerseCache()
    private var store: [String: ScripturePassage] = [:]
    private let queue = DispatchQueue(label: "com.amen.BereanVerseCache", attributes: .concurrent)

    private init() {}

    func get(_ key: String) -> ScripturePassage? {
        queue.sync { store[key] }
    }

    func set(_ key: String, passage: ScripturePassage) {
        queue.async(flags: .barrier) { self.store[key] = passage }
    }
}
