// ScripturePreviewCardView.swift
// AMENAPP — Smart Comments Wave 3
//
// Compact verse preview card shown below a comment when a Bible reference is detected.
// Passes through BereanCitationGate before any verse text is displayed.
//
// Liquid Glass rules:
//   - Opaque white card background (no glass behind verse text — no-glass-on-glass rule)
//   - Reduce-transparency fallback: solid systemBackground

import SwiftUI
import Foundation

struct ScripturePreviewCardView: View {

    let reference: String
    var translation: String = "BSB"

    // MARK: - Load State

    private enum LoadState {
        case idle
        case loading
        case loaded(preview: ScripturePreview, citationVerified: Bool)
        case blocked      // Citation gate blocked emission
        case failed
    }

    @State private var loadState: LoadState = .idle

    // MARK: - Guard

    var body: some View {
        guard AMENFeatureFlags.shared.commentScripturePreviewEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(cardContent)
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch loadState {
            case .idle, .loading:
                skeletonView
            case .loaded(let preview, let verified):
                loadedView(preview: preview, citationVerified: verified)
            case .blocked:
                blockedView
            case .failed:
                failedView
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .task {
            await loadPreview()
        }
    }

    // MARK: - Loaded View

    private func loadedView(preview: ScripturePreview, citationVerified: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Reference pill + translation code
            HStack(spacing: 8) {
                referencePill(text: "\(preview.reference) · \(preview.translation)")
                Spacer()
                verificationChip(verified: citationVerified)
            }

            // Verse text — opaque, no glass behind text
            Text(preview.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)

            // Cross-reference count
            if let crossCount = preview.crossReferenceCount, crossCount > 0 {
                Text("\(crossCount) cross-reference\(crossCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }

            // Attribution
            // TODO: Wave 3 deploy — resolve a real ScriptureSource from the knowledge graph
            // and pass it here. For now show a plain attribution line.
            Text("Berean Standard Bible")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .padding(.top, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // TODO: Wave 4 navigation — open Berean study mode for this reference
            // NavigationRouter.shared.push(.bereanStudy(reference: preview.reference))
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 120, height: 16)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .systemGray5))
                .frame(height: 12)
                .padding(.horizontal, 14)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 180, height: 12)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Blocked / Failed Views

    private var blockedView: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            Text("[Reference could not be verified]")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var failedView: some View {
        Text("Unable to load verse preview.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    // MARK: - Sub-Components

    private func referencePill(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "book.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue.opacity(0.8))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.blue.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.blue.opacity(0.08))
                .overlay(Capsule().strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.5))
        )
        .padding(.leading, 14)
    }

    private func verificationChip(verified: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: verified ? "checkmark.seal.fill" : "questionmark.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(verified ? Color.green : Color.orange)
            Text(verified ? "Verified" : "Unverified")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(verified ? Color.green : Color.orange)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(verified ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
        )
        .padding(.trailing, 14)
    }

    // MARK: - Card Background

    @ViewBuilder
    private var cardBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Color(uiColor: .systemBackground)
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    // MARK: - Load Logic

    private func loadPreview() async {
        loadState = .loading

        // Use an empty quotation — we're displaying the reference, not verifying a user's quote
        let (verdict, shouldBlock) = await BereanCitationGate.guardedEmit(
            reference: reference,
            quotation: "",
            depth: .quick,
            translation: translation
        )

        if shouldBlock {
            loadState = .blocked
            return
        }

        // Build a lightweight ScripturePreview from the verdict.
        // The actual verse text connector (fetchVerse) is a Wave 4 deploy item.
        // Until then we show a "text unavailable" message rather than fabricate content.
        let verseText = verdict.actualText ?? ""
        if verseText.isEmpty {
            // If no text is available from the citation gate, show blocked state to avoid
            // showing an empty card; the reference is verified but text isn't loaded yet.
            loadState = .blocked
            return
        }

        let preview = ScripturePreview(
            reference: reference,
            translation: translation,
            text: verseText,
            citationVerified: verdict.result == .verified || verdict.result == .paraphrase,
            crossReferenceCount: nil,
            cachedAt: Date().timeIntervalSince1970
        )

        let citationVerified = verdict.result == .verified || verdict.result == .paraphrase
        loadState = .loaded(preview: preview, citationVerified: citationVerified)
    }
}
