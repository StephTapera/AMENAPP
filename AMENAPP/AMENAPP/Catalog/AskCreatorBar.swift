import SwiftUI

struct AskCreatorBar: View {

    @Binding var query: String
    var onSubmit: () async -> Void
    var result: AskCreatorResult?
    var isLoading: Bool

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            queryField
            if isLoading {
                loadingIndicator
            } else if let result {
                resultView(result: result)
            }
        }
        .padding(14)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Query Field

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Ask this creator anything...", text: $query)
                .font(.systemScaled(14))
                .submitLabel(.send)
                .focused($fieldFocused)
                .onSubmit {
                    Task { await onSubmit() }
                }
            if !query.isEmpty {
                Button {
                    Task { await onSubmit() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(.primary)
                }
                .disabled(isLoading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(0.06))
        )
    }

    // MARK: - Loading

    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Finding answer...")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func resultView(result: AskCreatorResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                modeBadge(result: result)
                Spacer()
                Text(String(format: "%.0f%% confidence", result.confidence * 100))
                    .font(.systemScaled(11))
                    .foregroundStyle(.tertiary)
            }

            if result.refused {
                refusedBanner
            } else {
                Text(result.answer)
                    .font(.systemScaled(14))
                    .foregroundStyle(.primary)

                if !result.citations.isEmpty {
                    Divider()
                    Text("Sources")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(result.citations) { citation in
                        citationRow(citation: citation)
                    }
                }
            }
        }
    }

    private func modeBadge(result: AskCreatorResult) -> some View {
        let label = result.mode == "creator_said" ? "Creator Said" : "AI Summary"
        let color: Color = result.mode == "creator_said" ? .green : .secondary
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    private var refusedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(13))
                .foregroundStyle(.orange)
            Text("This question couldn't be answered from this creator's catalog.")
                .font(.systemScaled(13))
                .foregroundStyle(.orange)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.orange.opacity(0.08))
        )
    }

    private func citationRow(citation: CatalogCitation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(citation.snippet)
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let url = URL(string: citation.sourceUrl) {
                Link("Open Work", destination: url)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.05))
        )
    }
}
