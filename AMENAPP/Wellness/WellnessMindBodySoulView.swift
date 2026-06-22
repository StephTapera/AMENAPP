import SwiftUI

// MARK: - Active Sheet

enum WellnessActiveSheet: Identifiable {
    case breathing, sleep, movement
    var id: String { String(describing: self) }
}

// MARK: - Main View

struct WellnessMindBodySoulView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var insightEngine = WellnessLocalInsightEngine.shared

    @State private var selectedMood: WellnessMood = .heavy
    @State private var selectedTab: WellnessDisplayTab = .tools
    @State private var selectedCareChoice: WellnessCareChoice = .talk
    @State private var rhythmContext: WellnessRhythmContext = .current
    @State private var friendExpanded = false
    @State private var activeSheet: WellnessActiveSheet?

    private var rankedTools: [WellnessSmartTool] {
        WellnessToolRegistry.ranked(mood: selectedMood, rhythm: rhythmContext)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                WellnessHeroBanner(onDismiss: { dismiss() }, reduceMotion: reduceMotion)

                VStack(alignment: .leading, spacing: 16) {
                    WellnessCrisisSurfaceCard(friendExpanded: $friendExpanded)

                    WellnessTabRow(selectedTab: $selectedTab)

                    WellnessMoodBereanSection(
                        selectedMood: $selectedMood,
                        selectedCareChoice: $selectedCareChoice,
                        reduceMotion: reduceMotion
                    )

                    WellnessSmartToolsGrid(tools: rankedTools, onToolTap: handleToolTap)

                    WellnessRhythmCard(rhythm: rhythmContext)

                    WellnessTabContent(tab: selectedTab)

                    WellnessInsightSection(insightEngine: insightEngine)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground))
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .breathing: BreathingExerciseView()
            case .sleep: SleepHygieneView()
            case .movement: MovementWellnessView()
            }
        }
    }

    private func handleToolTap(_ name: String) {
        switch name {
        case "Breathing": activeSheet = .breathing
        case "Sleep":     activeSheet = .sleep
        case "Movement":  activeSheet = .movement
        default: break
        }
    }
}

// MARK: - Hero Banner

struct WellnessHeroBanner: View {
    let onDismiss: () -> Void
    let reduceMotion: Bool

    @State private var glowOffset: CGFloat = 0

    private let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.042, green: 0.228, blue: 0.235),
            Color(red: 0.055, green: 0.295, blue: 0.306),
            Color(red: 0.132, green: 0.432, blue: 0.376)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            heroGradient

            // Ambient glow
            if !reduceMotion {
                Circle()
                    .fill(Color(red: 0.20, green: 0.68, blue: 0.56).opacity(0.20))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: 160 + glowOffset, y: 30)
                    .animation(
                        .easeInOut(duration: 6).repeatForever(autoreverses: true),
                        value: glowOffset
                    )
            }

            // Subtle line texture
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 1)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                // Dismiss button
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("Adaptive")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.70))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .padding(.top, 60)
                .padding(.horizontal, 24)

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("WELLNESS & MENTAL HEALTH")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .tracking(3.0)
                        .foregroundStyle(.white.opacity(0.68))

                    Text("Mind,\nBody & Soul")
                        .font(.custom("OpenSans-Bold", size: 50))
                        .foregroundStyle(.white)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Faith-based care at every level of need.")
                        .font(.custom("OpenSans-Regular", size: 17))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .frame(height: 490)
        .onAppear {
            if !reduceMotion {
                glowOffset = 18
            }
        }
    }
}

#Preview {
    WellnessMindBodySoulView()
}
