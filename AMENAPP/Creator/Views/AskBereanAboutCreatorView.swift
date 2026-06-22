// AskBereanAboutCreatorView.swift
// AMENAPP — Creator Spotlight / Wave 4
//
// Ask Berean about this creator's teachings.
// Access-scoped: Berean only reads this creator's public content.
// Berean never invents quotes, titles, or positions.
// Scripture citations pass integrity check; unverifiable ones labeled [unverified].

import SwiftUI

struct AskBereanAboutCreatorView: View {

    let creatorId: String
    let creatorDisplayName: String

    @State private var freeFormInput: String = ""
    @State private var activeQuery: String?
    @State private var isLoading: Bool = false
    @State private var response: BereanCreatorResponse?
    @FocusState private var fieldFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let suggestedQuestions: [String] = [
        "Summarize recent teachings",
        "Where did they discuss Romans 8?",
        "What is their view on grace?",
        "Find their teaching on prayer",
        "Build a study plan from their content"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                suggestedQuestionsSection
                freeFormSection
                if let query = activeQuery {
                    responseSection(query: query)
                }
                disclaimers
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Ask Berean")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ask about \(creatorDisplayName)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Berean searches this creator's public content only.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Suggested Questions

    private var suggestedQuestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            CreatorQuestionLayout(spacing: 8) {
                ForEach(suggestedQuestions, id: \.self) { question in
                    CreatorQuestionChip(label: question) {
                        submitQuery(question)
                    }
                }
            }
        }
    }

    // MARK: - Free-Form Field

    private var freeFormSection: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if freeFormInput.isEmpty {
                    Text("Ask anything about their teachings...")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $freeFormInput, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .focused($fieldFocused)
                    .lineLimit(1...4)
                    .onSubmit {
                        let trimmed = freeFormInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { submitQuery(trimmed) }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
            )

            Button {
                let trimmed = freeFormInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { submitQuery(trimmed) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        freeFormInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.blue.opacity(0.3)
                            : Color.blue
                    )
            }
            .disabled(freeFormInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: freeFormInput.isEmpty)
        }
    }

    // MARK: - Response Area

    @ViewBuilder
    private func responseSection(query: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Query echo
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(query)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if isLoading {
                skeletonView
            } else if let resp = response {
                responseCard(resp)
            }
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(maxWidth: index == 3 ? 160 : .infinity)
                    .frame(height: 14)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        )
        .redacted(reason: .placeholder)
        .shimmering()
    }

    // MARK: - Response Card

    @ViewBuilder
    private func responseCard(_ resp: BereanCreatorResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Summarized by Berean")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            // Response text with [unverified] amber markers
            annotatedText(resp.text, unverifiedRanges: resp.unverifiedScriptureRanges)

            if !resp.contentIds.isEmpty {
                Divider()
                Text("From \(resp.contentIds.count) piece\(resp.contentIds.count == 1 ? "" : "s") of content")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        )
    }

    // MARK: - Annotated Text

    @ViewBuilder
    private func annotatedText(_ text: String, unverifiedRanges: [Range<String.Index>]) -> some View {
        if unverifiedRanges.isEmpty {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Build attributed string marking unverified scripture in amber
            Text(buildAnnotated(text: text, unverified: unverifiedRanges))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buildAnnotated(text: String, unverified: [Range<String.Index>]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in unverified {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].foregroundColor = .init(UIColor.systemOrange)
            }
        }
        return attributed
    }

    // MARK: - Disclaimers

    private var disclaimers: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "lock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Access-scoped: Berean only reads this creator's public content")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Berean never invents quotes, titles, or positions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Submit

    private func submitQuery(_ query: String) {
        freeFormInput = ""
        fieldFocused = false
        activeQuery = query
        isLoading = true
        response = nil
        Task {
            await loadResponse(for: query)
        }
    }

    private func loadResponse(for query: String) async {
        // TODO: call Berean Cloud Function:
        //   askBereanAboutCreator(creatorId: creatorId, query: query)
        // Stub: simulate network delay
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        response = BereanCreatorResponse(
            text: "This is a placeholder response. Wire to the Berean callable once deployed.",
            contentIds: [],
            unverifiedScriptureRanges: []
        )
        isLoading = false
    }
}

// MARK: - Glass Chip

private struct CreatorQuestionChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowLayout

private struct CreatorQuestionLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Shimmer modifier (accessibility-respecting)

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.4),
                            .clear
                        ]),
                        startPoint: .init(x: phase - 0.3, y: 0.5),
                        endPoint: .init(x: phase + 0.3, y: 0.5)
                    )
                    .blendMode(BlendMode.plusLighter)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Berean Creator Response model (local, stub)

private struct BereanCreatorResponse {
    let text: String
    let contentIds: [String]
    /// String.Index ranges in `text` where scripture could not be verified.
    let unverifiedScriptureRanges: [Range<String.Index>]
}
