import SwiftUI

struct WeightOfWordsMeter: View {
    let score: WeightOfWordsScore
    let onAcceptRewrite: (String) -> Void
    let onKeepOriginal: () -> Void

    @StateObject private var service = WeightOfWordsService.shared
    @State private var isLoadingRewrite = false
    @State private var customRewrite: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Mirror header
            HStack(spacing: 10) {
                Image(systemName: score.scoreLabel.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(labelColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.scoreLabel.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("Private reflection")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                weightBar
            }

            Text(score.scoreLabel.mirrorMessage)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            // Flags (if any, shown gently)
            if !score.flags.isEmpty {
                flagChips
            }

            // Suggested rewrite
            if let rewrite = score.suggestedRewrite ?? customRewrite {
                rewritePanel(rewrite: rewrite)
            } else if score.scoreLabel == .heavy || score.scoreLabel == .sharp || score.scoreLabel == .harmful {
                loadRewriteButton
            }

            // Actions
            HStack(spacing: 12) {
                Button(action: onKeepOriginal) {
                    Text("Keep as written")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("Keep original text without changes")

                Spacer()
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var weightBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.1)).frame(height: 6)
                Capsule().fill(labelColor.opacity(0.7)).frame(width: geo.size.width * score.scoreValue, height: 6)
                    .animation(reduceMotion ? nil : .spring(response: 0.5), value: score.scoreValue)
            }
        }
        .frame(width: 80, height: 6)
        .accessibilityHidden(true)
    }

    private var labelColor: Color {
        switch score.scoreLabel {
        case .light: return .blue
        case .encouraging: return .green
        case .heavy: return .orange
        case .sharp: return .orange
        case .harmful: return .red.opacity(0.7)
        }
    }

    private var flagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(score.flags, id: \.rawValue) { flag in
                    Text(flagDisplayName(flag))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func flagDisplayName(_ flag: WordWeightFlag) -> String {
        switch flag {
        case .highCorrectionIntensity: return "High intensity"
        case .sarcasmDetected: return "Possible sarcasm"
        case .shameLanguage: return "Shame language"
        case .spiritualManipulation: return "Spiritual pressure"
        case .condemnationTone: return "Condemnation tone"
        case .highEncouragement: return "Very encouraging"
        case .lowHumility: return "Low humility"
        case .scriptureIntegrityRisk: return "Scripture context"
        }
    }

    private func rewritePanel(rewrite: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A gentler version")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text(rewrite)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
            Button(action: { onAcceptRewrite(rewrite) }) {
                Text("Use this version")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.primary, in: Capsule())
            }
            .accessibilityLabel("Accept the suggested gentler rewrite")
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var loadRewriteButton: some View {
        Button(action: {
            isLoadingRewrite = true
            Task {
                customRewrite = await service.generateGracefulRewrite(for: score.sourceText)
                isLoadingRewrite = false
            }
        }) {
            HStack(spacing: 8) {
                if isLoadingRewrite { ProgressView().scaleEffect(0.8) }
                Text(isLoadingRewrite ? "Finding a gentler way..." : "Rewrite with grace")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .disabled(isLoadingRewrite)
        .accessibilityLabel("Generate a gentler rewrite of your words")
    }
}

// MARK: - Tone Impact Card

struct ToneImpactCard: View {
    let score: WeightOfWordsScore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: score.scoreLabel.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text(score.scoreLabel.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
            Spacer()
            Text(score.scoreLabel.mirrorMessage)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Word weight: \(score.scoreLabel.displayName). \(score.scoreLabel.mirrorMessage)")
    }
}
