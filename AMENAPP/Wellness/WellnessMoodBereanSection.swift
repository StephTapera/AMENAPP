import SwiftUI

// MARK: - Mood + Berean Section

struct WellnessMoodBereanSection: View {
    @Binding var selectedMood: WellnessMood
    @Binding var selectedCareChoice: WellnessCareChoice
    let reduceMotion: Bool

    private var config: WellnessMoodConfig { selectedMood.config }

    var body: some View {
        VStack(spacing: 12) {
            // Mood check-in card
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("How are you?")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("One tap only")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(Color(red: 0.10, green: 0.44, blue: 0.42))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.88, green: 0.96, blue: 0.95))
                        .clipShape(Capsule())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WellnessMood.allCases) { mood in
                            WellnessMoodPill(
                                mood: mood,
                                isSelected: selectedMood == mood,
                                reduceMotion: reduceMotion
                            ) {
                                withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.80)) {
                                    selectedMood = mood
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 12, y: 5)

            // Scripture card
            WellnessScriptureCard(verse: config.verse, quote: config.quote)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                .id("scripture-\(selectedMood.rawValue)")
                .animation(reduceMotion ? .none : .spring(response: 0.40, dampingFraction: 0.82), value: selectedMood)

            // Berean Care Mode card
            WellnessCareModeCard(
                careOpeningLine: config.careOpeningLine,
                selectedCareChoice: $selectedCareChoice,
                reduceMotion: reduceMotion
            )
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            .id("care-\(selectedMood.rawValue)")
            .animation(reduceMotion ? .none : .spring(response: 0.40, dampingFraction: 0.82), value: selectedMood)
        }
    }
}

// MARK: - Mood Pill

private struct WellnessMoodPill: View {
    let mood: WellnessMood
    let isSelected: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(mood.rawValue)
                .font(.custom(isSelected ? "OpenSans-Bold" : "OpenSans-Regular", size: 14))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color.white.opacity(0.34))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.50), lineWidth: 1)
                )
                .shadow(color: isSelected ? .black.opacity(0.18) : .clear, radius: 6, y: 3)
                .scaleEffect(isSelected ? (reduceMotion ? 1.0 : 1.03) : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Scripture Card

private struct WellnessScriptureCard: View {
    let verse: String
    let quote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("STATE-AWARE VERSE")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .tracking(2.2)
                        .foregroundStyle(.secondary)
                    Text(verse)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("Adaptive")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(Color(red: 0.10, green: 0.44, blue: 0.42))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.88, green: 0.96, blue: 0.95))
                    .clipShape(Capsule())
            }
            Text("\u{201C}\(quote)\u{201D}")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scripture: \(verse) — \(quote)")
    }
}

// MARK: - Care Mode Card

private struct WellnessCareModeCard: View {
    let careOpeningLine: String
    @Binding var selectedCareChoice: WellnessCareChoice
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BEREAN CARE MODE")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.52))
                    Text(careOpeningLine)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("Care")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text("Berean supports therapy, pastoral care, and emergency services. It never replaces them.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.52))
                .lineSpacing(2)

            // Care choice buttons
            FlexHStack(items: WellnessCareChoice.allCases) { choice in
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedCareChoice = choice
                    }
                } label: {
                    Text(choice.rawValue)
                        .font(.custom(selectedCareChoice == choice ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 14))
                        .foregroundStyle(selectedCareChoice == choice ? Color(red: 0.10, green: 0.10, blue: 0.10) : .white.opacity(0.88))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(selectedCareChoice == choice ? Color(red: 0.98, green: 0.95, blue: 0.92) : Color.white.opacity(0.10))
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedCareChoice == choice ? Color.white.opacity(0.45) : Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.rawValue)
                .accessibilityAddTraits(selectedCareChoice == choice ? .isSelected : [])
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.13, blue: 0.13), Color(red: 0.06, green: 0.06, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

// MARK: - Flex HStack (wrapping row for care buttons)

private struct FlexHStack<T: Identifiable, Content: View>: View {
    let items: [T]
    let content: (T) -> Content

    init(items: [T], @ViewBuilder content: @escaping (T) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                content(item)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension WellnessCareChoice: Identifiable {
    var id: String { rawValue }
}
