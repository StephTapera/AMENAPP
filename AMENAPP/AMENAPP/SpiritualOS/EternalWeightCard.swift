import SwiftUI

struct EternalWeightCard: View {
    let signal: EternalWeightSignal
    @StateObject private var service = EternalWeightService.shared
    @State private var meaningPrompt: String?
    @State private var showReflection = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: signal.state.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(stateColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.state.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("Private reflection")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                confidencePill
            }

            Text(signal.state.description)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            if let prompt = signal.reflectionPrompt ?? meaningPrompt {
                Text(prompt)
                    .font(.subheadline.italic())
                    .foregroundStyle(Color.primary)
                    .padding(12)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }

            Button(action: { showReflection = true }) {
                Label("Reflect on this", systemImage: "thought.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Open reflection for this content's eternal weight")
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 5)
        .task { await loadPromptIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    private var confidencePill: some View {
        let pct = Int(signal.confidenceScore * 100)
        return Text("\(pct)%")
            .font(.caption2)
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private var stateColor: Color {
        switch signal.state {
        case .growing: return .blue
        case .neutral: return .secondary
        case .misaligned: return .orange
        case .needsReflection: return .purple.opacity(0.7)
        case .bearingFruit: return .green
        }
    }

    private func loadPromptIfNeeded() async {
        guard signal.reflectionPrompt == nil && meaningPrompt == nil else { return }
        meaningPrompt = await service.getMeaningPrompt(for: signal.contentId)
    }
}

// MARK: - Meaning Over Metrics View

struct MeaningOverMetricsView: View {
    @StateObject private var service = EternalWeightService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if service.signals.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            infoCard
                            ForEach(service.signals) { signal in
                                EternalWeightCard(signal: signal)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Meaning")
            .navigationBarTitleDisplayMode(.large)
            .task { service.startListening() }
        }
    }

    private var infoCard: some View {
        VStack(spacing: 8) {
            Text("What mattered, not what performed.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text("This is a private space to reflect on the meaning your words may have carried — not likes, reach, or engagement.")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf")
                .font(.systemScaled(40))
                .foregroundStyle(Color.secondary)
            Text("No signals yet.")
                .font(.headline)
            Text("Signals appear as your content generates prayer, encouragement, and reflection over time.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Fruit Over Time Timeline (compact)

struct FruitOverTimeTimeline: View {
    let signals: [EternalWeightSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Over time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            HStack(spacing: 4) {
                ForEach(signals.prefix(10)) { signal in
                    Circle()
                        .fill(stateColor(signal.state).opacity(0.6))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(signal.state.displayName)
                }
            }
        }
    }

    private func stateColor(_ state: EternalWeightState) -> Color {
        switch state {
        case .growing: return .blue
        case .neutral: return .secondary
        case .misaligned: return .orange
        case .needsReflection: return .purple
        case .bearingFruit: return .green
        }
    }
}

// MARK: - Walk With Christ Suggestion Sheet

struct WalkWithChristPathSuggestionSheet: View {
    let pattern: String
    let suggestedPath: String
    let onAccept: () -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            // Handle
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.systemScaled(36))
                    .foregroundStyle(Color.secondary)
                Text("A Walk suggested from your patterns")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(pattern)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested path")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                Text(suggestedPath)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 10) {
                Button(action: onAccept) {
                    Text("Start this Walk")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary, in: Capsule())
                }
                .accessibilityLabel("Start the suggested Walk with Christ path")

                Button(action: onDismiss) {
                    Text("Maybe later")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                .accessibilityLabel("Dismiss this suggestion")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
