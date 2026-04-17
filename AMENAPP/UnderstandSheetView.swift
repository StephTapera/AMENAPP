// UnderstandSheetView.swift
// AMEN App — Accessibility Intelligence Layer (Phase 2)
//
// Glass bottom sheet with readability modes: Simplify, Summarize,
// Key Terms, Explain, Expand Context. Presented from UnderstandPillButton.
// Uses .ultraThinMaterial, Liquid Glass design, Motion.adaptive animations.

import SwiftUI

struct UnderstandSheetView: View {

    let originalText: String
    let contentId: String
    let initialMode: ReadabilityMode?

    @StateObject private var readabilityService = ReadabilityService.shared
    @State private var selectedMode: ReadabilityMode
    @State private var hasLoadedInitial = false
    @Environment(\.dismiss) private var dismiss

    init(originalText: String, contentId: String, initialMode: ReadabilityMode? = nil) {
        self.originalText = originalText
        self.contentId = contentId
        self.initialMode = initialMode
        _selectedMode = State(initialValue: initialMode ?? .simplify)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Mode selector pills
                    modePillStrip

                    // Content area
                    if readabilityService.isLoading {
                        loadingSkeleton
                    } else if let transform = readabilityService.currentTransform {
                        transformedContent(transform)
                    } else if let error = readabilityService.error {
                        errorView(error)
                    } else {
                        placeholderView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Understand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            guard !hasLoadedInitial else { return }
            hasLoadedInitial = true
            await loadTransform(mode: selectedMode)
        }
        .onDisappear {
            readabilityService.clearCurrentTransform()
        }
    }

    // MARK: - Mode Pill Strip

    private var modePillStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReadabilityMode.allCases, id: \.self) { mode in
                    modePill(mode)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private func modePill(_ mode: ReadabilityMode) -> some View {
        Button {
            guard mode != selectedMode else { return }
            HapticManager.impact(style: .light)
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
                selectedMode = mode
            }
            Task {
                await loadTransform(mode: mode)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 12, weight: .medium))
                Text(mode.displayName)
                    .font(AMENFont.semiBold(13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedMode == mode
                    ? Color.accentColor.opacity(0.15)
                    : Color(.tertiarySystemFill)
            )
            .foregroundStyle(
                selectedMode == mode
                    ? Color.accentColor
                    : Color(.secondaryLabel)
            )
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
    }

    // MARK: - Transformed Content

    @ViewBuilder
    private func transformedContent(_ transform: ReadabilityTransform) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mode description
            Text(selectedMode.description)
                .font(AMENFont.regular(13))
                .foregroundStyle(Color(.tertiaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Main transformed text
            Text(transform.transformedText)
                .font(AMENFont.regular(16))
                .foregroundStyle(Color(.label))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            // Key Terms section (only for keyTerms mode)
            if let keyTerms = transform.keyTerms, !keyTerms.isEmpty {
                keyTermsSection(keyTerms)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func keyTermsSection(_ terms: [KeyTermDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Terms")
                .font(AMENFont.bold(14))
                .foregroundStyle(Color(.label))

            ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                keyTermCard(term)
            }
        }
    }

    private func keyTermCard(_ term: KeyTermDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(term.term)
                .font(AMENFont.bold(15))
                .foregroundStyle(Color(.label))

            Text(term.definition)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color(.secondaryLabel))
                .lineSpacing(2)

            if let verse = term.relatedVerse {
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 10))
                    Text(verse)
                        .font(AMENFont.semiBold(12))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Loading Skeleton

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 16)
                    .frame(maxWidth: index == 3 ? 200 : .infinity)
                    .shimmer()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Error & Placeholder

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(Color(.tertiaryLabel))
            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await loadTransform(mode: selectedMode) }
            }
            .font(AMENFont.semiBold(14))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 24))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("Select a mode above to understand this content")
                .font(AMENFont.regular(14))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Load

    private func loadTransform(mode: ReadabilityMode) async {
        _ = await readabilityService.transform(
            text: originalText,
            contentId: contentId,
            mode: mode
        )
    }
}

// MARK: - Shimmer Modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color(.systemBackground).opacity(0.4),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .animation(
                    Animation.linear(duration: 1.5).repeatForever(autoreverses: false),
                    value: phase
                )
            )
            .clipped()
            .onAppear {
                phase = 300
            }
    }
}

extension View {
    fileprivate func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - ReadabilityMode Extensions

extension ReadabilityMode {
    var iconName: String {
        switch self {
        case .simplify: return "text.badge.minus"
        case .summarize: return "list.bullet"
        case .keyTerms: return "textformat.abc"
        case .explain: return "questionmark.circle"
        case .expandContext: return "clock.arrow.circlepath"
        }
    }

    var displayName: String {
        switch self {
        case .simplify: return "Simplify"
        case .summarize: return "Summarize"
        case .keyTerms: return "Key Terms"
        case .explain: return "Explain"
        case .expandContext: return "Context"
        }
    }

    var description: String {
        switch self {
        case .simplify: return "Rewritten at an accessible reading level"
        case .summarize: return "Key points from this content"
        case .keyTerms: return "Important terms and their meanings"
        case .explain: return "Explained for newcomers to faith"
        case .expandContext: return "Historical and theological background"
        }
    }
}
