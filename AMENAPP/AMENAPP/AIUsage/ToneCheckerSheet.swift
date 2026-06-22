import SwiftUI

struct ToneCheckerSheet: View {
    let text: String
    let context: String
    let isRestModeActive: Bool
    let onAcceptRewrite: (String) -> Void
    let onKeepOriginal: () -> Void
    let onSaveForMonday: (() -> Void)?

    @StateObject private var aiUsageService = AIUsageService.shared
    @State private var result: ToneCheckResult?
    @State private var isLoading = true
    @State private var selectedMode: ToneMode = .clear
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ToneMode: String, CaseIterable, Identifiable {
        case gentle = "Gentle"
        case clear = "Clear"
        case encouraging = "Encouraging"
        case pastoral = "Pastoral"
        case peacemaking = "Peacemaking"
        case directButKind = "Direct but kind"
        case scriptureGrounded = "Scripture-grounded"

        var id: String { rawValue }
        var apiValue: String {
            switch self {
            case .directButKind: return "direct_but_kind"
            case .scriptureGrounded: return "scripture_grounded"
            default: return rawValue.lowercased()
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if let result = result {
                    resultView(result)
                }
            }
            .navigationTitle("Tone Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onKeepOriginal() }
                }
            }
            .task { await loadToneCheck() }
        }
        .presentationDetents([.large])
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Checking tone...")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .accessibilityLabel("Loading tone check results")
    }

    private func resultView(_ result: ToneCheckResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Mode picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ToneMode.allCases) { mode in
                            Button(action: { selectedMode = mode; Task { await recheck(mode: mode) } }) {
                                Text(mode.rawValue)
                                    .font(.caption.weight(selectedMode == mode ? .semibold : .regular))
                                    .foregroundStyle(selectedMode == mode ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background {
                                        if selectedMode == mode {
                                            Capsule().fill(Color.primary.opacity(0.08))
                                        } else {
                                            Capsule().fill(Color.clear)
                                        }
                                    }
                                    .overlay(Capsule().stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                            }
                            .accessibilityLabel("\(mode.rawValue) tone mode\(selectedMode == mode ? ", selected" : "")")
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Score grid
                scoreGrid(result)
                    .padding(.horizontal, 24)

                // Concerns
                if !result.concerns.isEmpty {
                    concernsSection(result.concerns)
                        .padding(.horizontal, 24)
                }

                // Suggested rewrite
                if let rewrite = result.suggestedRewrite {
                    rewriteSection(rewrite)
                        .padding(.horizontal, 24)
                }

                // Sunday special
                if isRestModeActive && result.saveForMondayRecommended {
                    sundaySection
                        .padding(.horizontal, 24)
                }

                actionRow(result)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .padding(.top, 16)
        }
    }

    private func scoreGrid(_ result: ToneCheckResult) -> some View {
        let scores: [(String, Double)] = [
            ("Kindness", result.kindnessScore),
            ("Clarity", result.clarityScore),
            ("Humility", result.humilityScore),
            ("Peace", result.peaceScore),
            ("Truthfulness", result.truthfulnessScore),
            ("Pastoral", result.pastoralSensitivityScore)
        ]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Tone dimensions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
            ForEach(scores, id: \.0) { label, value in
                scoreRow(label: label, value: value)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func scoreRow(label: String, value: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1)).frame(height: 6)
                    Capsule().fill(scoreColor(value)).frame(width: geo.size.width * value, height: 6)
                        .animation(reduceMotion ? nil : .spring(response: 0.5), value: value)
                }
            }
            .frame(height: 6)
            Text("\(Int(value * 100))")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(value * 100)) out of 100")
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 0.7 { return .green.opacity(0.6) }
        if value >= 0.4 { return .orange.opacity(0.5) }
        return .red.opacity(0.4)
    }

    private func concernsSection(_ concerns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Considerations")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
            ForEach(concerns, id: \.self) { concern in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.systemScaled(5))
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 6)
                    Text(concern)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    private func rewriteSection(_ rewrite: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested version")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text(rewrite)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .padding(14)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var sundaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lord's Day Mode", systemImage: "moon.stars")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text("This may be a moment worth sitting with. You could save this for Monday and revisit with fresh eyes.")
                .font(.subheadline)
                .foregroundStyle(Color.primary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionRow(_ result: ToneCheckResult) -> some View {
        VStack(spacing: 10) {
            if let rewrite = result.suggestedRewrite {
                Button(action: { onAcceptRewrite(rewrite); dismiss() }) {
                    Text("Use suggested version")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary, in: Capsule())
                }
                .accessibilityLabel("Accept the suggested tone rewrite and use it")
            }

            if isRestModeActive, let saveForMonday = onSaveForMonday {
                Button(action: { saveForMonday(); dismiss() }) {
                    Text("Save for Monday")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("Save this as a draft to review on Monday")
            }

            Button(action: { onKeepOriginal(); dismiss() }) {
                Text("Keep original")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .accessibilityLabel("Keep original text without changes")
        }
    }

    private func loadToneCheck() async {
        result = await aiUsageService.evaluateTone(
            text: text,
            context: context,
            isRestModeActive: isRestModeActive
        )
        isLoading = false
    }

    private func recheck(mode: ToneMode) async {
        isLoading = true
        result = await aiUsageService.evaluateTone(
            text: text,
            context: "\(context):\(mode.apiValue)",
            isRestModeActive: isRestModeActive
        )
        isLoading = false
    }
}
