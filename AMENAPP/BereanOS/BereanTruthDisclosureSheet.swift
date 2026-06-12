import SwiftUI

// MARK: - BereanTruthDisclosureSheet

/// Full-screen sheet that explains all Berean OS confidence levels so users
/// understand exactly what each label means.
struct BereanTruthDisclosureSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    confidenceLevelsSection
                    whyItMattersSection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Understanding Confidence Levels")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss this sheet")
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Berean labels every AI statement so you always know what's certain vs. what's an interpretation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var confidenceLevelsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Confidence Levels")
                .font(.headline)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(BereanConfidenceLevel.allCases) { level in
                    confidenceLevelRow(for: level)

                    if level != BereanConfidenceLevel.allCases.last {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func confidenceLevelRow(for level: BereanConfidenceLevel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(dotColor(for: level))
                .frame(width: 12, height: 12)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(level.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(level.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.displayName): \(level.explanation)")
    }

    private var whyItMattersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why does this matter?")
                .font(.headline)

            Text(
                "AI systems can present guesses with the same confidence as established facts. " +
                "Epistemic transparency — being clear about what we know vs. what we think vs. what we're uncertain about — " +
                "is foundational to truth-seeking. Berean's confidence labels help you engage critically with AI output " +
                "so you can verify what matters, trust what's established, and hold speculation lightly."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    /// Returns the colored dot color that visually matches `BereanOSConfidenceBadge`.
    private func dotColor(for level: BereanConfidenceLevel) -> Color {
        switch level {
        case .certain:      return .green
        case .probable:     return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .uncertain:    return .orange
        case .speculative:  return .yellow
        case .unsupported:  return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    BereanTruthDisclosureSheet()
}
#endif
