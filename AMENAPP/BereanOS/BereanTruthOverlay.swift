import SwiftUI

// MARK: - View Modifier

extension View {
    /// Overlays a compact `BereanOSConfidenceBadge` in the top-trailing corner of the view.
    func bereanTruthLabel(_ level: BereanConfidenceLevel) -> some View {
        self.overlay(alignment: .topTrailing) {
            BereanOSConfidenceBadge(level: level, compact: true)
                .padding(4)
        }
    }
}

// MARK: - BereanInlineTruthLabel

/// A small superscript-style badge that, when tapped, reveals a popover with the
/// full explanation for the given confidence level.
struct BereanInlineTruthLabel: View {

    let level: BereanConfidenceLevel
    @State private var showExplanation = false

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            BereanOSConfidenceBadge(level: level, compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text("\(level.displayName): \(level.explanation). Tap to learn more.")
        )
        .popover(isPresented: $showExplanation) {
            explanationPopover
        }
    }

    // MARK: Private Subviews

    @ViewBuilder
    private var explanationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BereanOSConfidenceBadge(level: level, compact: false)
                Spacer()
                Button {
                    showExplanation = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            Text(level.explanation)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(minWidth: 240, maxWidth: 320)
        .presentationCompactAdaptation(.popover)
    }
}
