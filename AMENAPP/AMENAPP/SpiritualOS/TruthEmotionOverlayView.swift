import SwiftUI

struct TruthEmotionOverlayView: View {
    let analysis: TruthEmotionAnalysis
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Two-panel card
                    VStack(spacing: 0) {
                        emotionPanel
                        Divider().padding(.horizontal, 16)
                        factualPanel
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(0.06), radius: 16, y: 6)
                    .padding(.horizontal, 20)

                    // Assumptions
                    if !analysis.assumptions.isEmpty {
                        assumptionsSection
                    }

                    // Reframes
                    if !analysis.reframes.isEmpty {
                        reframesSection
                    }

                    // Scripture anchor
                    if let scripture = analysis.scriptureAnchor {
                        scriptureAnchorCard(ref: scripture, text: analysis.scriptureText)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .navigationTitle("Discern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .accessibilityLabel("Close discernment view")
                }
            }
        }
    }

    private var emotionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What I feel", systemImage: "heart")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            if let claim = analysis.emotionalClaim {
                Text("\"\(claim)\"")
                    .font(.body.italic())
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What I feel: \(analysis.emotionalClaim ?? "")")
    }

    private var factualPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What may be true", systemImage: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            if let possibility = analysis.factualPossibility {
                Text("\"\(possibility)\"")
                    .font(.body)
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What may be true: \(analysis.factualPossibility ?? "")")
    }

    private var assumptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Possible assumptions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 20)

            ForEach(analysis.assumptions, id: \.self) { assumption in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    Text(assumption)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                }
                .padding(.horizontal, 20)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var reframesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Another way to see it")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 20)

            ForEach(analysis.reframes, id: \.self) { reframe in
                Text(reframe)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func scriptureAnchorCard(ref: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ref, systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            if let scriptureText = text {
                Text(scriptureText)
                    .font(.body.italic())
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Assumption Chip (reusable)

struct AssumptionChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1), in: Capsule())
            .accessibilityLabel("Assumption: \(text)")
    }
}
